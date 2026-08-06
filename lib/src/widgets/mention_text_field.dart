import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/mention_api_service.dart';

class MentionTextField extends StatefulWidget {
  const MentionTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.style,
    this.cursorColor,
    this.minLines,
    this.maxLines = 5,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.searchOverride,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final TextStyle? style;
  final Color? cursorColor;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  // Forwarded alongside this widget's own internal mention-scanning
  // onChanged handler, so callers that need to react to every keystroke
  // (e.g. notes_type.dart re-validating the post form) don't lose that
  // ability just by switching from a plain TextField to this one.
  final void Function(String text)? onChanged;
  final Future<List<MentionCandidate>> Function(String query)? searchOverride;

  @override
  State<MentionTextField> createState() => MentionTextFieldState();
}

class MentionTextFieldState extends State<MentionTextField> {
  static const Duration _debounceDuration = Duration(milliseconds: 250);

  final List<MentionCandidate> _selectedMentions = [];
  List<MentionCandidate> _suggestions = [];
  Timer? _debounce;
  int? _mentionStartIndex;

  // The suggestion dropdown is rendered via OverlayPortal/CompositedTransform
  // rather than inline in this widget's own Column. An inline dropdown
  // participates in the surrounding layout's height budget -- inside a
  // fixed-height composer row (e.g. this widget wrapped in Expanded inside a
  // Row, itself near the bottom of a modal sheet with the keyboard open),
  // that reliably overflows ("BOTTOM OVERFLOWED BY n PIXELS") the moment
  // suggestions appear, since there's no room left to grow into. An overlay
  // paints into the app's Overlay (above everything, unconstrained by local
  // box constraints), so it can never cause a layout overflow here.
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlayController = OverlayPortalController();
  final GlobalKey _fieldKey = GlobalKey();
  // Captured from LayoutBuilder's constraints (a layout INPUT, always
  // available during build) rather than a GlobalKey's renderObject.size (a
  // layout OUTPUT, not yet computed while this same build is still running)
  // -- reading .size here throws "size has not yet been determined because
  // the framework is still in the layout phase".
  double? _fieldWidth;

  // Whether the dropdown should grow upward from the field instead of
  // downward. Recomputed (synchronously, from an event handler -- never
  // from build/layout, where the field's renderObject.size/position aren't
  // safely readable yet) right before the dropdown opens, since by then the
  // field has already been laid out on a prior frame.
  bool _showAbove = false;

  static const double _dropdownMaxHeight = 180;

  void _updatePreferredDirection() {
    final renderBox = _fieldKey.currentContext?.findRenderObject();
    if (renderBox is! RenderBox || !renderBox.hasSize) return;
    final fieldTop = renderBox.localToGlobal(Offset.zero).dy;
    final fieldBottom = fieldTop + renderBox.size.height;
    final mediaQuery = MediaQuery.of(context);
    final visibleBottom = mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    final spaceBelow = visibleBottom - fieldBottom;
    final spaceAbove = fieldTop - mediaQuery.padding.top;
    _showAbove = spaceBelow < _dropdownMaxHeight && spaceAbove > spaceBelow;
  }

  List<MentionCandidate> get selectedMentions =>
      List.unmodifiable(_selectedMentions);

  /// Clears the accumulated selection, without touching [widget.controller]
  /// or its text. Callers that reuse the same MentionTextField across
  /// multiple submissions (e.g. a comment composer left open after posting)
  /// must call this once a submission's mentions have been read and sent,
  /// otherwise every later submission would keep re-including mentions
  /// selected for earlier, already-sent text.
  void clearMentions() {
    if (_selectedMentions.isEmpty) return;
    setState(() {
      _selectedMentions.clear();
    });
  }

  Future<List<MentionCandidate>> _search(String query) {
    return widget.searchOverride?.call(query) ??
        MentionApiService.instance.search(query);
  }

  void _hideSuggestions() {
    _debounce?.cancel();
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
    if (_suggestions.isNotEmpty || _mentionStartIndex != null) {
      setState(() {
        _mentionStartIndex = null;
        _suggestions = [];
      });
    }
  }

  void _onChanged(String text) {
    widget.onChanged?.call(text);

    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0) return;

    final upToCursor = text.substring(0, cursor);
    final atIndex = upToCursor.lastIndexOf('@');
    if (atIndex == -1 ||
        (atIndex > 0 &&
            !RegExp(r'\s').hasMatch(upToCursor[atIndex - 1]) &&
            atIndex != 0)) {
      _hideSuggestions();
      return;
    }

    final query = upToCursor.substring(atIndex + 1);
    if (query.contains(' ') || query.isEmpty) {
      _hideSuggestions();
      return;
    }

    _mentionStartIndex = atIndex;
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () async {
      final results = await _search(query);
      if (!mounted) return;
      setState(() => _suggestions = results);
      if (results.isEmpty) {
        if (_overlayController.isShowing) _overlayController.hide();
      } else if (!_overlayController.isShowing) {
        _updatePreferredDirection();
        _overlayController.show();
      }
    });
  }

  void _select(MentionCandidate candidate) {
    final start = _mentionStartIndex;
    if (start == null) return;
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    final before = text.substring(0, start);
    final after = text.substring(cursor);
    final newText = '$before@${candidate.name} $after';
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
          offset: before.length + candidate.name.length + 2),
    );
    _debounce?.cancel();
    if (_overlayController.isShowing) _overlayController.hide();
    setState(() {
      _selectedMentions.add(candidate);
      _suggestions = [];
      _mentionStartIndex = null;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Widget _buildSuggestionsOverlay(BuildContext context) {
    final fieldWidth = _fieldWidth;
    // The field is often docked near the bottom of the screen, right above
    // the keyboard (comment/reply composers) -- anchoring below would put
    // the dropdown off-screen there. _updatePreferredDirection (called just
    // before this overlay opens) picks whichever side actually has room.
    final targetAnchor = _showAbove ? Alignment.topLeft : Alignment.bottomLeft;
    final followerAnchor = _showAbove ? Alignment.bottomLeft : Alignment.topLeft;
    final offset = Offset(0, _showAbove ? -4 : 4);
    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: targetAnchor,
      followerAnchor: followerAnchor,
      offset: offset,
      child: Align(
        alignment: _showAbove ? Alignment.bottomLeft : Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: fieldWidth,
            constraints: const BoxConstraints(maxHeight: _dropdownMaxHeight),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final candidate = _suggestions[index];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundImage: (candidate.profilePic?.isNotEmpty ?? false)
                        ? NetworkImage(candidate.profilePic!)
                        : null,
                    child: (candidate.profilePic?.isNotEmpty ?? false)
                        ? null
                        : const Icon(Icons.person, size: 16),
                  ),
                  title: Text(candidate.name),
                  onTap: () => _select(candidate),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _fieldWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : null;
        return CompositedTransformTarget(
          link: _layerLink,
          child: OverlayPortal(
            controller: _overlayController,
            overlayChildBuilder: _buildSuggestionsOverlay,
            child: TextField(
              key: _fieldKey,
              controller: widget.controller,
              decoration: widget.decoration,
              style: widget.style,
              cursorColor: widget.cursorColor,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              onChanged: _onChanged,
            ),
          ),
        );
      },
    );
  }
}
