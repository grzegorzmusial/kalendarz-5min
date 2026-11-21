import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kalendarz_5min/calendar.dart';
import 'package:kalendarz_5min/main.dart';
import 'package:kalendarz_5min/tasks.dart';
import 'package:kalendarz_5min/tasks_screen.dart';
import 'package:kalendarz_5min/timeline.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a schedule imported from another time zone keeps its exact instant',
    () {
      final task = GoogleTask.fromJson({
        'id': 't',
        'title': 'Podróż',
        'due': '2026-11-21T00:00:00Z',
        'notes': '[Kalendarz 5 min]\n2026-11-21T00:05:00+14:00 / 2026-11-21T00:10:00+14:00\n[/Kalendarz 5 min]',
      }, 'l');
      expect(task.schedule!.start.toUtc(), DateTime.utc(2026, 11, 20, 10, 5));
      expect(task.schedule!.end.toUtc(), DateTime.utc(2026, 11, 20, 10, 10));
    },
  );

  test('scheduled task notes round-trip and preserve text', () {
    final plan = TaskSchedule(
      DateTime(2026, 11, 21, 9, 25),
      DateTime(2026, 11, 21, 9, 30),
    );
    const text = 'Pierwsza linia\nDruga linia  ';
    final encoded = writeTaskNotes(text, plan);
    final decoded = readTaskNotes(encoded);
    expect(decoded.notes, text);
    expect(decoded.schedule!.start, plan.start);
    expect(decoded.schedule!.end, plan.end);
    expect(writeTaskNotes(encoded, plan), encoded);
    expect(writeTaskNotes(encoded, null), text);
    expect(
      readTaskNotes('$encoded\n\nDopisane w Google').notes,
      '$text\n\nDopisane w Google',
    );
    expect(
      readTaskNotes(encoded.replaceAll('\n', '\r\n')).schedule!.start,
      plan.start,
    );
    const malformed =
        '[Kalendarz 5 min]\nniepoprawny termin / brak\n[/Kalendarz 5 min]';
    expect(readTaskNotes(malformed).notes, malformed);
    expect(readTaskNotes(malformed).schedule, isNull);
  });

  test('Google due-date changes move the plan and clearing the date removes timing', () {
    final plan = TaskSchedule(
      DateTime(2026, 11, 21, 23, 55),
      DateTime(2026, 11, 22, 0, 10),
    );
    final json = <String, dynamic>{
      'id': 't',
      'title': 'Plan',
      'notes': writeTaskNotes('Opis', plan),
      'due': '2026-11-23T00:00:00Z',
      'status': 'needsAction',
    };
    final moved = GoogleTask.fromJson(json, 'l');
    expect(moved.schedule!.start, DateTime(2026, 11, 23, 23, 55));
    expect(moved.schedule!.end, DateTime(2026, 11, 24, 0, 10));
    expect(moved.notes, 'Opis');
    json['due'] = null;
    expect(GoogleTask.fromJson(json, 'l').schedule, isNull);
    expect(GoogleTask.fromJson(json, 'l').notes, 'Opis');
  });

  test('rescheduling reads fresh notes and uses the current ETag', () async {
    final plan = TaskSchedule(
      DateTime(2026, 11, 21, 9),
      DateTime(2026, 11, 21, 9, 5),
    );
    final requests = <http.Request>[];
    final api = TasksApi(
      token: () async => 'token',
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'id': 't',
              'title': 'Nowy tytuł z Google',
              'notes': writeTaskNotes('Nowa notatka z Google', plan),
              'due': '2026-11-21T00:00:00Z',
              'etag': '"fresh"',
            }),
            200,
            headers: _jsonHeaders,
          );
        }
        expect(request.headers['If-Match'], '"fresh"');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 't', 'title': 'Nowy tytuł z Google', ...body}),
          200,
          headers: _jsonHeaders,
        );
      }),
    );
    addTearDown(api.close);
    const cached = GoogleTask(
      id: 't',
      listId: 'l',
      title: 'Stary tytuł',
      notes: 'Stara notatka',
      etag: '"old"',
    );
    final updated = await api.reschedule(
      cached,
      DateTime(2026, 11, 21, 10),
      DateTime(2026, 11, 21, 10, 15),
    );
    expect(updated.notes, 'Nowa notatka z Google');
    expect(updated.schedule!.start, DateTime(2026, 11, 21, 10));
    expect(jsonDecode(requests.last.body).containsKey('title'), isFalse);
    expect(requests.length, 2);
  });

  testWidgets('a new task defaults to the tapped time and five minutes', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    final api = TasksApi(
      token: () async => 'token',
      client: MockClient((request) async {
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 't', ...saved!}),
          200,
          headers: _jsonHeaders,
        );
      }),
    );
    addTearDown(api.close);
    final start = DateTime(2026, 11, 21, 9, 25);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => TaskEditor(
                  api: api,
                  lists: const [GoogleTaskList('l', 'Moje zadania')],
                  listId: 'l',
                  date: start,
                  initialStart: start,
                ),
              ),
              child: const Text('Otwórz'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Otwórz'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Zadanie z godziną',
    );
    expect(find.text('09:25'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      '5',
    );
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    final task = GoogleTask.fromJson({'id': 't', ...saved!}, 'l');
    expect(task.schedule!.start, start);
    expect(task.schedule!.end, start.add(const Duration(minutes: 5)));
    expect(task.notes, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scheduled tasks appear on the calendar and drag through Tasks API',
    (tester) async {
      const channel = MethodChannel('calendar/android');
      final nativeWrites = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'hasPermission':
            return true;
          case 'day':
            return {'calendars': [], 'events': []};
          case 'save':
            nativeWrites.add(call);
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final now = DateTime.now();
      final day = dateOnly(now);
      final minutes =
          (slotAt(day, now.difference(day).inMinutes.toDouble()) - 5).clamp(
            0,
            dayMinutes(day) - 90,
          );
      final start = day.add(Duration(minutes: minutes));
      final end = start.add(const Duration(minutes: 30));
      var task = <String, dynamic>{
        'id': 't',
        'title': 'Zaplanowane zadanie',
        'notes': writeTaskNotes('Notatka', TaskSchedule(start, end)),
        'due': DateTime.utc(day.year, day.month, day.day).toIso8601String(),
        'etag': '"v1"',
        'status': 'needsAction',
      };
      final otherTask = {...task, 'title': 'Równoległe zadanie'};
      var patches = 0;
      final api = TasksApi(
        token: () async => 'token',
        client: MockClient((request) async {
          if (request.method == 'PATCH') {
            patches++;
            task = {
              ...task,
              ...jsonDecode(request.body) as Map<String, dynamic>,
              'etag': '"v2"',
            };
            return http.Response(jsonEncode(task), 200, headers: _jsonHeaders);
          }
          if (request.url.path.endsWith('users/@me/lists')) {
            return http.Response(
              jsonEncode({
                'items': [
                  {'id': 'l', 'title': 'Moje zadania'},
                  {'id': 'l2', 'title': 'Druga lista'},
                ],
              }),
              200,
              headers: _jsonHeaders,
            );
          }
          if (request.url.path.endsWith('/tasks/t')) {
            return http.Response(jsonEncode(task), 200, headers: _jsonHeaders);
          }
          expect(request.url.queryParameters['showCompleted'], 'false');
          return http.Response(
            jsonEncode({
              'items': [request.url.path.contains('/l2/') ? otherTask : task],
            }),
            200,
            headers: _jsonHeaders,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(MaterialApp(home: DayScreen(tasksApi: api)));
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(Timeline),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      scroll.jumpTo((minutes - 30).clamp(0, dayMinutes(day)).toDouble() * 5);
      await tester.pumpAndSettle();
      final block = find.text('☐ Zaplanowane zadanie');
      expect(block, findsOneWidget);
      expect(find.text('☐ Równoległe zadanie'), findsOneWidget);
      final gesture = await tester.startGesture(tester.getCenter(block));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final updated = GoogleTask.fromJson(task, 'l');
      expect(updated.schedule!.start, start.add(const Duration(minutes: 10)));
      expect(updated.schedule!.end, end.add(const Duration(minutes: 10)));
      expect(patches, 1);
      await tester.longPress(block);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byTooltip('Zmień godzinę zakończenia'),
        const Offset(0, 25),
      );
      await tester.pumpAndSettle();
      final resized = GoogleTask.fromJson(task, 'l');
      expect(resized.schedule!.start, start.add(const Duration(minutes: 10)));
      expect(resized.schedule!.end, end.add(const Duration(minutes: 15)));
      expect(patches, 2);
      expect(nativeWrites, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
