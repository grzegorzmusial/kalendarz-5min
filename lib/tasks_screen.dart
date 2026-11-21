import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'calendar.dart';
import 'tasks.dart';

Future<void> configureTasks(BuildContext context) async {
  final store = CalendarStore();
  final saved = await store.taskClientId();
  if (!context.mounted) return;
  var input = saved;
  final form = GlobalKey<FormState>();
  final clientId = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: const Text('Dostęp do Zadań Google'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'W projekcie Google Cloud włącz Google Tasks API i skonfiguruj logowanie OAuth. '
                'Dodaj klienta Android dla tej aplikacji oraz klienta typu Aplikacja internetowa. '
                'Instrukcja dołączona do APK zawiera nazwę pakietu i odcisk SHA-1.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: saved,
                onChanged: (value) => input = value,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Identyfikator klienta webowego OAuth',
                ),
                validator: (value) =>
                    RegExp(
                      r'^[0-9]+-[a-zA-Z0-9]+\.apps\.googleusercontent\.com$',
                    ).hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Wklej pełny identyfikator klienta webowego',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, input.trim());
            }
          },
          child: const Text('Zapisz'),
        ),
      ],
    ),
  );
  if (clientId == null || !context.mounted) return;
  try {
    await store.setTaskClientId(clientId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved.isNotEmpty && saved != clientId
              ? 'Zapisano. Zamknij aplikację i uruchom ją ponownie.'
              : 'Zapisano konfigurację Zadań Google.',
        ),
      ),
    );
  } on PlatformException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nie udało się zapisać konfiguracji.')),
    );
  }
}

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.date, this.createNew = false});
  final DateTime date;
  final bool createNew;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with WidgetsBindingObserver {
  final _auth = TasksAuth.instance;
  late final _api = TasksApi(token: _auth.token);
  List<GoogleTaskList> _lists = [];
  List<GoogleTask> _tasks = [];
  String? _listId;
  String? _error;
  bool _busy = true;
  bool _editing = false;
  late bool _pendingCreate = widget.createNew;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _api.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy && !_editing) _load();
  }

  Future<void> _load({bool connect = false, bool changeAccount = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (changeAccount) await _auth.disconnect();
      if (connect) await _auth.connect();
      final lists = await _api.lists();
      final listId = lists.any((list) => list.id == _listId)
          ? _listId
          : lists.firstOrNull?.id;
      final tasks = listId == null ? <GoogleTask>[] : await _api.tasks(listId);
      if (!mounted) return;
      setState(() {
        _lists = lists;
        _listId = listId;
        _tasks = tasks;
        _busy = false;
      });
      if (_pendingCreate && listId != null) {
        _pendingCreate = false;
        await _edit();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = tasksError(error);
        _tasks = [];
        if (changeAccount) {
          _lists = [];
          _listId = null;
        }
      });
    }
  }

  Future<void> _edit([GoogleTask? task]) async {
    if (_busy || _listId == null || _error != null) return;
    _editing = true;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskEditor(
        api: _api,
        lists: _lists,
        listId: task?.listId ?? _listId!,
        date: widget.date,
        task: task,
      ),
    );
    _editing = false;
    if (!mounted || saved != true) return;
    await _load();
  }

  Future<void> _complete(GoogleTask task, bool completed) async {
    setState(() => _busy = true);
    try {
      await _api.complete(task, completed);
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tasksError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zadania Google'),
        actions: [
          IconButton(
            tooltip: 'Odśwież zadania',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (value) async {
              if (value == 'configure') {
                _editing = true;
                await configureTasks(context);
                _editing = false;
                if (mounted) await _load();
              } else {
                await _load(connect: true, changeAccount: true);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'configure',
                child: Text('Dostęp do Zadań Google'),
              ),
              PopupMenuItem(
                value: 'account',
                child: Text('Zmień konto Google'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_auth.email != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_auth.email!),
              ),
            if (_lists.isNotEmpty && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_listId),
                  initialValue: _listId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Lista zadań'),
                  items: [
                    for (final list in _lists)
                      DropdownMenuItem(
                        value: list.id,
                        child: Text(
                          list.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (id) {
                          _listId = id;
                          _load();
                        },
                ),
              ),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => _load(connect: true),
                              child: const Text('Połącz konto Google'),
                            ),
                            TextButton(
                              onPressed: () async {
                                _editing = true;
                                await configureTasks(context);
                                _editing = false;
                                if (mounted) await _load();
                              },
                              child: const Text('Konfiguruj dostęp'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _tasks.isEmpty
                  ? Center(
                      child: Text(
                        _lists.isEmpty
                            ? 'Utwórz listę w Zadaniach Google i odśwież widok.'
                            : 'Brak zadań na tej liście.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 90),
                      itemCount: _tasks.length,
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        return ListTile(
                          leading: Checkbox(
                            value: task.completed,
                            onChanged: (value) => _complete(task, value!),
                          ),
                          title: Text(
                            task.title.isEmpty ? 'Bez tytułu' : task.title,
                            style: TextStyle(
                              decoration: task.completed
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: task.due == null
                              ? null
                              : Text(locale.formatFullDate(task.due!)),
                          onTap: () => _edit(task),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: !_busy && _error == null && _listId != null
          ? FloatingActionButton(
              tooltip: 'Dodaj zadanie',
              onPressed: _edit,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({
    super.key,
    required this.api,
    required this.lists,
    required this.listId,
    required this.date,
    this.task,
    this.typeSelector,
    this.titleController,
    this.onSavingChanged,
  });
  final TasksApi api;
  final List<GoogleTaskList> lists;
  final String listId;
  final DateTime date;
  final GoogleTask? task;
  final Widget? typeSelector;
  final TextEditingController? titleController;
  final ValueChanged<bool>? onSavingChanged;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final _form = GlobalKey<FormState>();
  late final _title =
      widget.titleController ??
      TextEditingController(text: widget.task?.title ?? '');
  late final _notes = TextEditingController(text: widget.task?.notes ?? '');
  late String _listId = widget.listId;
  late DateTime? _due = widget.task == null ? widget.date : widget.task!.due;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    if (widget.titleController == null) _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.onSavingChanged?.call(true);
    try {
      await widget.api.save(
        listId: _listId,
        title: _title.text,
        notes: _notes.text,
        due: _due,
        task: widget.task,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      widget.onSavingChanged?.call(false);
      setState(() {
        _saving = false;
        _error = tasksError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = MaterialLocalizations.of(context);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.task == null ? 'Nowe zadanie' : 'Edytuj zadanie'),
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
                TextFormField(
                  controller: _title,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: 'Tytuł'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Wpisz tytuł'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notes,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notatka'),
                ),
                const SizedBox(height: 14),
                if (widget.task == null)
                  DropdownButtonFormField<String>(
                    initialValue: _listId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Lista zadań'),
                    items: [
                      for (final list in widget.lists)
                        DropdownMenuItem(
                          value: list.id,
                          child: Text(
                            list.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (id) => setState(() => _listId = id!),
                  ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        _due == null
                            ? 'Dodaj datę'
                            : locale.formatShortDate(_due!),
                      ),
                      onPressed: _saving
                          ? null
                          : () async {
                              final due = await showDatePicker(
                                context: context,
                                initialDate: _due ?? widget.date,
                                firstDate: DateTime(1900),
                                lastDate: DateTime(2199, 12, 31),
                              );
                              if (mounted && due != null) {
                                setState(() => _due = due);
                              }
                            },
                    ),
                    if (_due != null)
                      IconButton(
                        tooltip: 'Usuń datę',
                        onPressed: _saving
                            ? null
                            : () => setState(() => _due = null),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
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
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Zapisywanie…' : 'Zapisz'),
          ),
        ],
      ),
    );
  }
}
