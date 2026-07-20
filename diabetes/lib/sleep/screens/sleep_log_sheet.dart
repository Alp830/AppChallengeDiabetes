import 'package:flutter/material.dart';

import '../models/sleep_models.dart';

/// Bottom sheet for adding or editing a night of sleep. Returns a [SleepLog]
/// on save (keeping the existing id when editing, empty id when new), or null
/// if dismissed.
class SleepLogSheet extends StatefulWidget {
  const SleepLogSheet({
    super.key,
    this.initial,
    this.initialBedtime,
    this.initialWakeTime,
  });

  final SleepLog? initial;
  final DateTime? initialBedtime;
  final DateTime? initialWakeTime;

  @override
  State<SleepLogSheet> createState() => _SleepLogSheetState();
}

class _SleepLogSheetState extends State<SleepLogSheet> {
  late DateTime _bedtime;
  late DateTime _wakeTime;
  late int _quality;
  late int _wakeUps;
  final _noteController = TextEditingController();

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final now = DateTime.now();
    final defaultWake = DateTime(now.year, now.month, now.day, 7);
    _wakeTime = initial?.wakeTime ?? widget.initialWakeTime ?? defaultWake;
    _bedtime =
        initial?.bedtime ??
        widget.initialBedtime ??
        _wakeTime.subtract(const Duration(hours: 8));
    _quality = initial?.quality ?? 3;
    _wakeUps = initial?.wakeUps ?? 0;
    _noteController.text = initial?.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isBedtime}) async {
    final current = isBedtime ? _bedtime : _wakeTime;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      final picked = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isBedtime) {
        _bedtime = picked;
      } else {
        _wakeTime = picked;
      }
    });
  }

  void _setToNow({required bool isBedtime}) {
    setState(() {
      final now = DateTime.now();
      if (isBedtime) {
        _bedtime = now;
      } else {
        _wakeTime = now;
      }
    });
  }

  void _save() {
    final duration = _wakeTime.difference(_bedtime);
    if (duration.inMinutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wake time must be after bedtime.')),
      );
      return;
    }
    final note = _noteController.text.trim();
    Navigator.of(context).pop(
      SleepLog(
        id: widget.initial?.id ?? '',
        bedtime: _bedtime,
        wakeTime: _wakeTime,
        quality: _quality,
        wakeUps: _wakeUps,
        source: widget.initial?.source ?? SleepSource.manual,
        note: note.isEmpty ? null : note,
        deepMinutes: widget.initial?.deepMinutes,
        lightMinutes: widget.initial?.lightMinutes,
        remMinutes: widget.initial?.remMinutes,
        awakeMinutes: widget.initial?.awakeMinutes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final duration = _wakeTime.difference(_bedtime);
    final durationLabel = duration.inMinutes <= 0
        ? '—'
        : '${duration.inHours}h ${duration.inMinutes % 60}m';

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Edit night' : 'Log last night',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ListTile(
              key: const Key('bedtimeField'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bedtime),
              title: const Text('Went to bed'),
              subtitle: Text(_formatDateTime(_bedtime)),
              trailing: _TrailingControls(
                onNow: () => _setToNow(isBedtime: true),
                onEdit: () => _pickDateTime(isBedtime: true),
              ),
              onTap: () => _pickDateTime(isBedtime: true),
            ),
            ListTile(
              key: const Key('wakeTimeField'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Woke up'),
              subtitle: Text(_formatDateTime(_wakeTime)),
              trailing: _TrailingControls(
                onNow: () => _setToNow(isBedtime: false),
                onEdit: () => _pickDateTime(isBedtime: false),
              ),
              onTap: () => _pickDateTime(isBedtime: false),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Time in bed: $durationLabel',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'How did you sleep?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
                ButtonSegment(value: 5, label: Text('5')),
              ],
              selected: {_quality},
              onSelectionChanged: (selection) =>
                  setState(() => _quality = selection.first),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Times woke up',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: _wakeUps == 0
                      ? null
                      : () => setState(() => _wakeUps--),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$_wakeUps',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  onPressed: () => setState(() => _wakeUps++),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Note (optional)',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('saveSleepButton'),
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(_isEditing ? 'Save changes' : 'Save night'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trailing controls for a date/time tile: a compact "Now" shortcut that snaps
/// the field to the current moment, plus the edit affordance that opens the
/// pickers. Each button has its own handler so neither triggers the tile's tap.
class _TrailingControls extends StatelessWidget {
  const _TrailingControls({required this.onNow, required this.onEdit});

  final VoidCallback onNow;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Set to right now',
          child: TextButton.icon(
            onPressed: onNow,
            icon: const Icon(Icons.schedule, size: 18),
            label: const Text('Now'),
          ),
        ),
        IconButton(
          onPressed: onEdit,
          tooltip: 'Pick date and time',
          icon: const Icon(Icons.edit),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime date) {
  final hour = date.hour == 0
      ? 12
      : (date.hour > 12 ? date.hour - 12 : date.hour);
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.month}/${date.day}  $hour:$minute $period';
}
