import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:kalendarz_5min/calendar.dart';
import 'package:kalendarz_5min/timeline.dart';

void main() {
  final day = DateTime(2026, 1, 1);
  CalendarEvent event({bool writable = true}) => CalendarEvent(
    id: 1,
    calendarId: 1,
    title: 'Spotkanie',
    start: DateTime(2026, 1, 1, 9),
    end: DateTime(2026, 1, 1, 9, 30),
    canModify: writable,
  );
  final calendar = GoogleCalendar({
    'id': 1,
    'name': 'Osobisty',
    'account': 'test@example.com',
    'color': 0xff7656bc,
    'writable': true,
  });

  Future<void> showTimeline(
    WidgetTester tester,
    CalendarEvent initial,
    Future<bool> Function(CalendarEvent, DateTime, DateTime) save,
  ) async {
    var current = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) => Scaffold(
            body: Timeline(
              day: day,
              data: CalendarDay([calendar], [current]),
              onSlot: (_) {},
              onEvent: (_) {},
              onReschedule: (original, start, end) async {
                final saved = await save(original, start, end);
                if (saved) {
                  update(() => current = current.withTimes(start, end));
                }
                return saved;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'holding and moving preserves duration and snaps to five minutes',
    (tester) async {
      final changes = <(DateTime, DateTime)>[];
      await showTimeline(tester, event(), (original, start, end) async {
        changes.add((start, end));
        return true;
      });
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Spotkanie')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, [
        (DateTime(2026, 1, 1, 9, 10), DateTime(2026, 1, 1, 9, 40)),
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'end and start handles resize independently with a five-minute minimum',
    (tester) async {
      final changes = <(DateTime, DateTime)>[];
      await showTimeline(tester, event(), (original, start, end) async {
        changes.add((start, end));
        return true;
      });
      await tester.longPress(find.text('Spotkanie'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byTooltip('Zmień godzinę zakończenia'),
        const Offset(0, -125),
      );
      await tester.pumpAndSettle();
      expect(changes.last, (
        DateTime(2026, 1, 1, 9),
        DateTime(2026, 1, 1, 9, 5),
      ));

      await tester.longPress(find.text('Spotkanie'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byTooltip('Zmień godzinę rozpoczęcia'),
        const Offset(0, -50),
      );
      await tester.pumpAndSettle();
      expect(changes.last, (
        DateTime(2026, 1, 1, 8, 50),
        DateTime(2026, 1, 1, 9, 5),
      ));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read-only events cannot be moved', (tester) async {
    var writes = 0;
    await showTimeline(tester, event(writable: false), (
      original,
      start,
      end,
    ) async {
      writes++;
      return true;
    });
    await tester.longPress(find.text('Spotkanie'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Zmień godzinę rozpoczęcia'), findsNothing);
    expect(writes, 0);
  });
}
