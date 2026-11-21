import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'calendar.dart';

class TimeFields extends StatelessWidget {
  const TimeFields({
    super.key,
    required this.start,
    required this.end,
    required this.duration,
    required this.onStartChanged,
    required this.onDurationChanged,
    required this.enabled,
    this.allowOriginalDuration = false,
  });
  final DateTime start;
  final DateTime? end;
  final TextEditingController duration;
  final ValueChanged<DateTime> onStartChanged;
  final VoidCallback onDurationChanged;
  final bool enabled;
  final bool allowOriginalDuration;

  void _setDuration(int minutes) {
    duration.text = '$minutes';
    onDurationChanged();
  }

  void _step(int direction) {
    final minutes = int.tryParse(duration.text) ?? slotMinutes;
    final grid = minutes / slotMinutes;
    final next = direction > 0 ? grid.floor() + 1 : grid.ceil() - 1;
    _setDuration((next * slotMinutes).clamp(slotMinutes, 5256000));
  }

  @override
  Widget build(BuildContext context) {
    final day = dateOnly(start);
    final slots = List.generate(
      dayMinutes(day) ~/ slotMinutes,
      (index) => day.add(Duration(minutes: index * slotMinutes)),
    );
    if (!slots.contains(start)) {
      slots.add(start);
      slots.sort();
    }
    final locale = MaterialLocalizations.of(context);
    final finish = end;
    final endLabel = finish == null
        ? null
        : dateOnly(finish) == day
        ? slotLabel(day, finish)
        : '${locale.formatShortDate(finish)}, ${clock(finish)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<DateTime>(
          key: ValueKey(start),
          initialValue: start,
          decoration: const InputDecoration(labelText: 'Godzina rozpoczęcia'),
          menuMaxHeight: 340,
          items: [
            for (final slot in slots)
              DropdownMenuItem(value: slot, child: Text(slotLabel(day, slot))),
          ],
          onChanged: enabled ? (value) => onStartChanged(value!) : null,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: duration,
                enabled: enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Czas trwania (min)',
                ),
                onChanged: (_) => onDurationChanged(),
                validator: (_) {
                  final minutes = int.tryParse(duration.text);
                  if (minutes == null || minutes < 1 || minutes > 5256000) {
                    return 'Podaj czas';
                  }
                  if (!allowOriginalDuration &&
                      (minutes < slotMinutes || minutes % slotMinutes != 0)) {
                    return 'Wpisz wielokrotność 5';
                  }
                  return null;
                },
              ),
            ),
            IconButton(
              tooltip: 'Skróć o 5 minut',
              onPressed:
                  !enabled || (int.tryParse(duration.text) ?? 0) <= slotMinutes
                  ? null
                  : () => _step(-1),
              icon: const Icon(Icons.remove),
            ),
            IconButton(
              tooltip: 'Wydłuż o 5 minut',
              onPressed: enabled ? () => _step(1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: enabled ? () => _setDuration(slotMinutes) : null,
              child: const Text('Ustaw 5 min'),
            ),
            if (endLabel != null) Text('Koniec o $endLabel'),
          ],
        ),
      ],
    );
  }
}
