import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/abundance/domain/day_keys.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

/// Create or edit a goal. A MERIT goal carries a numeric measure (target,
/// current, unit, optional recurring cadence); a MILESTONE goal is scored by
/// its action plans instead, so the measure fields hide and a plan list
/// shows.
class GoalFormScreen extends StatefulWidget {
  const GoalFormScreen({
    super.key,
    required this.service,
    required this.uid,
    this.existing,
  });

  final GoalsService service;
  final String uid;
  final GoalSummary? existing;

  @override
  State<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends State<GoalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _targetValue;
  late final TextEditingController _currentValue;
  late final TextEditingController _unit;
  final _planEntry = TextEditingController();

  late GoalCategory _category;
  late GoalType _goalType;
  late GoalDirection _direction;
  late TargetPeriod _targetPeriod;
  late DateTime _targetDate;
  final List<String> _planTitles = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _title = TextEditingController(text: g?.title ?? '');
    _description = TextEditingController(text: g?.description ?? '');
    _targetValue = TextEditingController(
        text: g == null || g.targetValue == 0 ? '' : '${g.targetValue}');
    _currentValue = TextEditingController(
        text: g == null || g.currentValue == 0 ? '' : '${g.currentValue}');
    _unit = TextEditingController(text: g?.unit ?? '');
    _category = g?.category ?? GoalCategory.personal;
    _goalType = g?.goalType ?? GoalType.merit;
    _direction = g?.direction ?? GoalDirection.gain;
    _targetPeriod = g?.targetPeriod ?? TargetPeriod.none;
    _targetDate = g?.targetDate ?? addDays(DateTime.now(), 90);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _targetValue.dispose();
    _currentValue.dispose();
    _unit.dispose();
    _planEntry.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final targetValue = double.tryParse(_targetValue.text.trim()) ?? 0;
      final currentValue = double.tryParse(_currentValue.text.trim()) ?? 0;
      if (_isEdit) {
        await widget.service.updateGoal(
          goalId: widget.existing!.id,
          actorId: widget.uid,
          title: _title.text.trim(),
          description: _description.text.trim(),
          targetDate: _targetDate,
          goalType: _goalType,
          direction: _direction,
          targetValue: targetValue,
          currentValue: currentValue,
          unit: _unit.text,
          targetPeriod: _targetPeriod,
        );
      } else {
        await widget.service.createGoal(
          uid: widget.uid,
          category: _category,
          title: _title.text.trim(),
          description: _description.text.trim(),
          targetDate: _targetDate,
          goalType: _goalType,
          direction: _direction,
          targetValue: targetValue,
          currentValue: currentValue,
          unit: _unit.text,
          targetPeriod: _targetPeriod,
          planTitles: _planTitles,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save goal: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMerit = _goalType == GoalType.merit;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit goal' : 'New goal')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('goal-title'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            if (!_isEdit)
              DropdownButtonFormField<GoalCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Life area'),
                items: [
                  for (final c in GoalCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _category = v!),
              ),
            const SizedBox(height: 12),
            SegmentedButton<GoalType>(
              segments: [
                for (final t in GoalType.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_goalType},
              onSelectionChanged: (s) => setState(() => _goalType = s.first),
            ),
            const SizedBox(height: 12),
            if (isMerit) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('goal-target-value'),
                      controller: _targetValue,
                      decoration:
                          const InputDecoration(labelText: 'Target value'),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('goal-current-value'),
                      controller: _currentValue,
                      decoration:
                          const InputDecoration(labelText: 'Current value'),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(
                          labelText: 'Unit', hintText: 'km, PHP, books…'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<GoalDirection>(
                      initialValue: _direction,
                      decoration:
                          const InputDecoration(labelText: 'Direction'),
                      items: [
                        for (final d in GoalDirection.values)
                          DropdownMenuItem(value: d, child: Text(d.label)),
                      ],
                      onChanged: (v) => setState(() => _direction = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TargetPeriod>(
                initialValue: _targetPeriod,
                decoration:
                    const InputDecoration(labelText: 'Recurring target'),
                items: [
                  for (final p in TargetPeriod.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (v) => setState(() => _targetPeriod = v!),
              ),
            ] else if (!_isEdit) ...[
              Text('Action plans',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final title in _planTitles)
                ListTile(
                  dense: true,
                  title: Text(title),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        setState(() => _planTitles.remove(title)),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _planEntry,
                      decoration:
                          const InputDecoration(hintText: 'Add a plan step'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      final t = _planEntry.text.trim();
                      if (t.isEmpty) return;
                      setState(() {
                        _planTitles.add(t);
                        _planEntry.clear();
                      });
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Target date'),
              subtitle: Text(isoDay(_targetDate)),
              trailing: const Icon(Icons.calendar_today, size: 20),
              onTap: _pickTargetDate,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save goal'),
            ),
          ],
        ),
      ),
    );
  }
}
