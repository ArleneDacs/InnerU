// ignore_for_file: dead_code
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
  late final TextEditingController _notes;
  late final TextEditingController _targetValue;
  late final TextEditingController _currentValue;
  late final TextEditingController _unit;
  final _planEntry = TextEditingController();
  final _scrollController = ScrollController();

  late GoalCategory _category;
  late GoalType _goalType;
  late GoalDirection _direction;
  late TargetPeriod _targetPeriod;
  late GoalStatus _status;
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
    _notes = TextEditingController(text: g?.notes ?? '');
    _targetValue = TextEditingController(
        text: g == null || g.targetValue == 0 ? '' : '${g.targetValue}');
    _currentValue = TextEditingController(
        text: g == null || g.currentValue == 0 ? '' : '${g.currentValue}');
    _unit = TextEditingController(text: g?.unit ?? '');
    _category = g?.category ?? GoalCategory.personal;
    _goalType = g?.goalType ?? GoalType.merit;
    _direction = g?.direction ?? GoalDirection.gain;
    _targetPeriod = g?.targetPeriod ?? TargetPeriod.none;
    _status = g?.status ?? GoalStatus.inProgress;
    _targetDate = g?.targetDate ?? addDays(DateTime.now(), 90);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _notes.dispose();
    _targetValue.dispose();
    _currentValue.dispose();
    _unit.dispose();
    _planEntry.dispose();
    _scrollController.dispose();
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
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          targetDate: _targetDate,
          goalType: _goalType,
          direction: _direction,
          targetValue: targetValue,
          currentValue: currentValue,
          unit: _unit.text,
          targetPeriod: _targetPeriod,
          status: _status,
        );
      } else {
        await widget.service.createGoal(
          uid: widget.uid,
          category: _category,
          title: _title.text.trim(),
          description: _description.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 760;
    final wideInner = screenWidth >= 860;

    final goalTypeRow = wide
        ? Row(
            children: [
              Expanded(
                child: _GoalTypeCard(
                  selected: _goalType == GoalType.merit,
                  title: 'Merit',
                  subtitle: 'A number you chip away at over time.',
                  onTap: () => setState(() => _goalType = GoalType.merit),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GoalTypeCard(
                  selected: _goalType == GoalType.milestone,
                  title: 'Milestone',
                  subtitle: 'Done when its action plans are done.',
                  onTap: () => setState(() => _goalType = GoalType.milestone),
                ),
              ),
            ],
          )
        : Column(
            children: [
              _GoalTypeCard(
                selected: _goalType == GoalType.merit,
                title: 'Merit',
                subtitle: 'A number you chip away at over time.',
                onTap: () => setState(() => _goalType = GoalType.merit),
              ),
              const SizedBox(height: 10),
              _GoalTypeCard(
                selected: _goalType == GoalType.milestone,
                title: 'Milestone',
                subtitle: 'Done when its action plans are done.',
                onTap: () => setState(() => _goalType = GoalType.milestone),
              ),
            ],
          );

    final categoryField = DropdownButtonFormField<GoalCategory>(
      initialValue: _category,
      dropdownColor: const Color(0xFF111A45),
      decoration: _fieldDecoration('Choose a category'),
      style: const TextStyle(
        color: Color(0xFFF7F5EC),
        fontSize: 16,
      ),
      items: [
        for (final c in GoalCategory.values)
          DropdownMenuItem(
            value: c,
            child: Text(c.label),
          ),
      ],
      onChanged: (v) => setState(() => _category = v!),
    );

    final statusField = DropdownButtonFormField<GoalStatus>(
      initialValue: _status,
      dropdownColor: const Color(0xFF111A45),
      decoration: _fieldDecoration('In progress'),
      style: const TextStyle(
        color: Color(0xFFF7F5EC),
        fontSize: 16,
      ),
      items: [
        for (final status in GoalStatus.values)
          DropdownMenuItem(
            value: status,
            child: Text(status.label),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _status = value);
      },
    );

    final targetDateField = InkWell(
      onTap: _pickTargetDate,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: _fieldDecoration(isoDay(_targetDate)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isoDay(_targetDate),
                style: const TextStyle(
                  color: Color(0xFFF7F5EC),
                  fontSize: 16,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              color: Color(0xFFB7C0E5),
              size: 20,
            ),
          ],
        ),
      ),
    );

    final topMetaFields = _isEdit
        ? (wide
            ? Row(
                children: [
                  Expanded(child: statusField),
                  const SizedBox(width: 18),
                  Expanded(child: targetDateField),
                ],
              )
            : Column(
                children: [
                  statusField,
                  const SizedBox(height: 18),
                  targetDateField,
                ],
              ))
        : (wide
            ? Row(
                children: [
                  Expanded(child: categoryField),
                  const SizedBox(width: 18),
                  Expanded(child: targetDateField),
                ],
              )
            : Column(
                children: [
                  categoryField,
                  const SizedBox(height: 18),
                  targetDateField,
                ],
              ));

    final meritFields = Column(
      children: [
        if (wideInner)
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('goal-target-value'),
                  controller: _targetValue,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                    color: Color(0xFFF7F5EC),
                  fontSize: 16,
                  ),
                  decoration: _fieldDecoration('10'),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: TextFormField(
                  key: const Key('goal-current-value'),
                  controller: _currentValue,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                    color: Color(0xFFF7F5EC),
                  fontSize: 16,
                  ),
                  decoration: _fieldDecoration('0'),
                ),
              ),
            ],
          )
        else ...[
          TextFormField(
            key: const Key('goal-target-value'),
            controller: _targetValue,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  color: Color(0xFFF7F5EC),
                  fontSize: 16,
                ),
            decoration: _fieldDecoration('10'),
          ),
          const SizedBox(height: 18),
          TextFormField(
            key: const Key('goal-current-value'),
            controller: _currentValue,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              color: Color(0xFFF7F5EC),
                  fontSize: 16,
            ),
            decoration: _fieldDecoration('0'),
          ),
        ],
        const SizedBox(height: 18),
        if (wideInner)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<GoalDirection>(
                  initialValue: _direction,
                  dropdownColor: const Color(0xFF111A45),
                  decoration: _fieldDecoration('Gain'),
                  style: const TextStyle(
                    color: Color(0xFFF7F5EC),
                    fontSize: 16,
                  ),
                  items: [
                    for (final d in GoalDirection.values)
                      DropdownMenuItem(
                        value: d,
                        child: Text(d.label),
                      ),
                  ],
                  onChanged: (v) => setState(() => _direction = v!),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: TextFormField(
                  controller: _unit,
                  style: const TextStyle(
                    color: Color(0xFFF7F5EC),
                    fontSize: 16,
                  ),
                  decoration: _fieldDecoration(
                    'Kg',
                    helper: 'e.g. Kg, M, books',
                  ),
                ),
              ),
            ],
          )
        else ...[
          DropdownButtonFormField<GoalDirection>(
            initialValue: _direction,
            dropdownColor: const Color(0xFF111A45),
            decoration: _fieldDecoration('Gain'),
            style: const TextStyle(
              color: Color(0xFFF7F5EC),
              fontSize: 16,
            ),
            items: [
              for (final d in GoalDirection.values)
                DropdownMenuItem(
                  value: d,
                  child: Text(d.label),
                ),
            ],
            onChanged: (v) => setState(() => _direction = v!),
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _unit,
            style: const TextStyle(
              color: Color(0xFFF7F5EC),
              fontSize: 16,
            ),
            decoration: _fieldDecoration(
              'Kg',
              helper: 'e.g. Kg, M, books',
            ),
          ),
        ],
        const SizedBox(height: 18),
        DropdownButtonFormField<TargetPeriod>(
          initialValue: _targetPeriod,
          dropdownColor: const Color(0xFF111A45),
          decoration: _fieldDecoration('Daily'),
          style: const TextStyle(
            color: Color(0xFFF7F5EC),
            fontSize: 16,
          ),
          items: [
            for (final p in TargetPeriod.values)
              DropdownMenuItem(
                value: p,
                child: Text(p.label),
              ),
          ],
          onChanged: (v) => setState(() => _targetPeriod = v!),
        ),
      ],
    );

    Widget sectionCard(Widget child, {EdgeInsetsGeometry? padding}) {
      return Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1438).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF243169)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: child,
      );
    }

    final pageContent = Scaffold(
      backgroundColor: const Color(0xFF050714),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF070A18),
              Color(0xFF0A1026),
              Color(0xFF050714),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(wide ? 16 : 14, 14, wide ? 16 : 14, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const Text(
                                '← My goals',
                                style: TextStyle(
                                  color: Color(0xFF9DA9D6),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10183F),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: const Color(0xFF243169)),
                              ),
                              child: const Text(
                                'A12 only',
                                style: TextStyle(
                                  color: Color(0xFFF0B93C),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      sectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isEdit ? 'Edit goal' : 'Set a new goal',
                                        style: const TextStyle(
                                          color: Color(0xFFF6EAD0),
                                          fontSize: 24,
                                          height: 1.1,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                          fontFamily: 'Georgia',
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _isEdit
                                            ? 'Update the goal details, score, and status.'
                                            : 'Build a focused goal for personal, professional, or contribution progress.',
                                        style: const TextStyle(
                                          color: Color(0xFFB7C0E5),
                                          fontSize: 13.5,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  iconSize: 24,
                                  color: const Color(0xFFB7C0E5),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Goal type',
                              style: TextStyle(
                                color: Color(0xFFD7DCF4),
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            goalTypeRow,
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      sectionCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Goal details',
                              style: TextStyle(
                                color: Color(0xFFD7DCF4),
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              key: const Key('goal-title'),
                              controller: _title,
                              style: const TextStyle(
                                color: Color(0xFFF7F5EC),
                                fontSize: 16,
                              ),
                              decoration: _fieldDecoration('Goal title'),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty)
                                      ? 'Title is required'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _description,
                              style: const TextStyle(
                                color: Color(0xFFF7F5EC),
                                fontSize: 16,
                              ),
                              decoration: _fieldDecoration(
                                'What are you committing to?',
                              ),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 12),
                            topMetaFields,
                            if (_goalType == GoalType.merit) ...[
                              const SizedBox(height: 12),
                              meritFields,
                            ] else ...[
                              const SizedBox(height: 12),
                              _ActionPlansPanel(
                                planTitles: _planTitles,
                                planEntry: _planEntry,
                                onAdd: () {
                                  final t = _planEntry.text.trim();
                                  if (t.isEmpty) return;
                                  setState(() {
                                    _planTitles.add(t);
                                    _planEntry.clear();
                                  });
                                },
                                onRemove: (title) =>
                                    setState(() => _planTitles.remove(title)),
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _notes,
                              style: const TextStyle(
                                color: Color(0xFFF7F5EC),
                                fontSize: 16,
                              ),
                              decoration: _fieldDecoration(
                                'Notes',
                                helper: 'Anything your coach should know.',
                              ),
                              maxLines: 3,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFB7C0E5),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontSize: 15),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFF0B93C),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                _saving
                                    ? 'Saving...'
                                    : _isEdit
                                        ? 'Save changes'
                                        : 'Create goal',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return pageContent;

    final isMerit = _goalType == GoalType.merit;
    final headerTitle = _isEdit ? 'EDIT GOAL' : 'SET A NEW GOAL';
    final headerSubtitle = _isEdit
        ? 'A merit goal is scored by its measure; a milestone goal by its action plans.'
        : 'Personal, professional or contribution - all three categories count towards your Goal Total Score.';
    return Scaffold(
      backgroundColor: const Color(0xFF050714),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          children: [
            Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Container(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1539),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFF25336A)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 30,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  headerTitle,
                                  style: const TextStyle(
                                    color: Color(0xFFF0E6CF),
                                    fontSize: 34,
                                    height: 1.05,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                    fontFamily: 'Georgia',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  headerSubtitle,
                                  style: const TextStyle(
                                    color: Color(0xFFB7C0E5),
                                    fontSize: 18,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            iconSize: 30,
                            color: const Color(0xFFB7C0E5),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Goal type',
                        style: TextStyle(
                          color: Color(0xFFD7DCF4),
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked = constraints.maxWidth < 860;
                          final meritCard = Expanded(
                            child: _GoalTypeCard(
                              selected: _goalType == GoalType.merit,
                              title: 'Merit',
                              subtitle: 'A number you chip away at over time.',
                              onTap: () =>
                                  setState(() => _goalType = GoalType.merit),
                            ),
                          );
                          final milestoneCard = Expanded(
                            child: _GoalTypeCard(
                              selected: _goalType == GoalType.milestone,
                              title: 'Milestone',
                              subtitle: 'Done when its action plans are done.',
                              onTap: () =>
                                  setState(() => _goalType = GoalType.milestone),
                            ),
                          );

                          if (stacked) {
                            return Column(
                              children: [
                                meritCard,
                                const SizedBox(height: 16),
                                milestoneCard,
                              ],
                            );
                          }

                          return Row(
                            children: [
                              meritCard,
                              const SizedBox(width: 16),
                              milestoneCard,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          Widget titleField = TextFormField(
                            key: const Key('goal-title'),
                            controller: _title,
                            style: const TextStyle(
                              color: Color(0xFFF7F5EC),
                              fontSize: 18,
                            ),
                            decoration: _fieldDecoration('Enter a goal title'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Title is required'
                                : null,
                          );

                          Widget descriptionField = TextFormField(
                            controller: _description,
                            style: const TextStyle(
                              color: Color(0xFFF7F5EC),
                              fontSize: 18,
                            ),
                            decoration:
                                _fieldDecoration('The outcome you are committing to...'),
                            maxLines: 4,
                          );

                          Widget categoryField = DropdownButtonFormField<GoalCategory>(
                            initialValue: _category,
                            dropdownColor: const Color(0xFF111A45),
                            decoration:
                                _fieldDecoration('Choose a category'),
                            style: const TextStyle(
                              color: Color(0xFFF7F5EC),
                              fontSize: 18,
                            ),
                            items: [
                              for (final c in GoalCategory.values)
                                DropdownMenuItem(
                                  value: c,
                                  child: Text(c.label),
                                ),
                            ],
                            onChanged: (v) => setState(() => _category = v!),
                          );

                          Widget targetDateField = InkWell(
                            onTap: _pickTargetDate,
                            borderRadius: BorderRadius.circular(18),
                            child: InputDecorator(
                              decoration:
                                  _fieldDecoration(isoDay(_targetDate)),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      isoDay(_targetDate),
                                      style: const TextStyle(
                                        color: Color(0xFFF7F5EC),
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.calendar_today_outlined,
                                    color: Color(0xFFB7C0E5),
              size: 18,
                                  ),
                                ],
                              ),
                            ),
                          );

                          Widget topMetaFields;
                          if (_isEdit) {
                            topMetaFields = Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<GoalStatus>(
                                    initialValue: _status,
                                    dropdownColor: const Color(0xFF111A45),
                                    decoration: _fieldDecoration('In progress'),
                                    style: const TextStyle(
                                      color: Color(0xFFF7F5EC),
                                      fontSize: 18,
                                    ),
                                    items: [
                                      for (final status in GoalStatus.values)
                                        DropdownMenuItem(
                                          value: status,
                                          child: Text(status.label),
                                        ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() => _status = value);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(child: targetDateField),
                              ],
                            );
                          } else {
                            topMetaFields = Row(
                              children: [
                                Expanded(child: categoryField),
                                const SizedBox(width: 18),
                                Expanded(child: targetDateField),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              titleField,
                              const SizedBox(height: 20),
                              descriptionField,
                              const SizedBox(height: 20),
                              topMetaFields,
                              if (!_isEdit && !isMerit) ...[
                                const SizedBox(height: 20),
                                _ActionPlansPanel(
                                  planTitles: _planTitles,
                                  planEntry: _planEntry,
                                  onAdd: () {
                                    final t = _planEntry.text.trim();
                                    if (t.isEmpty) return;
                                    setState(() {
                                      _planTitles.add(t);
                                      _planEntry.clear();
                                    });
                                  },
                                  onRemove: (title) => setState(
                                    () => _planTitles.remove(title),
                                  ),
                                ),
                              ],
                              if (isMerit) ...[
                                const SizedBox(height: 20),
                                LayoutBuilder(
                                  builder: (context, innerConstraints) {
                                    final wideInner =
                                        innerConstraints.maxWidth >= 900;
                                    final targetValueField = TextFormField(
                                      key: const Key('goal-target-value'),
                                      controller: _targetValue,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      style: const TextStyle(
                                        color: Color(0xFFF7F5EC),
                                        fontSize: 18,
                                      ),
                                      decoration: _fieldDecoration('10'),
                                    );
                                    final currentValueField = TextFormField(
                                      key: const Key('goal-current-value'),
                                      controller: _currentValue,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      style: const TextStyle(
                                        color: Color(0xFFF7F5EC),
                                        fontSize: 18,
                                      ),
                                      decoration: _fieldDecoration('0'),
                                    );
                                    final directionField =
                                        DropdownButtonFormField<GoalDirection>(
                                      initialValue: _direction,
                                      dropdownColor: const Color(0xFF111A45),
                                      decoration: _fieldDecoration('Gain'),
                                      style: const TextStyle(
                                        color: Color(0xFFF7F5EC),
                                        fontSize: 18,
                                      ),
                                      items: [
                                        for (final d in GoalDirection.values)
                                          DropdownMenuItem(
                                            value: d,
                                            child: Text(d.label),
                                          ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _direction = v!),
                                    );
                                    final unitField = TextFormField(
                                      controller: _unit,
                                      style: const TextStyle(
                                        color: Color(0xFFF7F5EC),
                                        fontSize: 18,
                                      ),
                                      decoration: _fieldDecoration(
                                        'Kg',
                                        helper: 'e.g. Kg, M, books',
                                      ),
                                    );
                                    final periodField =
                                        DropdownButtonFormField<TargetPeriod>(
                                      initialValue: _targetPeriod,
                                      dropdownColor: const Color(0xFF111A45),
                                      decoration: _fieldDecoration('Daily'),
                                      style: const TextStyle(
                                        color: Color(0xFFF7F5EC),
                                        fontSize: 18,
                                      ),
                                      items: [
                                        for (final p in TargetPeriod.values)
                                          DropdownMenuItem(
                                            value: p,
                                            child: Text(p.label),
                                          ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _targetPeriod = v!),
                                    );

                                    return Column(
                                      children: [
                                        if (wideInner)
                                          Row(
                                            children: [
                                              Expanded(child: targetValueField),
                                              const SizedBox(width: 18),
                                              Expanded(
                                                child: currentValueField,
                                              ),
                                            ],
                                          )
                                        else ...[
                                          targetValueField,
                                          const SizedBox(height: 18),
                                          currentValueField,
                                        ],
                                        const SizedBox(height: 18),
                                        if (wideInner)
                                          Row(
                                            children: [
                                              Expanded(child: directionField),
                                              const SizedBox(width: 18),
                                              Expanded(child: unitField),
                                            ],
                                          )
                                        else ...[
                                          directionField,
                                          const SizedBox(height: 18),
                                          unitField,
                                        ],
                                        const SizedBox(height: 18),
                                        periodField,
                                      ],
                                    );
                                  },
                                ),
                              ],
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _notes,
                                style: const TextStyle(
                                  color: Color(0xFFF7F5EC),
                                  fontSize: 18,
                                ),
                                decoration: _fieldDecoration(
                                  'Notes',
                                  helper: 'Anything you want your coach to know.',
                                ),
                                maxLines: 4,
                              ),
                              const SizedBox(height: 24),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final compact = constraints.maxWidth < 420;
                                  final saveLabel = _saving
                                      ? 'Saving...'
                                      : _isEdit
                                          ? 'Save changes'
                                          : 'Create goal';
                                  final saveButton = FilledButton(
                                    onPressed: _saving ? null : _save,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFF0B93C),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 12,
                                      ),
                                      minimumSize: const Size(0, 42),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                      saveLabel,
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  );
                                  final cancelButton = TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFFD7DCF4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      minimumSize: const Size(0, 38),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(fontSize: 15),
                                    ),
                                  );
                                  if (compact) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        saveButton,
                                        const SizedBox(height: 10),
                                        cancelButton,
                                      ],
                                    );
                                  }
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      cancelButton,
                                      const SizedBox(width: 12),
                                      saveButton,
                                    ],
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    String hint, {
    String? helper,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF8390C0), fontSize: 15),
      helperText: helper,
      helperStyle: const TextStyle(color: Color(0xFF8390C0), fontSize: 12.5),
      filled: true,
      fillColor: const Color(0xFF10183F),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF243169)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF243169)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFF0B93C), width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

class _GoalTypeCard extends StatelessWidget {
  const _GoalTypeCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 0),
      child: Material(
        color: selected ? const Color(0xFF2B2A37) : const Color(0xFF10183F),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? const Color(0xFFF0B93C)
                    : const Color(0xFF243169),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF7F5EC),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFB7C0E5),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionPlansPanel extends StatelessWidget {
  const _ActionPlansPanel({
    required this.planTitles,
    required this.planEntry,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> planTitles;
  final TextEditingController planEntry;
  final VoidCallback onAdd;
  final void Function(String title) onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B102E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF243169)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Action plans',
                  style: TextStyle(
                    color: Color(0xFFD7DCF4),
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${planTitles.length} plans',
                style: const TextStyle(
                  color: Color(0xFFB7C0E5),
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Optional - the steps you\'ll take. The score comes from the measure above; these just track the work.',
            style: TextStyle(
              color: Color(0xFFB7C0E5),
              fontSize: 13.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          for (final title in planTitles) ...[
              Row(
                children: [
                  Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF243169)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10183F),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF243169)),
                    ),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFF7F5EC),
                        fontSize: 14.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => onRemove(title),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: const Icon(Icons.close, color: Color(0xFF8390C0)),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: planEntry,
                  style: const TextStyle(color: Color(0xFFF7F5EC)),
                  decoration: InputDecoration(
                    hintText: 'Plan 1',
                    hintStyle: const TextStyle(
                      color: Color(0xFF8390C0),
                      fontSize: 14.5,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF10183F),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF243169)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF243169)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFFF0B93C),
                        width: 1.4,
                      ),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onAdd,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF7F5EC),
                  side: const BorderSide(color: Color(0xFF243169)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  minimumSize: const Size(0, 42),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  '+ Add',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
