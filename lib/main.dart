import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'calendar.dart';
import 'editor.dart';
import 'new_item_editor.dart';
import 'timeline.dart';
import 'tasks_screen.dart';
import 'tasks.dart';

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
  const DayScreen({super.key, this.tasksApi});
  final TasksApi? tasksApi;

  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> with WidgetsBindingObserver {
  final _store = CalendarStore();
  late final _tasksApi =
      widget.tasksApi ?? TasksApi(token: TasksAuth.instance.token);
  List<GoogleTask> _scheduledTasks = [];
  int _tasksRequest = 0;
  DateTime _day = dateOnly(DateTime.now());
  CalendarDay? _data;
  Timer? _refreshTimer;
  int _loadId = 0;
  int? _defaultCalendarId;
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
    _load(reloadTasks: true);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _store.onChange(null);
    if (widget.tasksApi == null) _tasksApi.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(reloadTasks: true);
  }

  Future<void> _load({bool request = false, bool reloadTasks = false}) async {
    final loadId = ++_loadId;
    final day = _day;
    try {
      final defaultCalendarId = await _store.defaultCalendar();
      final allowed = request
          ? await _store.requestPermission()
          : await _store.hasPermission();
      final data = allowed ? await _store.readDay(day) : null;
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _data = data;
        _defaultCalendarId = defaultCalendarId;
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
    if (mounted && loadId == _loadId && reloadTasks) unawaited(_refreshTasks());
  }

  Future<void> _refreshTasks({bool showErrors = false}) async {
    final request = ++_tasksRequest;
    try {
      final tasks = await _tasksApi.scheduledTasks();
      if (!mounted || request != _tasksRequest) return;
      setState(() => _scheduledTasks = tasks);
    } catch (error) {
      if (!mounted || request != _tasksRequest) return;
      if (TasksAuth.instance.email == null && widget.tasksApi == null) {
        setState(() => _scheduledTasks = []);
      }
      if (showErrors) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tasksError(error))));
      }
    }
  }

  List<CalendarEvent> get _taskEvents => _scheduledTasks
      .where(
        (task) =>
            !task.completed &&
            task.schedule != null &&
            task.schedule!.start.isBefore(shiftDay(_day, 1)) &&
            task.schedule!.end.isAfter(_day),
      )
      .map((task) => task.calendarEvent)
      .toList();

  void _select(DateTime day) {
    day = dateOnly(day);
    if (_day == day) return;
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

  Future<void> _chooseDefaultCalendar() async {
    final calendars = _writable;
    if (calendars.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Włącz kalendarz Google z prawem zapisu.'),
        ),
      );
      return;
    }
    final selected =
        calendars.any((calendar) => calendar.id == _defaultCalendarId)
        ? _defaultCalendarId
        : calendars.first.id;
    final choice = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Domyślny kalendarz'),
        children: [
          for (final calendar in calendars)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, calendar.id),
              child: Row(
                children: [
                  Icon(
                    calendar.id == selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(calendar.label)),
                ],
              ),
            ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    try {
      await _store.setDefaultCalendar(choice);
      if (!mounted) return;
      ++_loadId;
      setState(() => _defaultCalendarId = choice);
      await _load();
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nie udało się zapisać domyślnego kalendarza.'),
        ),
      );
    }
  }

  Future<void> _create([DateTime? start]) async {
    final writable = _writable;
    final now = DateTime.now();
    final minutes = dateOnly(now) == _day
        ? slotAt(_day, now.difference(_day).inMinutes.toDouble())
        : 8 * 60;
    start ??= _day.add(Duration(minutes: minutes));
    final calendar =
        writable
            .where((calendar) => calendar.id == _defaultCalendarId)
            .firstOrNull ??
        writable.firstOrNull;
    final saved = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NewItemEditor(
        store: _store,
        calendars: writable,
        calendarId: calendar?.id ?? -1,
        start: start!,
      ),
    );
    if (!mounted || saved == null) return;
    await _load(reloadTasks: saved == true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved == true
              ? 'Zapisano zadanie w Google.'
              : 'Zapisano w kalendarzu Google na urządzeniu.',
        ),
      ),
    );
  }

  Future<void> _openTasks({bool createNew = false}) async {
    final account = TasksAuth.instance.email;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TasksScreen(date: _day, createNew: createNew),
      ),
    );
    if (!mounted) return;
    if (account != TasksAuth.instance.email) {
      setState(() => _scheduledTasks = []);
    }
    await _refreshTasks(showErrors: true);
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
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Zapisano w kalendarzu Google na urządzeniu.'),
      ),
    );
  }

  void _openEvent(CalendarEvent event) {
    if (event.taskId != null) {
      _editTask(event);
      return;
    }
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

  Future<void> _editTask(CalendarEvent event) async {
    try {
      final task = await _tasksApi.task(event.taskListId!, event.taskId!);
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => TaskEditor(
          api: _tasksApi,
          lists: const [],
          listId: task.listId,
          date: _day,
          task: task,
        ),
      );
      if (mounted && saved == true) await _refreshTasks(showErrors: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tasksError(error))));
      }
    }
  }

  Future<bool> _reschedule(
    CalendarEvent event,
    DateTime start,
    DateTime end,
  ) async {
    if (event.taskId != null) {
      final task = _scheduledTasks
          .where(
            (task) =>
                task.id == event.taskId && task.listId == event.taskListId,
          )
          .firstOrNull;
      if (task == null) return false;
      try {
        final updated = await _tasksApi.reschedule(task, start, end);
        if (mounted) {
          setState(
            () => _scheduledTasks = _scheduledTasks
                .map(
                  (item) => item.id == task.id && item.listId == task.listId
                      ? updated
                      : item,
                )
                .toList(),
          );
        }
        return true;
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(tasksError(error))));
        }
        return false;
      }
    }
    try {
      await _store.save(
        calendarId: event.calendarId,
        title: event.title,
        start: start,
        end: end,
        event: event,
      );
      if (mounted) await _load();
      return true;
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nie udało się zmienić godziny wydarzenia.'),
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = !_loading;
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
                _refreshTasks(showErrors: true);
              } else if (action == 'defaultCalendar') {
                _chooseDefaultCalendar();
              } else if (action == 'tasks') {
                _openTasks();
              } else if (action == 'tasksConfig') {
                configureTasks(context);
              } else {
                _settings(permissions: action == 'permission');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refresh', child: Text('Odśwież')),
              PopupMenuItem(value: 'tasks', child: Text('Zadania Google')),
              PopupMenuItem(
                value: 'tasksConfig',
                child: Text('Dostęp do Zadań Google'),
              ),
              PopupMenuItem(
                value: 'defaultCalendar',
                child: Text('Domyślny kalendarz'),
              ),
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
            Expanded(child: _body()),
          ],
        ),
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              tooltip: 'Dodaj wydarzenie lub zadanie',
              onPressed: _create,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final tasks = _taskEvents;
    if (_failed && tasks.isEmpty) {
      return _CalendarMessage(
        icon: Icons.error_outline,
        title: 'Nie udało się odczytać kalendarza',
        action: 'Spróbuj ponownie',
        onPressed: _load,
      );
    }
    if (_denied && tasks.isEmpty) {
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
    final data = CalendarDay(_data?.calendars ?? [], [
      ...?_data?.events,
      ...tasks,
    ]);
    if (data.calendars.isEmpty && tasks.isEmpty) {
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
      onSlot: _create,
      onEvent: _openEvent,
      onReschedule: _reschedule,
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
