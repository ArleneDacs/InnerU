import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/features/abundance/domain/day_keys.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_theme.dart';

/// Create or edit a quest through a 4-step wizard mirroring A12-Tracker's
/// `goal-wizard.tsx`: What -> How -> When & qualities -> Declaration.
///
/// The wizard never shows a separate title/description/notes field -- like
/// A12's own wizard, it collects one declaration (step 0's "what"), the
/// qualities to embody (step 2), and a deadline (step 2), then composes the
/// sentence that gets stored. That composition (`_composeDeclaration`, a
/// port of goal-wizard.tsx's `declarationTemplate`) runs in `_submit()`,
/// which reconciles it into `_title`/`_description`/`_notes` immediately
/// before delegating to the pre-existing `_save()`.
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
  final _declarationController = TextEditingController();
  final _qualitiesFreeTextController = TextEditingController();
  final _scrollController = ScrollController();

  // Nullable (unlike the other fields below): a new quest starts with no
  // category picked, matching A12's wizard, which shows the category picker
  // unselected until the member chooses one. An edit still inherits its
  // existing category.
  GoalCategory? _category;
  late GoalType _goalType;
  late GoalDirection _direction;
  late TargetPeriod _targetPeriod;
  late GoalStatus _status;
  late DateTime _startDate;
  late DateTime _targetDate;
  final List<String> _planTitles = [];
  bool _saving = false;

  int _currentStep = 0; // 0=What, 1=How, 2=When & qualities, 3=Declaration
  static const _stepTitles = [
    'Step 1 of 4 — What',
    'Step 2 of 4 — How',
    'Step 3 of 4 — When & qualities',
    'Step 4 of 4 — Declaration',
  ];
  static const _stepLabels = ['What', 'How', 'When & qualities', 'Declaration'];

  // Copied verbatim from A12's `QUALITY_RECOMMENDATIONS` in goal-wizard.tsx.
  static const _qualityRecommendations = [
    'Commitment',
    'Discipline',
    'Excellence',
    'Integrity',
    'Responsibility',
    'Love',
    'Compassion',
    'Awareness',
  ];

  bool get _isEdit => widget.existing != null;

  bool get _step1Valid => _declarationController.text.trim().length >= 3;
  bool get _step2Valid =>
      _category != null && double.tryParse(_targetValue.text.trim()) != null;

  /// What the current step still needs, said out loud rather than left to a
  /// silently-dead Next button. Null once the step is satisfied.
  String? get _stepBlocker => switch (_currentStep) {
        0 => _step1Valid
            ? null
            : 'Answer the question with at least 3 characters.',
        1 => _category == null
            ? 'Choose a category.'
            : double.tryParse(_targetValue.text.trim()) == null
                ? 'Enter a target value.'
                : null,
        _ => null,
      };

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _title = TextEditingController(text: g?.title ?? '');
    _description = TextEditingController(text: g?.description ?? '');
    // Step 0's declaration field must not present as an empty, required
    // question when editing an existing quest -- A12's own wizard recovers
    // this via `splitDeclaration(title, description)`, whose "what" half is
    // just the title, trimmed (see goal-wizard.tsx's `splitDeclaration`).
    // The reverse mapping (declaration + qualities -> title/description/
    // notes) happens in `_submit()`, right before `_save()` runs.
    _declarationController.text = g?.title ?? '';
    _notes = TextEditingController(text: g?.notes ?? '');
    // A12 stores the chosen qualities in the goal's `notes` field (see
    // goal-wizard.tsx: `qualities` state seeded from `initial?.notes`, and
    // posted back as `notes: qualities.trim()`). Mirrored here so editing an
    // existing quest doesn't silently blank out its previously-set
    // qualities the next time this wizard saves.
    _qualitiesFreeTextController.text =
        _splitQualities(g?.notes ?? '').join(', ');
    _targetValue = TextEditingController(
        text: g == null || g.targetValue == 0 ? '' : '${g.targetValue}');
    _currentValue = TextEditingController(
        text: g == null || g.currentValue == 0 ? '' : '${g.currentValue}');
    _unit = TextEditingController(text: g?.unit ?? '');
    _category = g?.category;
    _goalType = g?.goalType ?? GoalType.merit;
    _direction = g?.direction ?? GoalDirection.gain;
    _targetPeriod = g?.targetPeriod ?? TargetPeriod.none;
    _status = g?.status ?? GoalStatus.inProgress;
    _startDate = _dateOnly(g?.startDate ?? DateTime.now());
    _targetDate = _dateOnly(g?.targetDate ?? addDays(DateTime.now(), 90));
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
    _declarationController.dispose();
    _qualitiesFreeTextController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Backs step 2 ("When & qualities")'s deadline picker.
  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() {
      final normalized = _dateOnly(picked);
      _targetDate = normalized;
      if (_startDate.isAfter(normalized)) {
        _startDate = normalized;
      }
    });
  }

  // ignore: unused_element
  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    setState(() {
      final normalized = _dateOnly(picked);
      _startDate = normalized;
      if (_targetDate.isBefore(normalized)) {
        _targetDate = normalized;
      }
    });
  }

  void _goNext() {
    final valid = switch (_currentStep) {
      0 => _step1Valid,
      1 => _step2Valid,
      _ => true,
    };
    if (!valid) return;
    setState(() => _currentStep = (_currentStep + 1).clamp(0, 3));
  }

  void _goBack() {
    setState(() => _currentStep = (_currentStep - 1).clamp(0, 3));
  }

  /// Toggles `quality`'s membership in the qualities free-text field.
  ///
  /// Mirrors A12's `toggleQuality` (goal-wizard.tsx:720-730) exactly: there
  /// is no separate Set tracking which qualities are "selected". The current
  /// selection is always recomputed by re-parsing whatever text is *live* in
  /// `_qualitiesFreeTextController` right now, then the new list is written
  /// straight back to that same controller. A persistent Set here would be a
  /// second source of truth that can go stale the moment a member types
  /// directly into the free-text field -- the next chip tap would then
  /// silently overwrite their typed text with a computation based on stale
  /// state. Deriving from the live text on every call makes that impossible.
  void _toggleQuality(String quality) {
    setState(() {
      final current = _parsedQualities();
      final isSelected = current.any(
        (q) => q.toLowerCase() == quality.toLowerCase(),
      );
      final next = isSelected
          ? current
              .where((q) => q.toLowerCase() != quality.toLowerCase())
              .toList()
          : [...current, quality];
      _qualitiesFreeTextController.text = next.join(', ');
    });
  }

  /// Splits a comma-separated qualities string into a deduped,
  /// order-preserving list -- mirrors A12's `qualityList()` in
  /// goal-wizard.tsx.
  List<String> _splitQualities(String text) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in text.split(',')) {
      final quality = raw.trim();
      if (quality.isEmpty) continue;
      if (seen.add(quality.toLowerCase())) result.add(quality);
    }
    return result;
  }

  /// The qualities actually in play right now: whatever is currently typed
  /// into the free-text field, which is also what every chip tap keeps in
  /// sync -- so this is correct whether the member used the chips, typed by
  /// hand, or both.
  List<String> _parsedQualities() =>
      _splitQualities(_qualitiesFreeTextController.text);

  /// "a, b, and c" -- mirrors A12's `naturalList()` in goal-wizard.tsx.
  String _naturalList(List<String> values) {
    if (values.isEmpty) return '';
    if (values.length == 1) return values.first;
    if (values.length == 2) return '${values[0]} and ${values[1]}';
    return '${values.sublist(0, values.length - 1).join(', ')}, and '
        '${values.last}';
  }

  /// Ported from A12's `declarationTemplate` (goal-wizard.tsx): composes the
  /// sentence stored as the quest's `description` from the raw "what"
  /// answer, the qualities chosen to embody, and the deadline -- e.g. "With
  /// Commitment, I see myself finishing what I start on or before July 31,
  /// 2026." `_title` gets the raw "what" alone (A12's hidden `title` input
  /// is `what.trim()`) -- see `_submit`.
  String _composeDeclaration(
    String what,
    List<String> qualities,
    DateTime targetDate,
  ) {
    final goal = what.trim().replaceAll(RegExp(r'[.!?]\s*$'), '');
    if (goal.isEmpty) return '';
    final embodied = _naturalList(qualities);
    final alreadyVision = RegExp(
      r'^i\s+(?:joyfully\s+)?see myself\b',
      caseSensitive: false,
    ).hasMatch(goal);
    final vision = alreadyVision
        ? goal
        : 'I see myself ${goal.substring(0, 1).toLowerCase()}${goal.substring(1)}';
    final prefix = embodied.isEmpty ? '' : 'With $embodied, ';
    return '$prefix$vision on or before '
        '${DateFormat('MMMM d, y').format(targetDate)}.';
  }

  /// Deliberately a no-op beyond the snackbar. Real AI-suggestion behavior
  /// (see `A12-Tracker/src/app/(app)/goals/actions.ts`'s
  /// `suggestDeclarationAction`) is unconfirmed from source and out of scope
  /// here -- a later task should read that file before wiring this up.
  void _requestAiSuggestions() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI suggestions are coming soon.')),
    );
  }

  /// Reconciles the wizard's declaration/qualities state into the fields
  /// `_save()` actually persists, then delegates to it unchanged. The
  /// wizard never shows a separate title/description/notes field, so this
  /// is the one place that mapping happens, immediately before the
  /// pre-existing save path runs:
  ///  - `_title` <- the raw "what" (step 0's declaration field), trimmed.
  ///  - `_description` <- `_composeDeclaration`, the full declaration
  ///    sentence (qualities + deadline woven in), mirroring A12's
  ///    `declarationTemplate`.
  ///  - `_notes` <- the chosen qualities, comma-joined, mirroring A12's own
  ///    wizard, which stores qualities in the goal's `notes` field.
  Future<void> _submit() async {
    final qualities = _parsedQualities();
    _title.text = _declarationController.text.trim();
    _description.text = _composeDeclaration(
      _declarationController.text,
      qualities,
      _targetDate,
    );
    _notes.text = qualities.join(', ');
    await _save();
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
          startDate: _startDate,
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
          category: _category ?? GoalCategory.personal,
          title: _title.text.trim(),
          description: _description.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          startDate: _startDate,
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
    return Scaffold(
      backgroundColor: AbundanceColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable step content. The Back/Next (or Submit) row below
            // is deliberately NOT part of this scroll view -- it is a
            // pinned footer so it stays reachable at the bottom of the
            // screen no matter how tall a given step's content is (this
            // mirrors a modal's fixed footer, adapted for a full-screen
            // mobile layout instead of a desktop dialog).
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 16),
                          // Shown on every step, unconditionally -- confirmed
                          // against goal-wizard.tsx:880-926, where this banner
                          // sits outside all four step <section> blocks with
                          // no `step` gating at all. The brief's "step 0 and
                          // step 2 only" instruction did not match the real
                          // reference file.
                          _buildAiBanner(),
                          const SizedBox(height: 16),
                          _buildProgressBar(),
                          const SizedBox(height: 20),
                          _buildStepBody(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: AbundanceColors.background,
                border: Border(top: BorderSide(color: AbundanceColors.border)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: _buildNavRow(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEdit ? 'Edit quest' : 'Set a new quest',
                style: const TextStyle(
                  color: AbundanceColors.foreground,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Georgia',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _stepTitles[_currentStep],
                style: const TextStyle(
                  color: AbundanceColors.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
          color: AbundanceColors.muted,
        ),
      ],
    );
  }

  Widget _buildAiBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AbundanceColors.primaryGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AbundanceColors.primaryGold.withValues(alpha: 0.35),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Start with AI declaration suggestions',
                  style: TextStyle(
                    color: AbundanceColors.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Answer four questions, choose from five declarations, '
                  'then review the populated Quest steps.',
                  style: TextStyle(
                    color: AbundanceColors.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _requestAiSuggestions,
            style: OutlinedButton.styleFrom(
              foregroundColor: AbundanceColors.foreground,
              side: const BorderSide(color: AbundanceColors.border),
            ),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Get 5 AI suggestions'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Row(
      children: [
        for (var i = 0; i < _stepLabels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= _currentStep
                        ? AbundanceColors.primaryGold
                        : AbundanceColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _stepLabels[i],
                  style: TextStyle(
                    color: i == _currentStep
                        ? AbundanceColors.primaryGold
                        : AbundanceColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepBody() {
    return switch (_currentStep) {
      0 => _buildStepWhat(),
      1 => _buildStepHow(),
      2 => _buildStepWhenAndQualities(),
      _ => _buildStepDeclaration(),
    };
  }

  Widget _buildStepWhat() {
    return _sectionCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shape your declaration',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Answer in the present tense so the result reads like a quest '
            'you can see and feel.',
            style: TextStyle(
              color: AbundanceColors.muted,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'What do you joyfully see yourself achieving?',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('quest-declaration-field'),
            controller: _declarationController,
            maxLines: 4,
            style: const TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 16,
            ),
            decoration: _fieldDecoration(
              'I see myself build a closer relationship with my family, '
              'friends and love ones.',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHow() {
    return _sectionCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How will you achieve it?',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose how the quest is measured, then list the action plans '
            'that will make it real.',
            style: TextStyle(
              color: AbundanceColors.muted,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Category',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _buildCategoryPicker(),
          const SizedBox(height: 18),
          const Text(
            'Direction',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _buildDirectionToggle(),
          const SizedBox(height: 18),
          const Text(
            'Target value',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('quest-target-value-field'),
            controller: _targetValue,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 16,
            ),
            decoration: _fieldDecoration('10'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          const Text(
            'Target period',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<TargetPeriod>(
            initialValue: _targetPeriod,
            dropdownColor: AbundanceColors.surfaceRaised,
            decoration: _fieldDecoration('Daily'),
            style: const TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 16,
            ),
            items: [
              for (final p in TargetPeriod.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) => setState(() => _targetPeriod = v!),
          ),
          const SizedBox(height: 18),
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
            onRemove: (title) => setState(() => _planTitles.remove(title)),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPicker() {
    return Row(
      children: [
        for (final c in GoalCategory.values) ...[
          if (c != GoalCategory.values.first) const SizedBox(width: 8),
          Expanded(
            child: _CategoryChip(
              category: c,
              selected: _category == c,
              onTap: () => setState(() => _category = c),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDirectionToggle() {
    return Row(
      children: [
        Expanded(
          child: _DirectionButton(
            label: 'Gain',
            icon: Icons.trending_up,
            selected: _direction == GoalDirection.gain,
            onTap: () => setState(() => _direction = GoalDirection.gain),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DirectionButton(
            label: 'Release',
            icon: Icons.trending_down,
            selected: _direction == GoalDirection.lose,
            onTap: () => setState(() => _direction = GoalDirection.lose),
          ),
        ),
      ],
    );
  }

  Widget _buildStepWhenAndQualities() {
    // Recomputed on every build from the live free-text field -- mirrors
    // A12's chip rendering (goal-wizard.tsx:1287-1289), which also derives
    // `selected` fresh from `qualityList(qualities)` rather than a separate
    // Set, so a chip's highlighted state never disagrees with what the
    // free-text field actually contains.
    final selectedQualities =
        _parsedQualities().map((q) => q.toLowerCase()).toSet();
    return _sectionCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose when and who you will be',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose a deadline, then select the qualities you will embody.',
            style: TextStyle(
              color: AbundanceColors.muted,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Deadline',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _buildDeadlinePicker(),
          const SizedBox(height: 18),
          const Text(
            'What qualities will you embody?',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final quality in _qualityRecommendations)
                _QualityChip(
                  label: quality,
                  selected: selectedQualities.contains(quality.toLowerCase()),
                  onTap: () => _toggleQuality(quality),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('quest-qualities-field'),
            controller: _qualitiesFreeTextController,
            maxLines: 2,
            style: const TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 15,
            ),
            decoration: _fieldDecoration(
              'Love, Compassion, Integrity, Excellence, Awareness',
              helper: 'Separate each quality with a comma.',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlinePicker() {
    return Material(
      color: AbundanceColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _pickTargetDate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AbundanceColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.event_outlined,
                size: 18,
                color: AbundanceColors.muted,
              ),
              const SizedBox(width: 10),
              Text(
                DateFormat('MMMM d, y').format(_targetDate),
                style: const TextStyle(
                  color: AbundanceColors.foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepDeclaration() {
    final qualities = _parsedQualities();
    // Computed live (not just at submit) so the review card always shows
    // what will actually be saved if Submit is tapped right now.
    final composed = _composeDeclaration(
      _declarationController.text,
      qualities,
      _targetDate,
    );
    return _sectionCard(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Review your quest declaration',
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Review the declaration and every answer before saving your '
            'quest.',
            style: TextStyle(
              color: AbundanceColors.muted,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AbundanceColors.primaryGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AbundanceColors.primaryGold.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  composed.isEmpty
                      ? _declarationController.text.trim()
                      : composed,
                  style: const TextStyle(
                    color: AbundanceColors.foreground,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: AbundanceColors.border, height: 1),
                const SizedBox(height: 12),
                const Text(
                  'QUALITIES',
                  style: TextStyle(
                    color: AbundanceColors.primaryGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  qualities.isEmpty ? 'None selected' : qualities.join(', '),
                  style: const TextStyle(
                    color: AbundanceColors.foreground,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavRow() {
    final isLast = _currentStep == _stepTitles.length - 1;
    final blocker = _stepBlocker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (blocker != null) ...[
          Text(
            blocker,
            style: const TextStyle(color: AbundanceColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            TextButton(
              onPressed: _currentStep == 0 ? () => Navigator.pop(context) : _goBack,
              style: TextButton.styleFrom(foregroundColor: AbundanceColors.muted),
              child: Text(_currentStep == 0 ? 'Cancel' : 'Back'),
            ),
            const Spacer(),
            if (!isLast)
              FilledButton(
                // Deliberately always wired to `_goNext` rather than
                // `blocker == null ? _goNext : null`: `_goNext` re-reads
                // step validity live when pressed, so it stays correct even
                // in a frame where this row hasn't rebuilt since the last
                // keystroke (e.g. a test's enterText immediately followed
                // by tap(), with no pump in between). The blocker text
                // above is the user-facing signal for why a tap did
                // nothing; the button itself is not visually disabled.
                onPressed: _goNext,
                style: FilledButton.styleFrom(
                  backgroundColor: AbundanceColors.primaryGold,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Next'),
              )
            else
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AbundanceColors.primaryGold,
                  foregroundColor: Colors.black,
                ),
                child: Text(_saving ? 'Saving...' : 'Submit'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _sectionCard(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AbundanceColors.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AbundanceColors.border),
      ),
      child: child,
    );
  }

  InputDecoration _fieldDecoration(String hint, {String? helper}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AbundanceColors.muted, fontSize: 15),
      helperText: helper,
      helperStyle: const TextStyle(color: AbundanceColors.muted, fontSize: 12.5),
      filled: true,
      fillColor: AbundanceColors.surfaceRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AbundanceColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AbundanceColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AbundanceColors.primaryGold, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final GoalCategory category;
  final bool selected;
  final VoidCallback onTap;

  static const _icons = {
    GoalCategory.personal: Icons.person_outline,
    GoalCategory.professional: Icons.work_outline,
    GoalCategory.contribution: Icons.volunteer_activism_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final tint = AbundanceColors.categoryColor(category.code);
    return Material(
      color: AbundanceColors.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AbundanceColors.primaryGold : AbundanceColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icons[category], size: 18, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  category.label,
                  style: const TextStyle(
                    color: AbundanceColors.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  const _DirectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AbundanceColors.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AbundanceColors.primaryGold : AbundanceColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AbundanceColors.foreground),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: AbundanceColors.foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quality recommendation chip on step 2 -- toggles the quality's
/// membership in the qualities free-text field when tapped. Mirrors the pill
/// buttons in goal-wizard.tsx's `QUALITY_RECOMMENDATIONS` row.
class _QualityChip extends StatelessWidget {
  const _QualityChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AbundanceColors.primaryGold.withValues(alpha: 0.15)
          : AbundanceColors.surfaceRaised,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AbundanceColors.primaryGold
                  : AbundanceColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? AbundanceColors.primaryGold
                  : AbundanceColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
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
        color: AbundanceColors.surfaceSunken,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AbundanceColors.border),
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
                    color: AbundanceColors.foreground,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${planTitles.length} plans',
                style: const TextStyle(
                  color: AbundanceColors.muted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Optional - the steps you\'ll take. The score comes from the '
            'measure above; these just track the work.',
            style: TextStyle(
              color: AbundanceColors.muted,
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
                    border: Border.all(color: AbundanceColors.border),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AbundanceColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AbundanceColors.border),
                    ),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AbundanceColors.foreground,
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
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: const Icon(Icons.close, color: AbundanceColors.muted),
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
                  style: const TextStyle(color: AbundanceColors.foreground),
                  decoration: InputDecoration(
                    hintText: 'Plan 1',
                    hintStyle: const TextStyle(
                      color: AbundanceColors.muted,
                      fontSize: 14.5,
                    ),
                    filled: true,
                    fillColor: AbundanceColors.surfaceRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AbundanceColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AbundanceColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AbundanceColors.primaryGold,
                        width: 1.4,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onAdd,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AbundanceColors.foreground,
                  side: const BorderSide(color: AbundanceColors.border),
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
