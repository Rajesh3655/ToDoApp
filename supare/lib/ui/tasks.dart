import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../core/app_store.dart';
import '../models/models.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.store, required this.upcoming});
  final AppStore store;
  final bool upcoming;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String query = '';
  bool history = false;
  bool importantOnly = false;
  Future<void> action(Future<void> Function() fn) async {
    try {
      await fn();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not finish this action. Check reminder permissions in Settings.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final all = widget.store.tasks;
    final tasks =
        all
            .where(
              (t) => history
                  ? t.completedAt != null
                  : t.completedAt == null &&
                        (widget.upcoming
                            ? !t.due.isBefore(tomorrow)
                            : t.due.isBefore(tomorrow)),
            )
            .where((t) => !importantOnly || t.important)
            .where(
              (t) => '${t.title} ${t.description}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
            )
            .toList()
          ..sort(
            (a, b) => history
                ? b.completedAt!.compareTo(a.completedAt!)
                : a.due.compareTo(b.due),
          );
    final overdue = tasks
        .where((t) => t.completedAt == null && t.due.isBefore(now))
        .length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editTask(context, widget.store),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SUPARE',
                    style: TextStyle(
                      letterSpacing: 3,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.upcoming
                              ? 'A little ahead.'
                              : 'Make room\nfor what matters.',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                        ),
                      ),
                      Icon(
                        widget.upcoming
                            ? Icons.wb_twilight_outlined
                            : Icons.wb_sunny_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: 36,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    history
                        ? 'Your completed tasks'
                        : widget.upcoming
                        ? 'Plans, one day at a time.'
                        : '${DateFormat('EEEE, d MMMM').format(now)}${overdue > 0 ? ' · $overdue overdue' : ''}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      hintText: 'Find a task',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Completed'),
                        selected: history,
                        onSelected: (v) => setState(() => history = v),
                      ),
                      FilterChip(
                        label: const Text('Important'),
                        selected: importantOnly,
                        onSelected: (v) => setState(() => importantOnly = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (tasks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 20, 36, 100),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      history ? Icons.task_alt : Icons.spa_outlined,
                      size: 58,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      query.isNotEmpty
                          ? 'No matching tasks'
                          : history
                          ? 'Small wins live here.'
                          : 'A clear space.',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      query.isNotEmpty
                          ? 'Try a different search.'
                          : history
                          ? 'Completed tasks appear here. You can restore them anytime.'
                          : 'Add a task. Choose a time. Let Supare help you remember.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
            sliver: SliverList.builder(
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final t = tasks[index];
                final late = t.completedAt == null && t.due.isBefore(now);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: ListTile(
                      leading: IconButton(
                        tooltip: history ? 'Restore task' : 'Complete task',
                        icon: Icon(
                          history
                              ? Icons.restore
                              : Icons.radio_button_unchecked,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () => action(
                          () => history
                              ? widget.store.restoreTask(t.id)
                              : widget.store.completeTask(t.id),
                        ),
                      ),
                      title: Text(
                        t.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: history
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEE, d MMM · h:mm a').format(t.due),
                              style: TextStyle(
                                color: late
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              children: [
                                if (t.reminder == 'alarm')
                                  const Text('◉ Alarm'),
                                if (t.repeat != 'none')
                                  Text(
                                    t.repeat == 'custom'
                                        ? 'Every ${t.intervalDays} days'
                                        : t.repeat,
                                  ),
                                if (t.important)
                                  const Icon(Icons.star_rounded, size: 16),
                              ],
                            ),
                          ],
                        ),
                      ),
                      onTap: () => editTask(context, widget.store, task: t),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Task actions',
                        onSelected: (value) async {
                          if (value == 'edit') {
                            await editTask(context, widget.store, task: t);
                          }
                          if (value == 'tomorrow') {
                            final d = DateTime.now().add(
                              const Duration(days: 1),
                            );
                            await action(
                              () => widget.store.saveTask(
                                t.copyWith(
                                  due: DateTime(
                                    d.year,
                                    d.month,
                                    d.day,
                                    t.due.hour,
                                    t.due.minute,
                                  ),
                                ),
                              ),
                            );
                          }
                          if (value == 'snooze') {
                            await action(
                              () => widget.store.snoozeTask(t.id, 10),
                            );
                          }
                          if (value == 'important') {
                            await action(
                              () => widget.store.saveTask(
                                t.copyWith(important: !t.important),
                              ),
                            );
                          }
                          if (value == 'delete' && context.mounted) {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete task?'),
                                content: const Text(
                                  'Its reminder will also be cancelled.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('Keep'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (yes == true) {
                              await action(() => widget.store.deleteTask(t.id));
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit / reschedule'),
                          ),
                          if (!history) ...[
                            const PopupMenuItem(
                              value: 'tomorrow',
                              child: Text('Move to tomorrow'),
                            ),
                            const PopupMenuItem(
                              value: 'snooze',
                              child: Text('Snooze 10 minutes'),
                            ),
                            PopupMenuItem(
                              value: 'important',
                              child: Text(
                                t.important ? 'Remove star' : 'Mark important',
                              ),
                            ),
                          ],
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> editTask(
  BuildContext context,
  AppStore store, {
  TaskItem? task,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TaskEditor(store: store, task: task),
  );
}

class TaskEditor extends StatefulWidget {
  const TaskEditor({super.key, required this.store, this.task});
  final AppStore store;
  final TaskItem? task;
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController description;
  late final TextEditingController interval;
  late final String taskId;
  late DateTime due;
  late String reminder;
  late String repeat;
  late bool important;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final t = widget.task;
    taskId = t?.id ?? const Uuid().v4();
    title = TextEditingController(text: t?.title);
    description = TextEditingController(text: t?.description);
    interval = TextEditingController(text: '${t?.intervalDays ?? 2}');
    due = t?.due ?? DateTime.now().add(const Duration(hours: 1));
    reminder = t?.reminder ?? 'normal';
    repeat = t?.repeat ?? 'none';
    important = t?.important ?? false;
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    interval.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (widget.task?.completedAt == null && due.isBefore(DateTime.now())) {
      setState(() => error = 'Choose a future date and time for the reminder.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.saveTask(
        TaskItem(
          id: taskId,
          title: title.text.trim(),
          description: description.text.trim(),
          due: due,
          reminder: reminder,
          repeat: repeat,
          intervalDays: int.tryParse(interval.text) ?? 1,
          important: important,
          recurrenceDay:
              widget.task != null && DateUtils.isSameDay(widget.task!.due, due)
              ? widget.task!.recurrenceDay
              : due.day,
          recurrenceAnchor: widget.task != null && widget.task!.due == due
              ? widget.task!.recurrenceAnchor
              : due,
          seriesId: widget.task?.seriesId,
          createdAt: widget.task?.createdAt,
          completedAt: widget.task?.completedAt,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'The task may be saved, but its reminder could not be scheduled. Check alarm access in Settings, then retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      20,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.task == null ? 'A new intention' : 'Edit task',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: title,
              autofocus: true,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What needs doing?'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Give your task a title'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: description,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(DateFormat('d MMM yyyy').format(due)),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: due,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (d != null && mounted) {
                        setState(
                          () => due = DateTime(
                            d.year,
                            d.month,
                            d.day,
                            due.hour,
                            due.minute,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(DateFormat('h:mm a').format(due)),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(due),
                      );
                      if (t != null && mounted) {
                        setState(
                          () => due = DateTime(
                            due.year,
                            due.month,
                            due.day,
                            t.hour,
                            t.minute,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'normal',
                  icon: Icon(Icons.notifications_outlined),
                  label: Text('Normal'),
                ),
                ButtonSegment(
                  value: 'alarm',
                  icon: Icon(Icons.alarm),
                  label: Text('Alarm'),
                ),
              ],
              selected: {reminder},
              onSelectionChanged: (v) => setState(() => reminder = v.first),
            ),
            const SizedBox(height: 8),
            Text(
              reminder == 'alarm'
                  ? 'Android: rings with alarm access. iPhone: a local notification; continuous ringing depends on system support.'
                  : 'A local notification at the scheduled time. Sound follows your device settings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: repeat,
              decoration: const InputDecoration(labelText: 'Repeat'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Once')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'custom', child: Text('Every N days')),
              ],
              onChanged: (v) => setState(() => repeat = v!),
            ),
            if (repeat == 'custom')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextFormField(
                  controller: interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Repeat every (days)',
                  ),
                  validator: (v) =>
                      (int.tryParse(v ?? '') ?? 0) < 1 ||
                          (int.tryParse(v ?? '') ?? 0) > 3650
                      ? 'Choose 1–3650 days'
                      : null,
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mark as important'),
              value: important,
              onChanged: (v) => setState(() => important = v),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Save task'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
