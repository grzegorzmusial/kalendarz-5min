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

class GoogleTask {
  const GoogleTask({
    required this.id,
    required this.listId,
    required this.title,
    this.notes = '',
    this.due,
    this.completed = false,
  });
  factory GoogleTask.fromJson(Map<String, dynamic> json, String listId) {
    final due = DateTime.tryParse(json['due'] as String? ?? '');
    return GoogleTask(
      id: json['id'] as String,
      listId: listId,
      title: json['title'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      due: due == null ? null : DateTime(due.year, due.month, due.day),
      completed: json['status'] == 'completed',
    );
  }
  final String id;
  final String listId;
  final String title;
  final String notes;
  final DateTime? due;
  final bool completed;
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

  Future<List<GoogleTask>> tasks(String listId) async =>
      (await _pages('lists/${Uri.encodeComponent(listId)}/tasks', {
        'maxResults': '100',
        'showCompleted': 'true',
        'showHidden': 'true',
        'showDeleted': 'false',
      })).map((json) => GoogleTask.fromJson(json, listId)).toList();

  Future<void> save({
    required String listId,
    required String title,
    required String notes,
    required DateTime? due,
    GoogleTask? task,
  }) async {
    final path = 'lists/${Uri.encodeComponent(listId)}/tasks';
    await _request(
      task == null ? 'POST' : 'PATCH',
      task == null ? path : '$path/${Uri.encodeComponent(task.id)}',
      body: {
        'title': title.trim(),
        'notes': notes,
        'due': due == null
            ? null
            : DateTime.utc(due.year, due.month, due.day).toIso8601String(),
      },
    );
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
