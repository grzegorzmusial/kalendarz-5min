import 'package:material_ui/material_ui.dart';

import 'calendar.dart';
import 'editor.dart';
import 'tasks.dart';
import 'tasks_screen.dart';

class NewItemEditor extends StatefulWidget {
  const NewItemEditor({
    super.key,
    required this.store,
    required this.calendars,
    required this.calendarId,
    required this.start,
  });
  final CalendarStore store;
  final List<GoogleCalendar> calendars;
  final int calendarId;
  final DateTime start;

  @override
  State<NewItemEditor> createState() => _NewItemEditorState();
}

class _NewItemEditorState extends State<NewItemEditor> {
  final _title = TextEditingController();
  bool _task = false;
  bool _visitedTasks = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selector = SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('Wydarzenie')),
        ButtonSegment(value: true, label: Text('Zadanie')),
      ],
      selected: {_task},
      onSelectionChanged: _saving
          ? null
          : (selection) {
              FocusScope.of(context).unfocus();
              setState(() {
                _task = selection.single;
                _visitedTasks = _visitedTasks || _task;
              });
            },
    );
    void savingChanged(bool saving) => setState(() => _saving = saving);
    return IndexedStack(
      index: _task ? 1 : 0,
      children: [
        EventEditor(
          store: widget.store,
          calendars: widget.calendars,
          calendarId: widget.calendarId,
          start: widget.start,
          typeSelector: selector,
          titleController: _title,
          onSavingChanged: savingChanged,
        ),
        if (_visitedTasks)
          _NewTaskEditor(
            date: widget.start,
            selector: selector,
            title: _title,
            onSavingChanged: savingChanged,
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

class _NewTaskEditor extends StatefulWidget {
  const _NewTaskEditor({
    required this.date,
    required this.selector,
    required this.title,
    required this.onSavingChanged,
  });
  final DateTime date;
  final Widget selector;
  final TextEditingController title;
  final ValueChanged<bool> onSavingChanged;
  @override
  State<_NewTaskEditor> createState() => _NewTaskEditorState();
}

class _NewTaskEditorState extends State<_NewTaskEditor> {
  final _auth = TasksAuth.instance;
  late final _api = TasksApi(token: _auth.token);
  List<GoogleTaskList> _lists = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool connect = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (connect) await _auth.connect();
      final lists = await _api.lists();
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = tasksError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _error == null && _lists.isNotEmpty) {
      return TaskEditor(
        api: _api,
        lists: _lists,
        listId: _lists.first.id,
        date: widget.date,
        initialStart: widget.date,
        typeSelector: widget.selector,
        titleController: widget.title,
        onSavingChanged: widget.onSavingChanged,
      );
    }
    return AlertDialog(
      scrollable: true,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Nowe zadanie'),
          const SizedBox(height: 12),
          widget.selector,
        ],
      ),
      content: SizedBox(
        width: 380,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error ??
                        'Utwórz listę w Zadaniach Google i odśwież widok.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _load(connect: true),
                    child: const Text('Połącz konto Google'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await configureTasks(context);
                      if (mounted) await _load();
                    },
                    child: const Text('Konfiguruj dostęp'),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
      ],
    );
  }
}
