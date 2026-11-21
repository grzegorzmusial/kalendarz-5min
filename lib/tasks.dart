import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'calendar.dart';

class TasksFailure implements Exception {
  const TasksFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class TasksAuth {
  TasksAuth._();
  static final instance = TasksAuth._();
  static const scopes = ['https://www.googleapis.com/auth/tasks'];
  final _signIn = GoogleSignIn.instance;
  Future<void>? _initialization;
  String? _initializedClientId;
  GoogleSignInAccount? _account;
  String? get email => _account?.email;

  Future<void> _initialize() async {
    final clientId = (await CalendarStore().taskClientId()).trim();
    if (clientId.isEmpty) {
      throw const TasksFailure(
        'Skonfiguruj dostęp do Zadań Google w menu pod trzema kropkami.',
      );
    }
    if (_initializedClientId != null && _initializedClientId != clientId) {
      throw const TasksFailure(
        'Zamknij i uruchom aplikację ponownie po zmianie konfiguracji.',
      );
    }
    _initializedClientId = clientId;
    _initialization ??= _signIn.initialize(serverClientId: clientId);
    await _initialization;
  }

  Future<void> connect() async {
    await _initialize();
    _account = await _signIn.authenticate(scopeHint: scopes);
    await _account!.authorizationClient.authorizeScopes(scopes);
  }

  Future<String> token() async {
    await _initialize();
    _account ??= await _signIn.attemptLightweightAuthentication();
    final account = _account;
    if (account == null) {
      throw const TasksFailure('Połącz konto Google, aby wyświetlić zadania.');
    }
    final authorization = await account.authorizationClient
        .authorizationForScopes(scopes);
    if (authorization == null) {
      throw const TasksFailure(
        'Połącz konto Google i zezwól na dostęp do zadań.',
      );
    }
    return authorization.accessToken;
  }

  Future<void> disconnect() async {
    await _initialize();
    await _signIn.signOut();
    _account = null;
  }
}

String tasksError(Object error) {
  if (error is TasksFailure) return error.message;
  if (error is GoogleSignInException) {
    if (error.code == GoogleSignInExceptionCode.canceled) {
      return 'Logowanie zostało anulowane. Jeśli błąd powtarza się po wyborze konta, sprawdź konfigurację OAuth.';
    }
    if (error.code == GoogleSignInExceptionCode.clientConfigurationError) {
      return 'Sprawdź identyfikator klienta webowego OAuth, nazwę pakietu Android i odcisk SHA-1 w Google Cloud.';
    }
    return 'Nie udało się połączyć konta Google. Spróbuj ponownie.';
  }
  if (error is TimeoutException || error is http.ClientException) {
    return 'Nie udało się połączyć z Zadaniami Google. Sprawdź połączenie z internetem.';
  }
  return 'Nie udało się wykonać operacji w Zadaniach Google.';
}

class GoogleTaskList {
  const GoogleTaskList(this.id, this.title);
  factory GoogleTaskList.fromJson(Map<String, dynamic> json) => GoogleTaskList(
    json['id'] as String,
    json['title'] as String? ?? 'Lista zadań',
  );
  final String id;
  final String title;
}

class TaskSchedule {
  TaskSchedule(DateTime start, DateTime end, {DateTime? sourceDate})
    : start = start.toLocal(),
      end = end.toLocal(),
      sourceDate = sourceDate ?? dateOnly(start.toLocal()) {
    if (!end.isAfter(start)) throw ArgumentError('Task end must follow start');
  }
  final DateTime start;
  final DateTime end;
  final DateTime sourceDate;
  Duration get duration => end.difference(start);
  int get minutes => (duration.inMilliseconds / 60000).ceil();

  TaskSchedule onDate(DateTime date) {
    if (dateOnly(sourceDate) == dateOnly(date)) return this;
    final offset = DateTime.utc(date.year, date.month, date.day)
        .difference(
          DateTime.utc(sourceDate.year, sourceDate.month, sourceDate.day),
        )
        .inDays;
    final moved = DateTime(
      start.year,
      start.month,
      start.day + offset,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
    return TaskSchedule(moved, moved.add(duration), sourceDate: dateOnly(date));
  }
}

final _scheduleBlock = RegExp(
  r'(?:^|\r?\n(?:\r?\n)?)\[Kalendarz 5 min\]\r?\n([^\r\n]+) / ([^\r\n]+)\r?\n\[/Kalendarz 5 min\](?=$|\r?\n)',
);

({String notes, TaskSchedule? schedule}) readTaskNotes(String notes) {
  for (final match in _scheduleBlock.allMatches(notes)) {
    final start = DateTime.tryParse(match.group(1)!);
    final end = DateTime.tryParse(match.group(2)!);
    final startText = match.group(1)!;
    final sourceDate = startText.indexOf('T') == 10
        ? DateTime.tryParse(startText.substring(0, 10))
        : null;
    if (start != null &&
        end != null &&
        sourceDate != null &&
        end.isAfter(start)) {
      return (
        notes: notes.replaceRange(match.start, match.end, ''),
        schedule: TaskSchedule(start, end, sourceDate: sourceDate),
      );
    }
  }
  return (notes: notes, schedule: null);
}

String writeTaskNotes(String notes, TaskSchedule? schedule) {
  final cleanNotes = readTaskNotes(notes).notes;
  if (schedule == null) return cleanNotes;
  String timestamp(DateTime value) {
    final local = value.toLocal();
    final offset = local.timeZoneOffset.inMinutes;
    final hours = (offset.abs() ~/ 60).toString().padLeft(2, '0');
    final minutes = (offset.abs() % 60).toString().padLeft(2, '0');
    return '${local.toIso8601String()}${offset < 0 ? '-' : '+'}$hours:$minutes';
  }

  final block =
      '[Kalendarz 5 min]\n${timestamp(schedule.start)} / ${timestamp(schedule.end)}\n[/Kalendarz 5 min]';
  return cleanNotes.isEmpty ? block : '$cleanNotes\n\n$block';
}

class GoogleTask {
  const GoogleTask({
    required this.id,
    required this.listId,
    required this.title,
    this.notes = '',
    this.due,
    this.completed = false,
    this.schedule,
    this.etag,
  });
  factory GoogleTask.fromJson(Map<String, dynamic> json, String listId) {
    final due = DateTime.tryParse(json['due'] as String? ?? '');
    final parsed = readTaskNotes(json['notes'] as String? ?? '');
    return GoogleTask(
      id: json['id'] as String,
      listId: listId,
      title: json['title'] as String? ?? '',
      notes: parsed.notes,
      due: due == null ? null : DateTime(due.year, due.month, due.day),
      completed: json['status'] == 'completed',
      schedule: due == null ? null : parsed.schedule?.onDate(due),
      etag: json['etag'] as String?,
    );
  }
  final String id;
  final String listId;
  final String title;
  final String notes;
  final DateTime? due;
  final bool completed;
  final TaskSchedule? schedule;
  final String? etag;

  CalendarEvent get calendarEvent => CalendarEvent(
    id: -1,
    calendarId: -1,
    title: title,
    start: schedule!.start,
    end: schedule!.end,
    color: 0xff277c55,
    taskId: id,
    taskListId: listId,
  );
}

class TasksApi {
  TasksApi({required this.token, http.Client? client})
    : _client = client ?? http.Client();
  final Future<String> Function() token;
  final http.Client _client;

  void close() => _client.close();

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    String? etag,
  }) async {
    final accessToken = await token();
    final request = http.Request(
      method,
      Uri.parse('https://tasks.googleapis.com/tasks/v1/$path')
          .replace(queryParameters: query),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json; charset=utf-8',
      'If-Match': ?etag,
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 20)),
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode == 401) {
      throw const TasksFailure(
        'Dostęp do Zadań Google wygasł. Połącz konto ponownie.',
      );
    }
    if (response.statusCode == 403) {
      throw const TasksFailure(
        'Brak dostępu do Google Tasks API. Sprawdź zgodę na dostęp i konfigurację projektu Google Cloud.',
      );
    }
    if (response.statusCode == 404) {
      throw const TasksFailure(
        'Zadanie lub lista zostały usunięte. Odśwież listę.',
      );
    }
    if (response.statusCode == 412) {
      throw const TasksFailure(
        'Zadanie zmieniło się na innym urządzeniu. Odśwież je przed ponownym zapisem.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const TasksFailure(
        'Google nie potwierdził zapisu lub odczytu. Odśwież listę przed ponowną próbą.',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> _pages(
    String path,
    Map<String, String> query,
  ) async {
    final result = <Map<String, dynamic>>[];
    String? page;
    do {
      final json = await _request(
        'GET',
        path,
        query: {...query, 'pageToken': ?page},
      );
      result.addAll(
        (json['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      );
      page = json['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    return result;
  }

  Future<List<GoogleTaskList>> lists() async => (await _pages(
    'users/@me/lists',
    {'maxResults': '100'},
  )).map(GoogleTaskList.fromJson).toList();

  Future<List<GoogleTask>> tasks(
    String listId, {
    bool includeCompleted = true,
  }) async => (await _pages('lists/${Uri.encodeComponent(listId)}/tasks', {
    'maxResults': '100',
    'showCompleted': '$includeCompleted',
    'showHidden': '$includeCompleted',
    'showDeleted': 'false',
  })).map((json) => GoogleTask.fromJson(json, listId)).toList();

  Future<void> save({
    required String listId,
    required String title,
    required String notes,
    required DateTime? due,
    GoogleTask? task,
    TaskSchedule? schedule,
    bool removeSchedule = false,
  }) async {
    final path = 'lists/${Uri.encodeComponent(listId)}/tasks';
    final plan = due == null || removeSchedule
        ? null
        : schedule ?? task?.schedule?.onDate(due);
    final combinedNotes = writeTaskNotes(notes, plan);
    final date = plan?.start ?? due;
    if (combinedNotes.length > 8192) {
      throw const TasksFailure(
        'Notatka wraz z terminem może mieć maksymalnie 8192 znaków.',
      );
    }
    await _request(
      task == null ? 'POST' : 'PATCH',
      task == null ? path : '$path/${Uri.encodeComponent(task.id)}',
      body: {
        'title': title.trim(),
        'notes': combinedNotes,
        'due': date == null
            ? null
            : DateTime.utc(date.year, date.month, date.day).toIso8601String(),
      },
      etag: task?.etag,
    );
  }

  Future<List<GoogleTask>> scheduledTasks() async {
    final result = <GoogleTask>[];
    for (final list in await lists()) {
      result.addAll(
        (await tasks(
          list.id,
          includeCompleted: false,
        )).where((task) => !task.completed && task.schedule != null),
      );
    }
    return result;
  }

  Future<GoogleTask> task(
    String listId,
    String id,
  ) async => GoogleTask.fromJson(
    await _request(
      'GET',
      'lists/${Uri.encodeComponent(listId)}/tasks/${Uri.encodeComponent(id)}',
    ),
    listId,
  );

  Future<GoogleTask> reschedule(
    GoogleTask task,
    DateTime start,
    DateTime end,
  ) async {
    final path =
        'lists/${Uri.encodeComponent(task.listId)}/tasks/${Uri.encodeComponent(task.id)}';
    final current = await this.task(task.listId, task.id);
    final plan = TaskSchedule(start, end);
    final notes = writeTaskNotes(current.notes, plan);
    if (notes.length > 8192) {
      throw const TasksFailure('Notatka jest za długa, aby zapisać termin.');
    }
    final updated = await _request(
      'PATCH',
      path,
      body: {
        'notes': notes,
        'due': DateTime.utc(
          plan.start.year,
          plan.start.month,
          plan.start.day,
        ).toIso8601String(),
      },
      etag: current.etag,
    );
    return GoogleTask.fromJson(updated, task.listId);
  }

  Future<void> complete(GoogleTask task, bool completed) async {
    await _request(
      'PATCH',
      'lists/${Uri.encodeComponent(task.listId)}/tasks/${Uri.encodeComponent(task.id)}',
      body: {
        'status': completed ? 'completed' : 'needsAction',
        if (!completed) 'completed': null,
      },
    );
  }
}
