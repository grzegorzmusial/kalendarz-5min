import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'calendar.dart';

class EventEditor extends StatefulWidget {
  const EventEditor({
    super.key,
    required this.store,
    required this.calendars,
    required this.calendarId,
    required this.start,
    this.event,
    this.typeSelector,
    this.titleController,
    this.onSavingChanged,
  });

  final CalendarStore store;
  final List<GoogleCalendar> calendars;
  final int calendarId;
  final DateTime start;
  final CalendarEvent? event;
  final Widget? typeSelector;
  final TextEditingController? titleController;
  final ValueChanged<bool>? onSavingChanged;

  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  final _form = GlobalKey<FormState>();
  late final _title =
      widget.titleController ??
      TextEditingController(text: widget.event?.title ?? '');
  late final _duration = TextEditingController(text: '$_originalMinutes');
  late int _calendarId = widget.calendarId;
  late DateTime _start = widget.start;
  bool _saving = false;
  bool _durationChanged = false;
  String? _error;

  Duration get _originalDuration =>
      (widget.event == null || widget.event!.allDay)
      ? const Duration(minutes: slotMinutes)
      : widget.event!.end.difference(widget.event!.start);

  int get _originalMinutes => _originalDuration.inMinutes < 1
      ? slotMinutes
      : (_originalDuration.inSeconds / 60).ceil();

  int? get _minutes => int.tryParse(_duration.text);

  DateTime? get _end {
    final minutes = _minutes;
    if (minutes == null || minutes < 1 || minutes > 5256000) return null;
    if (!_durationChanged && _originalDuration > Duration.zero) {
      return _start.add(_originalDuration);
    }
    return _start.add(Duration(minutes: minutes));
  }

  @override
  void dispose() {
    if (widget.titleController == null) _title.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _setDuration(int minutes) {
    setState(() {
      _duration.text = '$minutes';
      _durationChanged = true;
    });
  }

  void _stepDuration(int direction) {
    final minutes = _minutes ?? slotMinutes;
    final gridIndex = minutes / slotMinutes;
    final next = direction > 0 ? gridIndex.floor() + 1 : gridIndex.ceil() - 1;
    _setDuration((next * slotMinutes).clamp(slotMinutes, 5256000));
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final end = _end!;
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.onSavingChanged?.call(true);
    try {
      await widget.store.save(
        calendarId: _calendarId,
        title: _title.text.trim(),
        start: _start,
        end: end,
        event: widget.event,
      );
      if (mounted) {
        Navigator.pop(context, (start: _start, calendarId: _calendarId));
      }
    } on PlatformException {
      if (mounted) {
        widget.onSavingChanged?.call(false);
        setState(() {
          _saving = false;
          _error =
              'Nie udało się zapisać wydarzenia. Sprawdź dostęp do kalendarza.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = dateOnly(_start);
    final slots = List.generate(
      dayMinutes(day) ~/ slotMinutes,
      (index) => day.add(Duration(minutes: index * slotMinutes)),
    );
    if (widget.event != null &&
        !widget.event!.allDay &&
        !slots.contains(widget.event!.start)) {
      slots.add(widget.event!.start);
      slots.sort();
    }
    final end = _end;
    final localizations = MaterialLocalizations.of(context);
    final endLabel = end == null
        ? null
        : dateOnly(end) == day
        ? slotLabel(day, end)
        : '${localizations.formatShortDate(end)}, ${clock(end)}';
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.event == null ? 'Nowe wydarzenie' : 'Edytuj wydarzenie',
            ),
            if (widget.typeSelector != null) ...[
              const SizedBox(height: 12),
              widget.typeSelector!,
            ],
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localizations.formatFullDate(day)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Tytuł'),
                  validator: (value) =>
                      widget.event == null &&
                          (value == null || value.trim().isEmpty)
                      ? 'Wpisz tytuł'
                      : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<DateTime>(
                  initialValue: _start,
                  decoration: const InputDecoration(
                    labelText: 'Godzina rozpoczęcia',
                  ),
                  menuMaxHeight: 340,
                  items: [
                    for (final slot in slots)
                      DropdownMenuItem(
                        value: slot,
                        child: Text(slotLabel(day, slot)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _start = value!),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _duration,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Czas trwania (min)',
                        ),
                        onChanged: (_) =>
                            setState(() => _durationChanged = true),
                        validator: (_) {
                          final minutes = _minutes;
                          if (minutes == null || _end == null) {
                            return 'Podaj czas';
                          }
                          if (_durationChanged && minutes % slotMinutes != 0) {
                            return 'Wpisz wielokrotność 5';
                          }
                          return null;
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Skróć o 5 minut',
                      onPressed: _saving || (_minutes ?? 0) <= slotMinutes
                          ? null
                          : () => _stepDuration(-1),
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      tooltip: 'Wydłuż o 5 minut',
                      onPressed: _saving ? null : () => _stepDuration(1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => _setDuration(slotMinutes),
                      child: const Text('Ustaw 5 min'),
                    ),
                    if (endLabel != null) Text('Koniec o $endLabel'),
                  ],
                ),
                if (widget.event == null && widget.calendars.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: _calendarId,
                    decoration: const InputDecoration(
                      labelText: 'Kalendarz Google',
                    ),
                    items: [
                      for (final calendar in widget.calendars)
                        DropdownMenuItem(
                          value: calendar.id,
                          child: Text(
                            calendar.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _calendarId = value!),
                  ),
                ],
                if (widget.calendars.isEmpty)
                  const Text('Włącz kalendarz Google z prawem zapisu.'),
                if (widget.event?.recurring == true)
                  const Text('Zmiana dotyczy tego wystąpienia.'),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: _saving || widget.calendars.isEmpty ? null : _save,
            child: Text(_saving ? 'Zapisywanie…' : 'Zapisz'),
          ),
        ],
      ),
    );
  }
}
