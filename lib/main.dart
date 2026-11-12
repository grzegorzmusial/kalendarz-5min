import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'calendar.dart';
import 'editor.dart';
import 'timeline.dart';

void main() => runApp(const CalendarApp());

class CalendarApp extends StatelessWidget {
  const CalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) {
      final colors = ColorScheme.fromSeed(
        seedColor: const Color(0xff5747bc),
        brightness: brightness,
      );
      return ThemeData(
        colorScheme: colors,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      );
    }

    return MaterialApp(
      title: 'Kalendarz 5 min',
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: const DayScreen(),
    );
  }
}

class DayScreen extends StatefulWidget {
  const DayScreen({super.key});

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> with WidgetsBindingObserver {
  final _store = CalendarStore();
  DateTime _day = dateOnly(DateTime.now());
  CalendarDay? _data;
  Timer? _refreshTimer;
  int _loadId = 0;
  int? _calendarId;
  bool _loading = true;
  bool _denied = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store.onChange(() {
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(milliseconds: 200), _load);
    });
    _load();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _store.onChange(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load({bool request = false}) async {
    final loadId = ++_loadId;
    final day = _day;
    try {
      final allowed = request
          ? await _store.requestPermission()
          : await _store.hasPermission();
      final data = allowed ? await _store.readDay(day) : null;
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _data = data;
        _denied = !allowed;
        _failed = false;
        _loading = false;
      });
    } on PlatformException {
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  void _select(DateTime day, {bool force = false}) {
    day = dateOnly(day);
    if (_day == day && !force) return;
    setState(() {
      _day = day;
      _data = null;
      _loading = true;
      _failed = false;
    });
    _load();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(1900),
      lastDate: DateTime(2199, 12, 31),
    );
    if (mounted && date != null) _select(date);
  }

  Future<void> _settings({bool permissions = false}) async {
    try {
      await _store.openSettings(permissions: permissions);
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Otwórz ustawienia ręcznie na telefonie.'),
          ),
        );
      }
    }
  }

  List<GoogleCalendar> get _writable =>
      _data?.calendars.where((calendar) => calendar.writable).toList() ?? [];

  void _add([DateTime? start]) {
    final writable = _writable;
    if (writable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Włącz kalendarz Google z prawem zapisu.'),
        ),
      );
      return;
    }
    final now = DateTime.now();
    final minutes = dateOnly(now) == _day
        ? slotAt(_day, now.difference(_day).inMinutes.toDouble())
        : 8 * 60;
    start ??= _day.add(Duration(minutes: minutes));
    final selected = writable.where((calendar) => calendar.id == _calendarId);
    _openEditor(start, selected.firstOrNull ?? writable.first);
  }

  Future<void> _openEditor(
    DateTime start,
    GoogleCalendar calendar, {
    CalendarEvent? event,
  }) async {
    final saved = await showDialog<({DateTime start, int calendarId})>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EventEditor(
        store: _store,
        calendars: _writable,
        calendarId: calendar.id,
        start: start,
        event: event,
      ),
    );
    if (!mounted || saved == null) return;
    _calendarId = saved.calendarId;
    if (event == null || dateOnly(event.start) == _day) {
      _select(saved.start, force: true);
    } else {
      await _load();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Zapisano w kalendarzu Google na urządzeniu.'),
      ),
    );
  }

  void _openEvent(CalendarEvent event) {
    final calendar = _data!.calendarFor(event);
    if (calendar.writable && event.canModify && !event.allDay) {
      _openEditor(event.start, calendar, event: event);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.label),
        content: Text(
          '${event.allDay ? 'Cały dzień' : '${clock(event.start)}–${clock(event.end)}'}\n'
          '${calendar.label}'
          '${calendar.writable && event.canModify ? '' : '\nTylko odczyt'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zamknij'),
          ),
          if (event.allDay && calendar.writable && event.canModify)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _openEditor(
                  DateTime(_day.year, _day.month, _day.day, 8),
                  calendar,
                  event: event,
                );
              },
              child: const Text('Zmień na 5 min'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final calendars = _data?.calendars ?? [];
    final canAdd = !_failed && !_loading && _writable.isNotEmpty;
    final syncEnabled = calendars.every((calendar) => calendar.sync);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalendarz 5 min'),
        actions: [
          IconButton(
            tooltip: 'Dzisiaj',
            onPressed: () => _select(DateTime.now()),
            icon: const Icon(Icons.today_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Opcje kalendarza',
            onSelected: (action) {
              if (action == 'refresh') {
                _load();
              } else {
                _settings(permissions: action == 'permission');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Odśwież')),
              PopupMenuItem(
                value: 'sync',
                child: Text('Ustawienia synchronizacji'),
              ),
              PopupMenuItem(
                value: 'permission',
                child: Text('Uprawnienia aplikacji'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _WeekHeader(day: _day, onSelect: _select, onPickDate: _pickDate),
            if (calendars.isNotEmpty)
              Material(
                color: syncEnabled
                    ? colors.surfaceContainer
                    : colors.tertiaryContainer,
                child: InkWell(
                  onTap: _settings,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          syncEnabled ? Icons.sync : Icons.sync_disabled,
                          size: 17,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            syncEnabled
                                ? 'Kalendarz Google'
                                : 'Synchronizacja jest wyłączona',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(child: _body()),
          ],
        ),
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              tooltip: 'Dodaj wydarzenie',
              onPressed: _add,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return _CalendarMessage(
        icon: Icons.error_outline,
        title: 'Nie udało się odczytać kalendarza',
        action: 'Spróbuj ponownie',
        onPressed: _load,
      );
    }
    if (_denied) {
      return _CalendarMessage(
        icon: Icons.calendar_month_outlined,
        title: 'Połącz kalendarz Google',
        detail: 'Zezwól na dostęp do kalendarza w Androidzie, aby wyświetlać i zapisywać wydarzenia.',
        action: 'Zezwól na dostęp',
        onPressed: () async {
          await _load(request: true);
          if (!mounted || !_denied) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Możesz nadać dostęp w ustawieniach aplikacji.',
              ),
              action: SnackBarAction(
                label: 'Ustawienia',
                onPressed: () => _settings(permissions: true),
              ),
            ),
          );
        },
      );
    }
    final data = _data!;
    if (data.calendars.isEmpty) {
      return _CalendarMessage(
        icon: Icons.sync_problem,
        title: 'Dodaj konto Google',
        detail: 'Dodaj konto Google do Androida i włącz synchronizację Kalendarza w ustawieniach konta.',
        action: 'Otwórz ustawienia',
        onPressed: _settings,
      );
    }
    return Timeline(
      key: ValueKey(_day),
      day: _day,
      data: data,
      onSlot: _add,
      onEvent: _openEvent,
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.day,
    required this.onSelect,
    required this.onPickDate,
  });

  final DateTime day;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = MaterialLocalizations.of(context);
    final monday = shiftDay(day, 1 - day.weekday);
    const weekdays = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];
    final today = dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Poprzedni tydzień',
                onPressed: () => onSelect(shiftDay(day, -7)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: onPickDate,
                  child: Text(
                    locale.formatMonthYear(day),
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Następny tydzień',
                onPressed: () => onSelect(shiftDay(day, 7)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (var index = 0; index < 7; index++)
                Expanded(
                  child: _WeekDay(
                    date: shiftDay(monday, index),
                    weekday: weekdays[index],
                    selected: day,
                    today: today,
                    onTap: onSelect,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.date,
    required this.weekday,
    required this.selected,
    required this.today,
    required this.onTap,
  });

  final DateTime date;
  final String weekday;
  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = date == selected;
    final foreground = active
        ? colors.onPrimary
        : date == today
        ? colors.primary
        : colors.onSurface;
    return Semantics(
      selected: active,
      button: true,
      label: MaterialLocalizations.of(context).formatFullDate(date),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => onTap(date),
          borderRadius: BorderRadius.circular(22),
          child: Column(
            children: [
              Text(weekday, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 3),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? colors.primary : null,
                  shape: BoxShape.circle,
                  border: date == today && !active
                      ? Border.all(color: foreground)
                      : null,
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarMessage extends StatelessWidget {
  const _CalendarMessage({
    required this.icon,
    required this.title,
    required this.action,
    required this.onPressed,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String action;
  final VoidCallback onPressed;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              if (detail != null) ...[
                const SizedBox(height: 10),
                Text(
                  detail!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(onPressed: onPressed, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }
}
