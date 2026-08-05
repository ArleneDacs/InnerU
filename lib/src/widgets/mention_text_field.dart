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
      _debounce?.cancel();
      setState(() {
        _mentionStartIndex = null;
        _suggestions = [];
      });
      return;
    }

    final query = upToCursor.substring(atIndex + 1);
    if (query.contains(' ') || query.isEmpty) {
      _debounce?.cancel();
      setState(() {
        _mentionStartIndex = null;
        _suggestions = [];
      });
      return;
    }

    _mentionStartIndex = atIndex;
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () async {
      final results = await _search(query);
      if (!mounted) return;
      setState(() => _suggestions = results);
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
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
        if (_suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
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
      ],
    );
  }
}
