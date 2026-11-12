import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalendarz_5min/calendar.dart';
import 'package:kalendarz_5min/main.dart';

void main() {
  const channel = MethodChannel('calendar/android');

  test(
    'concurrent events get separate lanes and adjacent events reuse space',
    () {
      final day = DateTime(2026, 11, 12);
      CalendarEvent event(int id, int start, int duration) => CalendarEvent(
        id: id,
        calendarId: 1,
        title: 'Wydarzenie $id',
        start: day.add(Duration(minutes: start)),
        end: day.add(Duration(minutes: start + duration)),
      );
      final placed = placeEvents([
        event(1, 480, 5),
        event(2, 480, 5),
        event(3, 480, 5),
        event(4, 485, 5),
      ], day);
      expect(placed.take(3).map((entry) => entry.lane), [0, 1, 2]);
      expect(placed.map((entry) => entry.laneCount), [3, 3, 3, 1]);
      expect(slotAt(day, 488.9), 485);
      expect(slotAt(day, 1440), 1435);
    },
  );

  testWidgets(
    'creates a five-minute event on the grid and shortens an existing one',
    (tester) async {
      final payloads = <Map<Object?, Object?>>[];
      final now = DateTime.now();
      final start = now.subtract(const Duration(minutes: 5));
      final day = dateOnly(now);
      final onScreen = dateOnly(start) == day ? start : day;
      final end = onScreen.add(const Duration(minutes: 45));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'hasPermission':
                return true;
              case 'day':
                return {
                  'calendars': [
                    {
                      'id': 1,
                      'name': 'Osobisty',
                      'account': 'test@example.com',
                      'color': 0xff7656bc,
                      'writable': true,
                      'sync': false,
                    },
                  ],
                  'events': [
                    for (var id = 1; id <= 2; id++)
                      {
                        'id': id,
                        'calendarId': 1,
                        'title': id == 1 ? 'Spotkanie A' : 'Spotkanie B',
                        'start': onScreen.millisecondsSinceEpoch,
                        'end': end.millisecondsSinceEpoch,
                        'allDay': false,
                        'recurring': false,
                        'canModify': true,
                        'color': null,
                      },
                  ],
                };
              case 'save':
                payloads.add(call.arguments as Map<Object?, Object?>);
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await tester.pumpWidget(const CalendarApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Synchronizacja jest wyłączona'), findsNothing);
      expect(find.text('Kalendarz Google'), findsNothing);
      final first = find.text('Spotkanie A');
      final second = find.text('Spotkanie B');
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
      expect(
        tester.getTopLeft(first).dx,
        lessThan(tester.getTopLeft(second).dx),
      );
      await tester.tap(first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ustaw 5 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();
      expect(payloads.single['id'], 1);
      expect(payloads.single['start'], onScreen.millisecondsSinceEpoch);
      expect(payloads.single['end'], onScreen.millisecondsSinceEpoch + 300000);

      await tester.tap(find.byTooltip('Dodaj wydarzenie'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Przerwa');
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();
      expect(payloads.last['id'], isNull);
      final newStart = payloads.last['start']! as int;
      expect(newStart % 300000, 0);
      expect(payloads.last['end'], newStart + 300000);
      expect(tester.takeException(), isNull);
    },
  );
}
