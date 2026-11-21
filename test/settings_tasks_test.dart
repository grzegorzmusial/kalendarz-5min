import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kalendarz_5min/main.dart';
import 'package:kalendarz_5min/tasks.dart';
import 'package:kalendarz_5min/calendar.dart';
import 'package:kalendarz_5min/new_item_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('calendar/android');

  test(
    'saved OAuth configuration takes precedence over the bundled client',
    () async {
      var configured = 'manual-client';
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => configured);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await CalendarStore().taskClientId(), 'manual-client');
      configured = '';
      expect(
        await CalendarStore().taskClientId(),
        const String.fromEnvironment('GOOGLE_TASKS_CLIENT_ID'),
      );
    },
  );

  testWidgets('inline type switch preserves the event draft', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final calendar = GoogleCalendar({
      'id': 1,
      'name': 'Osobisty',
      'account': 'test@example.com',
      'color': 0xff7656bc,
      'writable': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: NewItemEditor(
          store: CalendarStore(),
          calendars: [calendar],
          calendarId: 1,
          start: DateTime(2026, 11, 21, 9, 25),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nowe wydarzenie'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Mój wpis');
    await tester.tap(find.byTooltip('Wydłuż o 5 minut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zadanie'));
    await tester.pumpAndSettle();
    expect(find.text('Nowe zadanie'), findsOneWidget);
    expect(find.text('Konfiguruj dostęp'), findsOneWidget);
    await tester.tap(find.text('Wydarzenie'));
    await tester.pumpAndSettle();
    expect(find.text('Mój wpis'), findsOneWidget);
    expect(find.text('09:25'), findsOneWidget);
    final duration = tester.widget<TextFormField>(
      find.byType(TextFormField).at(1),
    );
    expect(duration.controller!.text, '10');
    expect(tester.takeException(), isNull);
  });

  testWidgets('default calendar survives reopening and one-off overrides', (
    tester,
  ) async {
    int? savedDefault;
    final savedEvents = <Map<Object?, Object?>>[];
    final calendars = [
      for (final id in [1, 2])
        {
          'id': id,
          'name': id == 1 ? 'Osobisty' : 'Praca',
          'account': 'test@example.com',
          'color': 0xff7656bc,
          'writable': true,
        },
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'defaultCalendar':
          return savedDefault;
        case 'setDefaultCalendar':
          savedDefault = (call.arguments as Map)['calendarId'] as int;
          return null;
        case 'hasPermission':
          return true;
        case 'day':
          return {'calendars': calendars, 'events': []};
        case 'save':
          savedEvents.add(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(const CalendarApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opcje kalendarza'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Domyślny kalendarz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Praca · test@example.com'));
    await tester.pumpAndSettle();
    expect(savedDefault, 2);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const CalendarApp());
    await tester.pumpAndSettle();
    Future<void> openEvent() async {
      await tester.tap(find.byTooltip('Dodaj wydarzenie lub zadanie'));
      await tester.pumpAndSettle();
    }

    await openEvent();
    expect(find.text('Praca · test@example.com'), findsOneWidget);
    final dropdown = find.byType(DropdownButtonFormField<int>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Osobisty · test@example.com').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Jednorazowy wybór',
    );
    await tester.tap(find.text('Zapisz'));
    await tester.pumpAndSettle();
    expect(savedEvents.single['calendarId'], 1);
    expect(savedDefault, 2);

    await openEvent();
    expect(find.text('Praca · test@example.com'), findsOneWidget);
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();

    calendars.removeLast();
    await tester.tap(find.byTooltip('Opcje kalendarza'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Odśwież'));
    await tester.pumpAndSettle();
    await openEvent();
    expect(find.text('Osobisty · test@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'Google Tasks pagination, date, edit and completion use the API',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.headers['Authorization'], 'Bearer test-access-token');
        if (request.method == 'GET') {
          if (request.url.path.endsWith('/users/@me/lists')) {
            if (request.url.queryParameters['pageToken'] == 'next') {
              return http.Response(
                jsonEncode({
                  'items': [
                    {'id': 'b', 'title': 'Praca'},
                  ],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'items': [
                  {'id': 'a', 'title': 'Moje zadania'},
                ],
                'nextPageToken': 'next',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 't',
                  'title': 'Zadanie',
                  'due': '2026-11-21T00:00:00.000Z',
                  'status': 'needsAction',
                },
              ],
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'id': 't'}), 200);
      });
      final api = TasksApi(
        token: () async => 'test-access-token',
        client: client,
      );
      addTearDown(api.close);
      final lists = await api.lists();
      expect(lists.map((list) => list.id), ['a', 'b']);
      final tasks = await api.tasks('a');
      expect(tasks.single.due, DateTime(2026, 11, 21));
      expect(requests.last.url.queryParameters['showHidden'], 'true');
      await api.save(
        listId: 'a',
        title: ' Nowe ',
        notes: 'Opis',
        due: DateTime(2026, 11, 22, 17),
      );
      expect(requests.last.method, 'POST');
      expect(jsonDecode(requests.last.body), {
        'title': 'Nowe',
        'notes': 'Opis',
        'due': '2026-11-22T00:00:00.000Z',
      });
      await api.save(
        listId: 'a',
        title: 'Zmiana',
        notes: '',
        due: null,
        task: tasks.single,
      );
      expect(requests.last.method, 'PATCH');
      expect(requests.last.url.path, '/tasks/v1/lists/a/tasks/t');
      expect(jsonDecode(requests.last.body)['due'], isNull);
      await api.complete(tasks.single, true);
      expect(jsonDecode(requests.last.body), {'status': 'completed'});
      await api.complete(tasks.single, false);
      expect(jsonDecode(requests.last.body), {
        'status': 'needsAction',
        'completed': null,
      });
    },
  );

  test(
    'a failed task creation is reported without retrying the write',
    () async {
      var writes = 0;
      final api = TasksApi(
        token: () async => 'test',
        client: MockClient((request) async {
          writes++;
          return http.Response('{}', 503);
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.save(listId: 'a', title: 'Zadanie', notes: '', due: null),
        throwsA(isA<TasksFailure>()),
      );
      expect(writes, 1);
    },
  );
}
