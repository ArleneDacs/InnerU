# Community Module Bug Fixes & Feature Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four Community-module bugs (black screen after posting, slow/non-optimistic comments, comment notifications not deep-linking, missing commenter avatars) and ship five features (clickable links, 50-char title limit, comment reactions, threaded comment replies, @mentions) in InnerU's Community module, without regressing the existing post/comment/heart flows.

**Architecture:** Backend is Laravel 12 + Postgres (`backend/`), one `auth:sanctum`-protected route group in `routes/api.php`. Community posts (`community_posts`), their reactions (`community_post_hearts`), and comments (`note_comments`, model name `NoteComment`) already exist and follow a consistent convention: `foreignId()->constrained()->cascadeOnDelete()`, composite `unique()` for reaction pivots, a static `Notification::createFor()` factory called ad-hoc from controllers (no Observers/Events), and `RefreshDatabase` + `Sanctum::actingAs()` feature tests. Every new backend piece in this plan mirrors that convention. Frontend is Flutter with a flat `ApiClient`-backed service-singleton pattern (no `dio`); the comment UI lives in `lib/src/models/comments_widget.dart` and is currently non-optimistic (full refetch after every mutation) with no avatars, no reactions, no threading, and no linkification anywhere in the app.

**Tech Stack:** Laravel 12 / PHP 8.2 / Postgres (backend), Flutter/Dart, existing `url_launcher: ^6.1.14` (frontend, no new package needed for links), existing `flutter_local_notifications`/OneSignal push pipeline (already wired, only payload routing changes).

## Global Constraints

- Backend tests run via `vendor/bin/phpunit --configuration=phpunit.pgsql.xml` — **not** `php artisan test`, which is broken in this project (see `postgres-ci-and-scoring-bug` history).
- Frontend tests run via `flutter test`; run `flutter analyze` after every Dart change (must report "No issues found!").
- New backend tables follow existing conventions exactly: `$table->id()` auto-increment PK, `foreignId('x_id')->constrained('table')->cascadeOnDelete()`, `$table->timestamps()`, composite `unique()` for anti-duplicate pivots, `json()` column + `'array'` Eloquent cast for structured/array data.
- All new/changed routes go inside the existing `auth:sanctum` group in `backend/routes/api.php` (the whole Community API is authenticated today — do not create unauthenticated routes).
- Every `Notification::createFor(...)` call must skip self-notification (mirror `PostHeartController`'s `(string) $post->user_id !== (string) $user->id` guard and `CommentController`'s equivalent).
- Do not touch `lib/src/models/comments.dart` (the legacy/dead `Comment` model) or the Watch app targets — out of scope.
- Do not add new Flutter dependencies for linkification — build it on top of the already-present `url_launcher`.
- No pagination exists on `GET /community/posts/{post}/comments` today (flat, full list, newest-first) — do not introduce pagination as a side effect of any task below; that's out of scope and would be its own project.
- Avatars must be resolved **live** at read time (join on `users`), never denormalized/snapshotted at comment-creation time — the spec explicitly requires avatars to update after a profile-photo change, which a snapshot (like `username` already is) cannot do.
- Keep `username`/comment-text snapshot behavior as-is; do not change how `username` is stored.

---

## File Structure

**Backend (`backend/`):**
- `app/Http/Controllers/Api/CommentController.php` — modify (avatars, reactions count, replies, mentions)
- `app/Http/Controllers/Api/CommunityController.php` — modify (title validation already `max:255`, add mentionable-users search + mentions on post create)
- `app/Models/NoteComment.php` — modify (add relations, fillable additions)
- `app/Models/CommentReaction.php` — create
- `app/Http/Controllers/Api/CommentReactionController.php` — create
- `database/migrations/2026_08_04_000001_create_comment_reactions_table.php` — create
- `database/migrations/2026_08_04_000002_add_parent_id_to_note_comments_table.php` — create
- `database/migrations/2026_08_04_000003_add_mentions_to_posts_and_comments.php` — create
- `routes/api.php` — modify (comment reactions routes, mentionable-users route)
- `tests/Feature/CommentReactionTest.php` — create
- `tests/Feature/CommentReplyTest.php` — create
- `tests/Feature/CommentAvatarTest.php` — create
- `tests/Feature/CommunityMentionTest.php` — create

**Frontend (`lib/`):**
- `lib/src/features/authentication/screen/notes/notes_type.dart` — modify (navigation race fix, daily-activity error decoupling, title maxLength, mention compose wiring)
- `lib/src/services/comments_api_service.dart` — modify (`CommunityComment` gains `profilePic`, `parentId`, `reactionsCount`, `reactedByMe`, `mentions`; add `reactComment`/`unreactComment`, `parentId`/`mentions` params on `addComment`)
- `lib/src/models/comments_widget.dart` — modify (optimistic add, avatars, reply UI, reaction button, scroll-to/highlight target comment)
- `lib/src/models/note_card.dart` — modify (linkify post body)
- `lib/src/widgets/linkified_text.dart` — create (shared URL-linkifying text widget)
- `lib/src/widgets/mention_text_field.dart` — create (shared @mention-autocomplete text input)
- `lib/src/services/mention_api_service.dart` — create (mentionable-users search)
- `lib/src/services/community_api_service.dart` — modify (`Note`/post model gains `mentions`)
- `lib/src/features/authentication/screen/community/community_screen.dart` — modify (accept `targetPostId`/`targetCommentId`, open + scroll on launch)
- `lib/src/services/notification_push_router.dart` — modify (pass `postId`/`commentId` through for `community_comment`)
- `lib/src/models/note_model.dart` — modify (`Note` gains `mentions`, if not already flowing through)

---

# Part A — Bug Fixes (no schema changes)

### Task 1: Fix black screen after posting (Navigator race)

**Files:**
- Modify: `lib/src/features/authentication/screen/notes/notes_type.dart` (Post-confirmation dialog's `TextButton.onPressed`, around line 326-345)
- Test: manual verification (see Step 4) — this is a transition-timing bug that a widget test's synchronous `pump()` cannot reliably reproduce or catch; do not write a widget test that would give false confidence here.

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new — behavior-only fix.

**Root cause:** `Navigator.pop(dialogContext)` (dismissing the confirmation dialog) is immediately followed, in the same synchronous continuation, by `Navigator.pushReplacementNamed(context, '/communityScreen')`. Two Navigator transitions fired back-to-back with no frame yield between them can paint a black frame while they overlap — this exact class of bug was already found and fixed once in this codebase, in `meditation_screen.dart`'s `_shareWithMemories()` (`Navigator.of(context).pop()` there is followed by `await Future<void>.delayed(const Duration(milliseconds: 180))` before the next modal opens). The post-flow never got that fix.

- [ ] **Step 1: Read the current button handler**

Open `lib/src/features/authentication/screen/notes/notes_type.dart` and locate the `TextButton` inside the post-confirmation `AlertDialog` (search for `pushReplacementNamed(context, '/communityScreen')`). Confirm the current shape matches:

```dart
TextButton(onPressed: () async {
  final success = await saveNotes(isSaved: false);
  if (!mounted || !dialogContext.mounted) return;
  Navigator.pop(dialogContext);
  if (!success) return;
  if (widget.openCommunityAfterPost) {
    Navigator.pushReplacementNamed(context, '/communityScreen');
  } else {
    Navigator.pop(context);
  }
}, ...)
```

- [ ] **Step 2: Insert a frame-settling delay between the dialog pop and the next navigation**

Replace the body of that `onPressed` with:

```dart
TextButton(onPressed: () async {
  final success = await saveNotes(isSaved: false);
  if (!mounted || !dialogContext.mounted) return;
  Navigator.pop(dialogContext);
  if (!success) return;

  // Popping this confirmation dialog and immediately pushing/replacing
  // the next route in the same synchronous continuation is the same
  // Navigator race already found and fixed in the meditation
  // complete-dialog flow (meditation_screen.dart _shareWithMemories):
  // the pop's transition and the next push's transition can overlap and
  // paint a black frame before either settles. Same fix here.
  await Future<void>.delayed(const Duration(milliseconds: 180));
  if (!mounted) return;

  if (widget.openCommunityAfterPost) {
    Navigator.pushReplacementNamed(context, '/communityScreen');
  } else {
    Navigator.pop(context);
  }
}, ...)
```

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze lib/src/features/authentication/screen/notes/notes_type.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual verification (both platforms)**

Using the `run` skill (or manually): post a "Learning" from a screen that sets `openCommunityAfterPost: true` (e.g. finish a meditation session → "Take photo & share" → post) and confirm the app lands on the Community feed with no black/blank frame, on both an iOS simulator and an Android emulator. Repeat 5+ times in a row (this is a timing race — it may not reproduce every single time even when broken).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/authentication/screen/notes/notes_type.dart
git commit -m "fix(community): prevent black screen from overlapping Navigator transitions after posting"
```

---

### Task 2: Stop a failed daily-activity sync from masking a successful post

**Files:**
- Modify: `lib/src/features/authentication/screen/notes/notes_type.dart` (`saveNotes`, around line 540-619)

**Interfaces:**
- Consumes: nothing new.
- Produces: `saveNotes` still returns `Future<bool>` with the same signature and same success/failure meaning to its caller — only the internal error boundary changes.

**Root cause:** `saveNotes` wraps both `CommunityApiService.instance.createPost(...)` and the secondary `_saveDailyActivity(...)` call inside one `try`. If `createPost` succeeds but `_saveDailyActivity` throws (e.g. a transient network blip — `_saveDailyActivity` itself makes its own separate API call), the whole function falls into `catch` and returns `false`, even though the post was already created server-side. The caller (Task 1's button handler) then does nothing — no navigation, no error message, user stuck on the compose form with a post that already exists (and a duplicate risk if they retry).

- [ ] **Step 1: Read the current `saveNotes` implementation**

Open `lib/src/features/authentication/screen/notes/notes_type.dart`, locate `saveNotes` (search for `CommunityApiService.instance.createPost`). Note the exact current arguments passed to `createPost` and to `CustomSnackBar.showCustomSnackBar` — Step 2 must preserve them exactly, only the try/catch boundary changes.

- [ ] **Step 2: Split post-creation and daily-activity recording into separate error boundaries**

Restructure so a failure in `_saveDailyActivity` can never turn a successful `createPost` into a reported failure:

```dart
try {
  await CommunityApiService.instance.createPost(
    // keep every argument exactly as it is in the current code
  );
} catch (e) {
  print("Error saving note: $e");
  _isSaving = false;
  return false;
}

// The post itself is now saved server-side. A failure recording the
// secondary daily-tracker activity must never be reported as if the
// post failed -- that previously stranded the user on the compose form
// with no error and no navigation, even though their post existed, and
// risked creating a duplicate post if they retried.
try {
  if (category == "Learning") {
    await _saveDailyActivity(learning: true);
  } else if (category == "Add Value") {
    await _saveDailyActivity(addValue: true);
  }
} catch (e) {
  print("Error recording daily activity for post: $e");
}

if (mounted) {
  // keep the existing CustomSnackBar.showCustomSnackBar(...) call exactly as-is
}
_isSaving = false;
return true;
```

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze lib/src/features/authentication/screen/notes/notes_type.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual verification**

Temporarily point `ApiConfig` at an unreachable host for the daily-tracker endpoint only (or use a debugger breakpoint / airplane-mode toggle timed to interrupt only the second call) and confirm: the post still appears in the Community feed and the app still navigates/shows success, even when the daily-activity sync fails. Revert any temporary test config before committing.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/authentication/screen/notes/notes_type.dart
git commit -m "fix(community): don't let a failed daily-activity sync mask a successful post"
```

---

### Task 3: Raise post title limit to 50 characters

**Files:**
- Modify: `lib/src/features/authentication/screen/notes/notes_type.dart` (title `TextField`, around line 409-453)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new — the live "n/50" counter comes for free from Flutter's built-in `TextField.maxLength` counter (already rendering as "n/40" today via `counterStyle`, per the existing code — no new counter widget needed).

Backend already validates `title` as `required|string|max:255` (`CommunityController.php` `store`, unrelated to this change — 50 is a client-side UX cap well under the server's 255 limit, so no backend change is needed).

- [ ] **Step 1: Read the current title field**

Open `lib/src/features/authentication/screen/notes/notes_type.dart`, locate the title `TextField` bound to `titleController` (search for `maxLength: 40`). Confirm it looks like:

```dart
TextField(
  controller: titleController,
  maxLines: 1,
  maxLength: 40,
  decoration: InputDecoration(
    hintText: "Title",
    counterStyle: TextStyle(color: companyTheme.mutedInkColor),
    ...
  ),
)
```

- [ ] **Step 2: Bump the cap and update the adjacent comment**

Change `maxLength: 40` to `maxLength: 50`. If there is a comment near this field referencing "40-char cap" (per the surveyed code), update its wording to say 50.

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze lib/src/features/authentication/screen/notes/notes_type.dart`
Expected: `No issues found!`

- [ ] **Step 4: Manual verification**

Open the compose screen, type into the Title field, confirm the counter reads "n/50" and that typing stops accepting input at 50 characters.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/authentication/screen/notes/notes_type.dart
git commit -m "feat(community): raise post title limit from 40 to 50 characters"
```

---

### Task 4: Optimistic comment submission

**Files:**
- Modify: `lib/src/models/comments_widget.dart` (`CommentWidget.addComment`, around line 91-112, and its comment-list state)
- Test: `test/widget/comment_widget_optimistic_test.dart` — create

**Interfaces:**
- Consumes: `CommentsApiService.instance.addComment({required postId, required comment})` → `Future<CommunityComment>` (unchanged signature, already returns the created comment with its real server id).
- Produces: `CommentWidget` now keeps its own mutable `List<CommunityComment>` in state (seeded from the `FutureBuilder`'s data once loaded) instead of only ever reading from `snapshot.data`; new comments are spliced into that list immediately.

**Root cause:** `addComment` currently does `await _api.addComment(...)` then calls `_reloadComments()`, which reassigns `_commentsFuture = _api.fetchComments(...)` and waits on a **second** full GET round-trip before the new comment is visible. This is a real extra network round-trip on top of the POST, not just a perception issue.

- [ ] **Step 1: Add local comment-list state seeded from the initial fetch**

In `_CommentWidgetState` (or equivalent), add:

```dart
List<CommunityComment>? _comments;
```

Wherever the `FutureBuilder<List<CommunityComment>>` currently reads `snapshot.data` directly to build the list, change it to seed `_comments` the first time data arrives and always render from `_comments` after that:

```dart
FutureBuilder<List<CommunityComment>>(
  future: _commentsFuture,
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting && _comments == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasData && _comments == null) {
      _comments = List<CommunityComment>.from(snapshot.data!);
    }
    final comments = _comments ?? const <CommunityComment>[];
    // ...existing list-building code, but iterate over `comments` instead of `snapshot.data`
  },
)
```

- [ ] **Step 2: Make `addComment` optimistic — insert immediately, reconcile or roll back**

Replace the current `addComment` body:

```dart
Future<void> addComment(String comment) async {
  final trimmed = comment.trim();
  if (trimmed.isEmpty) return;

  final session = AuthService.instance.currentSession;
  final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
  final optimistic = CommunityComment(
    id: tempId,
    postId: widget.postId,
    userId: session?.id.toString() ?? '',
    username: session?.name ?? 'You',
    comment: trimmed,
    createdAt: DateTime.now().toIso8601String(),
    updatedAt: null,
  );

  setState(() {
    _comments = [...(_comments ?? const <CommunityComment>[]), optimistic];
  });
  _commentController.clear();

  try {
    final saved = await _api.addComment(postId: widget.postId, comment: trimmed);
    if (!mounted) return;
    setState(() {
      _comments = [
        for (final c in _comments!)
          if (c.id == tempId) saved else c,
      ];
    });
    widget.onChanged?.call();
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _comments = [
        for (final c in _comments!)
          if (c.id != tempId) c,
      ];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not post your comment. Please try again.')),
    );
  }
}
```

This requires `CommunityComment`'s fields to already be non-final-constructor-assignable as shown (they are, per `comments_api_service.dart`'s existing class shape) — no model changes needed for this task alone (Task 7/8/9 will extend the model further; this task only relies on the fields that already exist: `id, postId, userId, username, comment, createdAt, updatedAt`).

- [ ] **Step 3: Leave edit/delete on the existing refetch pattern for now**

Do not change `_showEditDialog`/`_deleteComment` in this task — they stay on `_reloadComments()`. (If `_comments` is now the source of truth, make `_reloadComments()` also reset `_comments = null` before reassigning `_commentsFuture`, so the `FutureBuilder` re-seeds cleanly:)

```dart
void _reloadComments() {
  setState(() {
    _comments = null;
    _commentsFuture = _api.fetchComments(widget.postId);
  });
}
```

- [ ] **Step 4: Write the widget test**

Create `test/widget/comment_widget_optimistic_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/models/comments_widget.dart';
import 'package:selfcare_projects/src/services/comments_api_service.dart';

void main() {
  testWidgets('a submitted comment appears immediately, before the network call resolves', (tester) async {
    final completer = Completer<CommunityComment>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommentWidget(
            postId: 'post-1',
            fetchCommentsOverride: () async => const <CommunityComment>[],
            addCommentOverride: (postId, comment) => completer.future,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Great post!');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('Great post!'), findsOneWidget);

    completer.complete(const CommunityComment(
      id: 'real-id',
      postId: 'post-1',
      userId: 'u1',
      username: 'Arlene',
      comment: 'Great post!',
      createdAt: '2026-08-04T00:00:00Z',
      updatedAt: null,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Great post!'), findsOneWidget);
  });
}
```

This requires `CommentWidget` to accept two optional test-injection parameters, `fetchCommentsOverride`/`addCommentOverride`, mirroring the `debugLoader` pattern already used by `Leaderboard` (`test/widget/leaderboard_score_breakdown_sheet_test.dart`). Add them to `CommentWidget`'s constructor:

```dart
const CommentWidget({
  super.key,
  required this.postId,
  this.onChanged,
  this.fetchCommentsOverride,
  this.addCommentOverride,
});

final Future<List<CommunityComment>> Function()? fetchCommentsOverride;
final Future<CommunityComment> Function(String postId, String comment)? addCommentOverride;
```

Use them in place of `_api.fetchComments(...)`/`_api.addComment(...)` when non-null (fall back to the real `CommentsApiService.instance` calls otherwise) — same optional-injection-for-testing pattern already established elsewhere in this codebase (`Leaderboard(debugLoader: ...)`).

- [ ] **Step 5: Run the test**

Run: `flutter test test/widget/comment_widget_optimistic_test.dart`
Expected: PASS

- [ ] **Step 6: Run the analyzer and full suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and all tests pass (no regressions).

- [ ] **Step 7: Commit**

```bash
git add lib/src/models/comments_widget.dart test/widget/comment_widget_optimistic_test.dart
git commit -m "feat(community): show new comments immediately (optimistic UI) instead of waiting on a refetch"
```

---

# Part B — Clickable links in posts & comments

### Task 5: Build a shared `LinkifiedText` widget

**Files:**
- Create: `lib/src/widgets/linkified_text.dart`
- Test: `test/unit/linkified_text_test.dart` — create

**Interfaces:**
- Produces: `class LinkifiedText extends StatelessWidget` with constructor `LinkifiedText(String text, {TextStyle? style, TextStyle? linkStyle, Key? key})`. Also exports a pure, testable helper: `List<InlineSpan> buildLinkifiedSpans(String text, {required TextStyle baseStyle, required TextStyle linkStyle, required void Function(String url) onTap})`.

- [ ] **Step 1: Write the failing test for the pure span-building function**

Create `test/unit/linkified_text_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/widgets/linkified_text.dart';

void main() {
  const baseStyle = TextStyle(color: Colors.black);
  const linkStyle = TextStyle(color: Colors.blue);

  test('plain text with no URL produces a single non-tappable span', () {
    final spans = buildLinkifiedSpans(
      'just some text',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
    );
    expect(spans.length, 1);
    expect((spans.first as TextSpan).text, 'just some text');
    expect((spans.first as TextSpan).recognizer, isNull);
  });

  test('detects a bare https URL and wraps only that substring as a link', () {
    final spans = buildLinkifiedSpans(
      'Check this out: https://www.youtube.com/watch?v=xxxxx it is great',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
    );
    final texts = spans.map((s) => (s as TextSpan).text).toList();
    expect(texts, [
      'Check this out: ',
      'https://www.youtube.com/watch?v=xxxxx',
      ' it is great',
    ]);
    expect((spans[1] as TextSpan).style?.color, Colors.blue);
    expect((spans[1] as TextSpan).recognizer, isNotNull);
    expect((spans[0] as TextSpan).recognizer, isNull);
  });

  test('detects multiple URLs in the same text', () {
    final spans = buildLinkifiedSpans(
      'a.com then http://b.com/x then https://c.org',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (_) {},
    );
    final links = spans
        .whereType<TextSpan>()
        .where((s) => s.recognizer != null)
        .map((s) => s.text)
        .toList();
    expect(links, ['http://b.com/x', 'https://c.org']);
  });

  test('tapping the link span invokes onTap with the exact URL', () {
    String? tapped;
    final spans = buildLinkifiedSpans(
      'go to https://example.com/page now',
      baseStyle: baseStyle,
      linkStyle: linkStyle,
      onTap: (url) => tapped = url,
    );
    final linkSpan = spans.whereType<TextSpan>().firstWhere((s) => s.recognizer != null);
    (linkSpan.recognizer as TapGestureRecognizer).onTap!();
    expect(tapped, 'https://example.com/page');
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `flutter test test/unit/linkified_text_test.dart`
Expected: FAIL (file `lib/src/widgets/linkified_text.dart` does not exist yet)

- [ ] **Step 3: Implement `linkified_text.dart`**

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _urlPattern = RegExp(
  r'((https?:\/\/)[^\s]+)',
  caseSensitive: false,
);

/// Splits [text] into spans, wrapping any http(s) URL substring as a
/// tappable, distinctly-styled span. Covers YouTube/Facebook/Instagram/
/// TikTok/plain websites the same way -- they're all just http(s) URLs;
/// the OS itself resolves a tap to the installed app (via universal/app
/// links) or the default browser when the app isn't installed, so no
/// per-domain special-casing is needed here.
List<InlineSpan> buildLinkifiedSpans(
  String text, {
  required TextStyle baseStyle,
  required TextStyle linkStyle,
  required void Function(String url) onTap,
}) {
  final matches = _urlPattern.allMatches(text).toList();
  if (matches.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start), style: baseStyle));
    }
    final url = match.group(0)!;
    spans.add(
      TextSpan(
        text: url,
        style: linkStyle,
        recognizer: TapGestureRecognizer()..onTap = () => onTap(url),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
}

class LinkifiedText extends StatelessWidget {
  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final resolvedLinkStyle = (linkStyle ?? baseStyle).copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        children: buildLinkifiedSpans(
          text,
          baseStyle: baseStyle,
          linkStyle: resolvedLinkStyle,
          onTap: _open,
        ),
      ),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/linkified_text_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/src/widgets/linkified_text.dart test/unit/linkified_text_test.dart
git commit -m "feat(community): add reusable LinkifiedText widget for clickable URLs"
```

---

### Task 6: Wire `LinkifiedText` into post bodies and comments

**Files:**
- Modify: `lib/src/models/note_card.dart` (post body text rendering)
- Modify: `lib/src/models/comments_widget.dart` (comment text rendering)

**Interfaces:**
- Consumes: `LinkifiedText` from Task 5.

- [ ] **Step 1: Replace the plain `Text` rendering the post body text item**

In `note_card.dart`, find where a note item of `type == "text"` is rendered as `Text(textContent, style: ...)` (the same block that already handles the "Read More/Read Less" expansion). Replace the `Text(...)` used for the (possibly truncated) `textContent` with:

```dart
LinkifiedText(
  isExpanded ? textContent : textContent.substring(0, isLongText ? 150 : textContent.length),
  style: const TextStyle(
    fontSize: 16,
    color: Color.fromARGB(221, 19, 19, 19),
    height: 1.5,
  ),
)
```

Add the import: `import 'package:selfcare_projects/src/widgets/linkified_text.dart';`

- [ ] **Step 2: Replace the plain `Text` rendering each comment's body**

In `comments_widget.dart`, find the `Text(comment.comment, ...)` used to render a comment row's body and replace it with:

```dart
LinkifiedText(
  comment.comment,
  style: TextStyle(color: companyTheme.inkColor, fontSize: 14),
)
```

Add the same import.

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Manual verification**

Post a Community "Learning" (or comment) containing a mix of plain text and a URL (e.g. `Check this out https://www.youtube.com/watch?v=dQw4w9WgXcQ cool right?`). Confirm the URL renders underlined/colored and tapping it opens the YouTube app (if installed) or a browser, on both iOS and Android.

- [ ] **Step 5: Commit**

```bash
git add lib/src/models/note_card.dart lib/src/models/comments_widget.dart
git commit -m "feat(community): make URLs in post bodies and comments clickable"
```

---

# Part C — Comment avatars (live, updates with profile changes)

### Task 7: Backend — return the commenter's current profile picture

**Files:**
- Modify: `backend/app/Models/NoteComment.php`
- Modify: `backend/app/Http/Controllers/Api/CommentController.php`
- Test: `backend/tests/Feature/CommentAvatarTest.php` — create

**Interfaces:**
- Produces: `CommentController::mapComment` response gains a `profilePic` key (string or null) alongside the existing `id, postId, userId, username, comment, createdAt, updatedAt`.

- [ ] **Step 1: Add the `user()` relation to `NoteComment`**

`NoteComment` currently declares no relations at all. Add:

```php
public function user(): \Illuminate\Database\Eloquent\Relations\BelongsTo
{
    return $this->belongsTo(\App\Models\User::class);
}
```

- [ ] **Step 2: Write the failing feature test**

Create `backend/tests/Feature/CommentAvatarTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommentAvatarTest extends TestCase
{
    use RefreshDatabase;

    private function makePost(User $owner): CommunityPost
    {
        return CommunityPost::create([
            'user_id' => $owner->id,
            'username' => $owner->name,
            'title' => 'Test post',
            'note' => [['type' => 'text', 'value' => 'hello']],
            'color' => 0xFFFFFFFF,
            'category' => 'General',
            'saved' => false,
        ]);
    }

    public function test_comment_response_includes_the_commenters_current_profile_pic(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create(['profile_pic' => 'https://cdn.example.com/avatar-v1.png']);
        $post = $this->makePost($owner);

        Sanctum::actingAs($commenter);
        $response = $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'nice post',
        ]);

        $response->assertOk()->assertJsonPath('comment.profilePic', 'https://cdn.example.com/avatar-v1.png');
    }

    public function test_avatar_reflects_a_later_profile_picture_change_without_editing_the_comment(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create(['profile_pic' => 'https://cdn.example.com/avatar-v1.png']);
        $post = $this->makePost($owner);

        $comment = NoteComment::create([
            'community_post_id' => $post->id,
            'user_id' => $commenter->id,
            'username' => $commenter->name,
            'comment' => 'nice post',
        ]);

        $commenter->update(['profile_pic' => 'https://cdn.example.com/avatar-v2.png']);

        Sanctum::actingAs($owner);
        $response = $this->getJson("/api/community/posts/{$post->id}/comments");

        $response->assertOk();
        $payload = collect($response->json())->firstWhere('id', $comment->id);
        $this->assertSame('https://cdn.example.com/avatar-v2.png', $payload['profilePic']);
    }

    public function test_missing_profile_pic_returns_null_not_an_error(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create(['profile_pic' => null]);
        $post = $this->makePost($owner);

        Sanctum::actingAs($commenter);
        $response = $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'no avatar here',
        ]);

        $response->assertOk()->assertJsonPath('comment.profilePic', null);
    }
}
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommentAvatarTest`
Expected: FAIL (`profilePic` key missing from response)

- [ ] **Step 4: Update `mapComment` to eager-load and expose `profilePic`**

In `CommentController.php`:
- In `index`, change the query from `NoteComment::query()->where('community_post_id', $post->id)->orderByDesc('created_at')->get()` to eager-load the relation: `NoteComment::query()->with('user')->where('community_post_id', $post->id)->orderByDesc('created_at')->get()`.
- In `store`/`update`, after creating/saving the comment, call `$comment->load('user');` before passing it to `mapComment` (so the relation is available there too, even though `store`/`update` operate on a single row and don't need eager-load batching).
- In `mapComment`, add the field:

```php
private function mapComment(NoteComment $comment): array
{
    return [
        'id' => (string) $comment->id,
        'postId' => (string) $comment->community_post_id,
        'userId' => (string) $comment->user_id,
        'username' => $comment->username,
        'profilePic' => $comment->user?->profile_pic,
        'comment' => $comment->comment,
        'createdAt' => $this->serializeAppDate($comment->created_at),
        'updatedAt' => $this->serializeAppDate($comment->updated_at),
    ];
}
```

(Keep every other existing line/field in `mapComment` exactly as-is — only the `'profilePic' => ...` line is new. `$comment->user?->profile_pic` safely returns `null` if the user relation somehow can't resolve, e.g. a deleted user — though `cascadeOnDelete()` on `note_comments.user_id` means an orphaned comment shouldn't normally exist.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommentAvatarTest`
Expected: PASS (all 3 tests)

- [ ] **Step 6: Run the full backend suite to check for regressions**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml`
Expected: all tests pass, including the pre-existing `CommunityPostHeartTest`.

- [ ] **Step 7: Commit**

```bash
git add backend/app/Models/NoteComment.php backend/app/Http/Controllers/Api/CommentController.php backend/tests/Feature/CommentAvatarTest.php
git commit -m "feat(community): include commenter's live profile picture in comment payloads"
```

---

### Task 8: Frontend — render commenter avatars

**Files:**
- Modify: `lib/src/services/comments_api_service.dart` (`CommunityComment` model)
- Modify: `lib/src/models/comments_widget.dart` (comment row UI)

**Interfaces:**
- Produces: `CommunityComment.profilePic` (`String?`).

- [ ] **Step 1: Add `profilePic` to `CommunityComment`**

In `comments_api_service.dart`, add a `final String? profilePic;` field to the `CommunityComment` class, thread it through the constructor (including the `const` constructor used in Task 4's optimistic-insert code — pass `profilePic: session?.profilePic` there, sourced from `AuthService.instance.currentSession?.profilePic`, which already exists per `AuthService`/`AppSession`), and parse it from JSON: `profilePic: json['profilePic'] as String?,` in whatever factory/parsing method builds `CommunityComment` from the API response map.

- [ ] **Step 2: Replace the placeholder icon with a real avatar**

In `comments_widget.dart`, replace:

```dart
Icon(
  Icons.account_circle_rounded,
  size: 40,
  color: companyTheme.iconColor,
),
```

with:

```dart
CircleAvatar(
  radius: 20,
  backgroundColor: companyTheme.iconColor.withValues(alpha: 0.15),
  backgroundImage: (comment.profilePic?.isNotEmpty ?? false)
      ? NetworkImage(comment.profilePic!)
      : null,
  child: (comment.profilePic?.isNotEmpty ?? false)
      ? null
      : Icon(Icons.account_circle_rounded, size: 40, color: companyTheme.iconColor),
),
```

This matches the existing avatar convention already used in `chat_room.dart` (`CircleAvatar` + `NetworkImage` with an icon fallback).

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Manual verification**

Comment on a post as a user with a profile picture set — confirm the avatar shows. Comment as a user with no picture — confirm the fallback icon shows. Change your profile picture, then view an *existing* comment you made before the change — confirm the avatar updates to the new picture (proves the live-join, not a stale snapshot).

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/comments_api_service.dart lib/src/models/comments_widget.dart
git commit -m "feat(community): show commenter avatars in the comment list"
```

---

# Part D — Comment reactions

### Task 9: Backend — `comment_reactions` table, model, controller

**Files:**
- Create: `backend/database/migrations/2026_08_04_000001_create_comment_reactions_table.php`
- Create: `backend/app/Models/CommentReaction.php`
- Create: `backend/app/Http/Controllers/Api/CommentReactionController.php`
- Modify: `backend/app/Models/NoteComment.php` (add `reactions()` relation)
- Modify: `backend/routes/api.php`
- Test: `backend/tests/Feature/CommentReactionTest.php` — create

**Interfaces:**
- Produces: `POST /api/community/posts/{post}/comments/{comment}/reactions` and `DELETE /api/community/posts/{post}/comments/{comment}/reactions`, each returning `{commentId, reactionsCount, reactedByMe}`. `CommentController::mapComment` gains `reactionsCount` (int) and `reactedByMe` (bool).

This mirrors `CommunityPostHeart`/`PostHeartController` exactly — same shape, same duplicate-prevention strategy (DB unique constraint), same notification-gating pattern.

- [ ] **Step 1: Write the migration**

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('comment_reactions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('note_comment_id')->constrained('note_comments')->cascadeOnDelete();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->timestamps();

            // The DB is the real guard against duplicate reactions, same
            // as community_post_hearts -- firstOrCreate() in the
            // controller is a convenience wrapper around this, not the
            // actual guard.
            $table->unique(['note_comment_id', 'user_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('comment_reactions');
    }
};
```

- [ ] **Step 2: Create the `CommentReaction` model**

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class CommentReaction extends Model
{
    use HasFactory;

    protected $fillable = ['note_comment_id', 'user_id'];
}
```

- [ ] **Step 3: Add the `reactions()` relation to `NoteComment`**

```php
public function reactions(): \Illuminate\Database\Eloquent\Relations\HasMany
{
    return $this->hasMany(\App\Models\CommentReaction::class);
}
```

- [ ] **Step 4: Write the failing feature test**

Create `backend/tests/Feature/CommentReactionTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommentReactionTest extends TestCase
{
    use RefreshDatabase;

    private function makeComment(User $postOwner, User $commenter): array
    {
        $post = CommunityPost::create([
            'user_id' => $postOwner->id,
            'username' => $postOwner->name,
            'title' => 'Test post',
            'note' => [['type' => 'text', 'value' => 'hello']],
            'color' => 0xFFFFFFFF,
            'category' => 'General',
            'saved' => false,
        ]);
        $comment = NoteComment::create([
            'community_post_id' => $post->id,
            'user_id' => $commenter->id,
            'username' => $commenter->name,
            'comment' => 'nice',
        ]);
        return [$post, $comment];
    }

    public function test_reacting_to_a_comment_notifies_the_commenter_but_not_when_reacting_to_your_own(): void
    {
        $postOwner = User::factory()->create();
        $commenter = User::factory()->create();
        $reactor = User::factory()->create();
        [$post, $comment] = $this->makeComment($postOwner, $commenter);

        Sanctum::actingAs($reactor);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();
        $this->assertDatabaseHas('notifications', [
            'user_id' => (string) $commenter->id,
            'type' => 'comment_reaction',
        ]);

        Sanctum::actingAs($commenter);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();
        $this->assertDatabaseMissing('notifications', [
            'user_id' => (string) $commenter->id,
            'type' => 'comment_reaction',
            'data->reactedByUserId' => (string) $commenter->id,
        ]);
    }

    public function test_reacting_twice_from_the_same_user_does_not_duplicate(): void
    {
        $postOwner = User::factory()->create();
        $commenter = User::factory()->create();
        $reactor = User::factory()->create();
        [$post, $comment] = $this->makeComment($postOwner, $commenter);

        Sanctum::actingAs($reactor);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();
        $response = $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions");

        $response->assertOk()->assertJsonPath('reactionsCount', 1);
        $this->assertSame(1, \App\Models\CommentReaction::query()
            ->where('note_comment_id', $comment->id)->where('user_id', $reactor->id)->count());
    }

    public function test_removing_a_reaction_updates_the_count(): void
    {
        $postOwner = User::factory()->create();
        $commenter = User::factory()->create();
        $reactor = User::factory()->create();
        [$post, $comment] = $this->makeComment($postOwner, $commenter);

        Sanctum::actingAs($reactor);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();
        $response = $this->deleteJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions");

        $response->assertOk()->assertJsonPath('reactionsCount', 0)->assertJsonPath('reactedByMe', false);
    }

    public function test_comment_listing_reflects_reaction_count_and_whether_the_viewer_reacted(): void
    {
        $postOwner = User::factory()->create();
        $commenter = User::factory()->create();
        $fan = User::factory()->create();
        $bystander = User::factory()->create();
        [$post, $comment] = $this->makeComment($postOwner, $commenter);

        Sanctum::actingAs($fan);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();

        Sanctum::actingAs($fan);
        $fanView = $this->getJson("/api/community/posts/{$post->id}/comments");
        $fanComment = collect($fanView->json())->firstWhere('id', (string) $comment->id);
        $this->assertSame(1, $fanComment['reactionsCount']);
        $this->assertTrue($fanComment['reactedByMe']);

        Sanctum::actingAs($bystander);
        $bystanderView = $this->getJson("/api/community/posts/{$post->id}/comments");
        $bystanderComment = collect($bystanderView->json())->firstWhere('id', (string) $comment->id);
        $this->assertSame(1, $bystanderComment['reactionsCount']);
        $this->assertFalse($bystanderComment['reactedByMe']);
    }
}
```

- [ ] **Step 5: Run it to confirm it fails**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommentReactionTest`
Expected: FAIL (route/controller don't exist yet — 404s)

- [ ] **Step 6: Implement `CommentReactionController`**

```php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommentReaction;
use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CommentReactionController extends Controller
{
    public function store(Request $request, CommunityPost $post, NoteComment $comment): JsonResponse
    {
        $user = $request->user();
        abort_unless((int) $comment->community_post_id === (int) $post->id, 404);

        $reaction = CommentReaction::query()->firstOrCreate([
            'note_comment_id' => $comment->id,
            'user_id' => $user->id,
        ]);

        if ($reaction->wasRecentlyCreated && (string) $comment->user_id !== (string) $user->id) {
            Notification::createFor(
                (string) $comment->user_id,
                'comment_reaction',
                sprintf('%s reacted to your comment', $user->name),
                null,
                [
                    'postId' => (string) $post->id,
                    'commentId' => (string) $comment->id,
                    'reactedByUserId' => (string) $user->id,
                ],
            );
        }

        return response()->json($this->reactionState($comment, $user->id));
    }

    public function destroy(Request $request, CommunityPost $post, NoteComment $comment): JsonResponse
    {
        $user = $request->user();
        abort_unless((int) $comment->community_post_id === (int) $post->id, 404);

        CommentReaction::query()
            ->where('note_comment_id', $comment->id)
            ->where('user_id', $user->id)
            ->delete();

        return response()->json($this->reactionState($comment, $user->id));
    }

    private function reactionState(NoteComment $comment, int $userId): array
    {
        return [
            'commentId' => (string) $comment->id,
            'reactionsCount' => CommentReaction::query()->where('note_comment_id', $comment->id)->count(),
            'reactedByMe' => CommentReaction::query()
                ->where('note_comment_id', $comment->id)
                ->where('user_id', $userId)
                ->exists(),
        ];
    }
}
```

- [ ] **Step 7: Register the routes**

In `routes/api.php`, next to the existing comment routes, add:

```php
Route::post('/community/posts/{post}/comments/{comment}/reactions', [CommentReactionController::class, 'store']);
Route::delete('/community/posts/{post}/comments/{comment}/reactions', [CommentReactionController::class, 'destroy']);
```

Add the `use App\Http\Controllers\Api\CommentReactionController;` import at the top of the file if route-class imports are used there (check the existing style for `PostHeartController`'s import and match it).

- [ ] **Step 8: Update `CommentController::mapComment` to include reaction state**

Add to `mapComment` (alongside the `profilePic` field added in Task 7):

```php
'reactionsCount' => $comment->reactions()->count(),
'reactedByMe' => $comment->reactions()->where('user_id', auth()->id())->exists(),
```

(Two extra queries per comment row, matching the exact non-eager-loaded style `PostHeartController::heartState`/`CommunityController::mapPost` already use for posts — not eager-loaded here either, consistent with the existing codebase's accepted tradeoff for this size of dataset.)

- [ ] **Step 9: Run the test to verify it passes**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommentReactionTest`
Expected: PASS (all 4 tests)

- [ ] **Step 10: Run the full backend suite**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml`
Expected: all tests pass.

- [ ] **Step 11: Commit**

```bash
git add backend/database/migrations/2026_08_04_000001_create_comment_reactions_table.php \
  backend/app/Models/CommentReaction.php backend/app/Models/NoteComment.php \
  backend/app/Http/Controllers/Api/CommentReactionController.php \
  backend/app/Http/Controllers/Api/CommentController.php backend/routes/api.php \
  backend/tests/Feature/CommentReactionTest.php
git commit -m "feat(community): add comment reactions backend (mirrors post hearts)"
```

---

### Task 10: Frontend — comment reaction button

**Files:**
- Modify: `lib/src/services/comments_api_service.dart` (`CommunityComment` gains `reactionsCount`/`reactedByMe`; add `reactComment`/`unreactComment`)
- Modify: `lib/src/models/comments_widget.dart` (reaction button UI, optimistic count)

**Interfaces:**
- Consumes: `POST/DELETE /community/posts/{postId}/comments/{commentId}/reactions` from Task 9.
- Produces: `CommentsApiService.instance.reactComment({required postId, required commentId})` and `.unreactComment({required postId, required commentId})`, both `Future<CommentReactionState>`, where `CommentReactionState{commentId, reactionsCount, reactedByMe}` (new small class, same shape as the existing `PostHeartState`).

- [ ] **Step 1: Add fields to `CommunityComment` and the new `CommentReactionState` class**

In `comments_api_service.dart`, add `final int reactionsCount;` and `final bool reactedByMe;` to `CommunityComment` (thread through constructor + JSON parsing, defaulting to `0`/`false` if absent for backward compatibility with any cached/older payload), and add:

```dart
class CommentReactionState {
  const CommentReactionState({
    required this.commentId,
    required this.reactionsCount,
    required this.reactedByMe,
  });

  factory CommentReactionState.fromJson(Map<String, dynamic> json) {
    return CommentReactionState(
      commentId: json['commentId'].toString(),
      reactionsCount: (json['reactionsCount'] as num).toInt(),
      reactedByMe: json['reactedByMe'] == true,
    );
  }

  final String commentId;
  final int reactionsCount;
  final bool reactedByMe;
}
```

- [ ] **Step 2: Add the two API methods**

```dart
Future<CommentReactionState> reactComment({
  required String postId,
  required String commentId,
}) async {
  final response = await _api.postJson(
    '/api/community/posts/$postId/comments/$commentId/reactions',
    {},
    token: _token,
  );
  return CommentReactionState.fromJson(response);
}

Future<CommentReactionState> unreactComment({
  required String postId,
  required String commentId,
}) async {
  final response = await _api.deleteJson(
    '/api/community/posts/$postId/comments/$commentId/reactions',
    token: _token,
  );
  return CommentReactionState.fromJson(response);
}
```

(Match the exact `_api`/`_token` field names already used by the other methods in this class.)

- [ ] **Step 3: Add the reaction button to each comment row, with optimistic toggling**

In `comments_widget.dart`, in the comment row layout, add a small heart button below/beside the comment text:

```dart
Row(
  children: [
    InkWell(
      onTap: () => _toggleReaction(comment),
      child: Row(
        children: [
          Icon(
            comment.reactedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 16,
            color: comment.reactedByMe ? Colors.redAccent : companyTheme.mutedInkColor,
          ),
          const SizedBox(width: 4),
          Text(
            '${comment.reactionsCount}',
            style: TextStyle(fontSize: 12, color: companyTheme.mutedInkColor),
          ),
        ],
      ),
    ),
  ],
)
```

Add the handler, using the same local `_comments` list state introduced in Task 4:

```dart
Future<void> _toggleReaction(CommunityComment comment) async {
  final wasReacted = comment.reactedByMe;
  final optimistic = CommunityComment(
    id: comment.id,
    postId: comment.postId,
    userId: comment.userId,
    username: comment.username,
    profilePic: comment.profilePic,
    comment: comment.comment,
    createdAt: comment.createdAt,
    updatedAt: comment.updatedAt,
    reactionsCount: comment.reactionsCount + (wasReacted ? -1 : 1),
    reactedByMe: !wasReacted,
  );
  setState(() {
    _comments = [
      for (final c in _comments!)
        if (c.id == comment.id) optimistic else c,
    ];
  });

  try {
    final state = wasReacted
        ? await _api.unreactComment(postId: widget.postId, commentId: comment.id)
        : await _api.reactComment(postId: widget.postId, commentId: comment.id);
    if (!mounted) return;
    setState(() {
      _comments = [
        for (final c in _comments!)
          if (c.id == comment.id)
            CommunityComment(
              id: c.id, postId: c.postId, userId: c.userId, username: c.username,
              profilePic: c.profilePic, comment: c.comment, createdAt: c.createdAt,
              updatedAt: c.updatedAt, reactionsCount: state.reactionsCount, reactedByMe: state.reactedByMe,
            )
          else c,
      ];
    });
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _comments = [
        for (final c in _comments!)
          if (c.id == comment.id) comment else c, // roll back to the pre-tap value
      ];
    });
  }
}
```

This mirrors `NoteCardState._toggleHeart`'s existing optimistic-update/rollback shape for post hearts (`note_card.dart:46-85`) — same pattern, applied to comments.

- [ ] **Step 4: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Manual verification**

React to a comment, confirm the heart fills and count increments immediately (before any network latency is visible). Un-react, confirm it decrements. Force a network failure (airplane mode mid-tap) and confirm it rolls back to the prior state rather than getting stuck.

- [ ] **Step 6: Commit**

```bash
git add lib/src/services/comments_api_service.dart lib/src/models/comments_widget.dart
git commit -m "feat(community): add comment reactions to the Flutter UI"
```

---

# Part E — Threaded comment replies

### Task 11: Backend — `parent_id` on `note_comments`

**Files:**
- Create: `backend/database/migrations/2026_08_04_000002_add_parent_id_to_note_comments_table.php`
- Modify: `backend/app/Models/NoteComment.php`
- Modify: `backend/app/Http/Controllers/Api/CommentController.php`
- Test: `backend/tests/Feature/CommentReplyTest.php` — create

**Interfaces:**
- Produces: `POST /community/posts/{post}/comments` now accepts an optional `parentId` field; `mapComment` response gains `parentId` (string, nullable). `index` still returns a **flat** list (client groups into threads — see Task 12) ordered oldest-first-within-thread-friendly order: keep the existing `orderByDesc('created_at')` for top-level ordering but this plan does NOT change ordering semantics beyond adding the field; grouping/display order is a client concern in Task 12.

One level of threading only (a reply cannot itself be replied to) — matches the spec's explicitly-offered simpler option ("one-level threading") and keeps the data model and UI both simple.

- [ ] **Step 1: Write the migration**

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('note_comments', function (Blueprint $table) {
            $table->foreignId('parent_id')->nullable()->after('user_id')
                ->constrained('note_comments')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('note_comments', function (Blueprint $table) {
            $table->dropConstrainedForeignId('parent_id');
        });
    }
};
```

- [ ] **Step 2: Add `parent_id` to `NoteComment`'s fillable and add relations**

```php
protected $fillable = ['firestore_id', 'community_post_id', 'user_id', 'parent_id', 'username', 'comment'];

public function parent(): \Illuminate\Database\Eloquent\Relations\BelongsTo
{
    return $this->belongsTo(NoteComment::class, 'parent_id');
}

public function replies(): \Illuminate\Database\Eloquent\Relations\HasMany
{
    return $this->hasMany(NoteComment::class, 'parent_id');
}
```

- [ ] **Step 3: Write the failing feature test**

Create `backend/tests/Feature/CommentReplyTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommentReplyTest extends TestCase
{
    use RefreshDatabase;

    private function makePost(User $owner): CommunityPost
    {
        return CommunityPost::create([
            'user_id' => $owner->id,
            'username' => $owner->name,
            'title' => 'Test post',
            'note' => [['type' => 'text', 'value' => 'hello']],
            'color' => 0xFFFFFFFF,
            'category' => 'General',
            'saved' => false,
        ]);
    }

    public function test_a_reply_is_created_with_the_parent_comment_id(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create();
        $replier = User::factory()->create();
        $post = $this->makePost($owner);

        Sanctum::actingAs($commenter);
        $parent = $this->postJson("/api/community/posts/{$post->id}/comments", ['comment' => 'top level'])->json();

        Sanctum::actingAs($replier);
        $reply = $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'a reply',
            'parentId' => $parent['id'],
        ]);

        $reply->assertOk()->assertJsonPath('parentId', $parent['id']);
    }

    public function test_a_top_level_comment_has_a_null_parent_id(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create();
        $post = $this->makePost($owner);

        Sanctum::actingAs($commenter);
        $response = $this->postJson("/api/community/posts/{$post->id}/comments", ['comment' => 'top level']);

        $response->assertOk()->assertJsonPath('parentId', null);
    }

    public function test_replying_notifies_the_parent_comments_author_but_not_when_replying_to_yourself(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create();
        $replier = User::factory()->create();
        $post = $this->makePost($owner);

        $parent = NoteComment::create([
            'community_post_id' => $post->id,
            'user_id' => $commenter->id,
            'username' => $commenter->name,
            'comment' => 'top level',
        ]);

        Sanctum::actingAs($replier);
        $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'a reply', 'parentId' => $parent->id,
        ])->assertOk();
        $this->assertDatabaseHas('notifications', [
            'user_id' => (string) $commenter->id,
            'type' => 'comment_reply',
        ]);

        Sanctum::actingAs($commenter);
        $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'replying to myself', 'parentId' => $parent->id,
        ])->assertOk();
        $this->assertDatabaseMissing('notifications', [
            'user_id' => (string) $commenter->id,
            'type' => 'comment_reply',
            'data->replierId' => (string) $commenter->id,
        ]);
    }

    public function test_a_parentid_pointing_to_a_comment_on_a_different_post_is_rejected(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create();
        $postA = $this->makePost($owner);
        $postB = $this->makePost($owner);

        $foreignComment = NoteComment::create([
            'community_post_id' => $postB->id,
            'user_id' => $owner->id,
            'username' => $owner->name,
            'comment' => 'on a different post',
        ]);

        Sanctum::actingAs($commenter);
        $response = $this->postJson("/api/community/posts/{$postA->id}/comments", [
            'comment' => 'sneaky reply', 'parentId' => $foreignComment->id,
        ]);

        $response->assertStatus(422);
    }
}
```

- [ ] **Step 4: Run it to confirm it fails**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommentReplyTest`
Expected: FAIL

- [ ] **Step 5: Update `CommentController::store` to accept and validate `parentId`**

Add to the validation array in `store`:

```php
'parent_id' => ['sometimes', 'nullable', 'integer', Rule::exists('note_comments', 'id')->where('community_post_id', $post->id)],
```

Note the incoming JSON key is `parentId` (camelCase, matching this app's client convention) but Laravel validates/reads the raw request key as sent — check how the existing `store` method's validation array keys line up with the client's camelCase `comment` field (the client already sends `{'comment': comment}` and the backend validates `'comment'`, so field names are NOT camelCase-transformed anywhere in this controller — the client must send `'comment'` verbatim). Confirm this and validate `'parentId'` (not `'parent_id'`) as the key to match that existing convention exactly:

```php
$validated = $request->validate([
    'comment' => ['required', 'string', 'max:5000'],
    'parentId' => ['sometimes', 'nullable', 'integer', Rule::exists('note_comments', 'id')->where('community_post_id', $post->id)],
]);
```

Add `use Illuminate\Validation\Rule;` import if not already present. Then when creating the comment, add `'parent_id' => $validated['parentId'] ?? null,` to the `NoteComment::create([...])` call.

After creating, if `parent_id` is set, load the parent and notify its author instead of (or in addition to) the post owner:

```php
if (!empty($validated['parentId'])) {
    $parent = NoteComment::find($validated['parentId']);
    if ($parent && (string) $parent->user_id !== (string) $user->id) {
        Notification::createFor(
            (string) $parent->user_id,
            'comment_reply',
            sprintf('%s replied to your comment', $user->name),
            Str::limit(trim((string) $validated['comment']), 80),
            [
                'postId' => (string) $post->id,
                'commentId' => (string) $comment->id,
                'parentCommentId' => (string) $parent->id,
                'replierId' => (string) $user->id,
            ],
        );
    }
} elseif ((string) $post->user_id !== (string) $user->id) {
    // existing "community_comment" notification to the post owner, unchanged
}
```

(Keep the existing top-level "notify the post owner" logic exactly as it is today, just move it into that `elseif` branch so a reply notifies the parent-comment author instead of double-notifying the post owner.)

- [ ] **Step 6: Add `parentId` to `mapComment`**

```php
'parentId' => $comment->parent_id !== null ? (string) $comment->parent_id : null,
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommentReplyTest`
Expected: PASS (all 4 tests)

- [ ] **Step 8: Run the full backend suite**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml`
Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add backend/database/migrations/2026_08_04_000002_add_parent_id_to_note_comments_table.php \
  backend/app/Models/NoteComment.php backend/app/Http/Controllers/Api/CommentController.php \
  backend/tests/Feature/CommentReplyTest.php
git commit -m "feat(community): support one-level threaded replies on comments"
```

---

### Task 12: Frontend — reply button and nested rendering

**Files:**
- Modify: `lib/src/services/comments_api_service.dart` (`CommunityComment` gains `parentId`; `addComment` accepts optional `parentId`)
- Modify: `lib/src/models/comments_widget.dart` (Reply button, nested list, reply composer targeting)

**Interfaces:**
- Consumes: `parentId` field and `POST .../comments {parentId}` from Task 11.

- [ ] **Step 1: Add `parentId` to `CommunityComment` and `addComment`**

Add `final String? parentId;` to `CommunityComment` (thread through constructor/JSON parsing: `parentId: json['parentId'] as String?,`). Update `addComment`:

```dart
Future<CommunityComment> addComment({
  required String postId,
  required String comment,
  String? parentId,
}) async {
  final response = await _api.postJson(
    '/api/community/posts/$postId/comments',
    {
      'comment': comment,
      if (parentId != null) 'parentId': parentId,
    },
    token: _token,
  );
  return CommunityComment.fromJson(response['comment'] as Map<String, dynamic>);
}
```

(Adjust to match the exact existing response-unwrapping shape already used by this method — check whether the current code reads `response['comment']` or the raw `response` map, and keep that convention; only the new `parentId` request field and parameter are additions.)

- [ ] **Step 2: Track which comment is being replied to, and group replies under parents in the render**

Add state:

```dart
CommunityComment? _replyingTo;
```

Add a "Reply" `TextButton` under each top-level comment's action row (next to the reaction button from Task 10):

```dart
TextButton(
  onPressed: () => setState(() => _replyingTo = comment),
  child: const Text('Reply', style: TextStyle(fontSize: 12)),
)
```

When building the list from `_comments`, group into top-level + replies-by-parent:

```dart
final topLevel = _comments!.where((c) => c.parentId == null).toList();
final repliesByParent = <String, List<CommunityComment>>{};
for (final c in _comments!) {
  if (c.parentId != null) {
    (repliesByParent[c.parentId!] ??= []).add(c);
  }
}
```

Render each top-level comment, then indent its `repliesByParent[comment.id] ?? []` beneath it (e.g. `Padding(padding: const EdgeInsets.only(left: 40), child: Column(children: [for (final reply in replies) _buildCommentRow(reply)]))`), reusing whatever row-building function/widget already renders a single comment (extract one if the current code doesn't already have a reusable per-row builder — do this extraction as part of this step, since Tasks 4/8/10 already touched this row's contents).

- [ ] **Step 3: Show a "Replying to @username" chip above the input when `_replyingTo` is set, and pass `parentId` on submit**

```dart
if (_replyingTo != null)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      children: [
        Expanded(child: Text('Replying to ${_replyingTo!.username}', style: const TextStyle(fontSize: 12))),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          onPressed: () => setState(() => _replyingTo = null),
        ),
      ],
    ),
  ),
```

Update `addComment` (from Task 4) to pass `parentId: _replyingTo?.id` into `_api.addComment(...)` and into the optimistic `CommunityComment(...)` construction, then clear `_replyingTo` after a successful/failed submit (`setState(() => _replyingTo = null);` alongside the existing `_commentController.clear()`).

- [ ] **Step 4: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Manual verification**

Reply to a comment, confirm it renders indented beneath its parent. Confirm the reply composer shows "Replying to X" and that clearing it (X button) returns to a normal top-level comment.

- [ ] **Step 6: Commit**

```bash
git add lib/src/services/comments_api_service.dart lib/src/models/comments_widget.dart
git commit -m "feat(community): add threaded comment replies to the Flutter UI"
```

---

# Part F — Comment notification deep link + scroll/highlight

### Task 13: `CommunityScreen` accepts a target post/comment and opens it

**Files:**
- Modify: `lib/src/features/authentication/screen/community/community_screen.dart`
- Modify: `lib/src/services/notification_push_router.dart`

**Interfaces:**
- Produces: `CommunityScreen({Key? key, String? targetPostId, String? targetCommentId})`.

- [ ] **Step 1: Add optional constructor parameters**

```dart
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, this.targetPostId, this.targetCommentId});

  final String? targetPostId;
  final String? targetCommentId;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}
```

- [ ] **Step 2: After the initial post list loads, if a target is set, open that post's comment sheet**

In `_CommunityScreenState`, after `_loadPosts(...)` completes in `initState`'s existing flow, add:

```dart
if (widget.targetPostId != null) {
  final target = _posts.firstWhereOrNull((p) => p.id == widget.targetPostId);
  if (target != null && mounted) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openCommentsFor(target, highlightCommentId: widget.targetCommentId);
    });
  }
}
```

(`firstWhereOrNull` is from `package:collection`, already a transitive Flutter dependency — if not already imported in this file, add `import 'package:collection/collection.dart';`.) `_openCommentsFor` should call the same `showModalBottomSheet(... CommentWidget(postId: target.id, ...))` that `NoteCard.openCommentSection` already uses — extract or duplicate that call here, passing `highlightCommentId` through to `CommentWidget` as a new optional constructor parameter (wired up in Task 14).

- [ ] **Step 3: Update `notification_push_router.dart` to pass the data through**

Replace:

```dart
case 'community_comment':
case 'community_heart':
  navigator.push(
    MaterialPageRoute(builder: (context) => const CommunityScreen()),
  );
  return;
```

with:

```dart
case 'community_comment':
case 'community_heart':
case 'comment_reply':
case 'comment_reaction':
  final postId = data?['postId'] as String?;
  final commentId = data?['commentId'] as String?;
  navigator.push(
    MaterialPageRoute(
      builder: (context) => CommunityScreen(
        targetPostId: postId,
        targetCommentId: commentId,
      ),
    ),
  );
  return;
```

(Match whatever the existing local variable name for the notification's data map is in this switch — the survey found `data['postId']` already read for the `streak_milestone` case; reuse that same variable, don't reintroduce a second parse of the payload.)

- [ ] **Step 4: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/authentication/screen/community/community_screen.dart lib/src/services/notification_push_router.dart
git commit -m "feat(community): deep-link comment/reaction/reply notifications to the specific post"
```

---

### Task 14: Scroll to and highlight the target comment

**Files:**
- Modify: `lib/src/models/comments_widget.dart`

**Interfaces:**
- Consumes: reuses the scroll-into-view technique already proven in `leaderboard_screen.dart`'s `_scrollToCurrentUser` (`Scrollable.ensureVisible` + a coarse `animateTo` fallback for not-yet-built rows), generalized from a single `GlobalKey` to a `Map<String, GlobalKey>` keyed by comment id.
- Produces: `CommentWidget({..., this.highlightCommentId})`.

- [ ] **Step 1: Add the parameter and per-comment keys**

```dart
const CommentWidget({
  super.key,
  required this.postId,
  this.onChanged,
  this.highlightCommentId,
  this.fetchCommentsOverride,
  this.addCommentOverride,
});

final String? highlightCommentId;
```

Add state:

```dart
final Map<String, GlobalKey> _commentKeys = {};
String? _pulsingCommentId;

GlobalKey _keyFor(String commentId) => _commentKeys.putIfAbsent(commentId, () => GlobalKey());
```

Wrap each comment row's outermost widget with `KeyedSubtree(key: _keyFor(comment.id), child: <existing row widget>)`.

- [ ] **Step 2: After comments load, if `highlightCommentId` is set, scroll to it and pulse-highlight it**

Add, triggered once `_comments` is first populated (e.g. right after the `setState(() => _comments = ...)` seeding line from Task 4's `FutureBuilder` seeding logic):

```dart
void _scrollToHighlightTargetIfNeeded() {
  final targetId = widget.highlightCommentId;
  if (targetId == null || _comments == null) return;
  final matches = _comments!.any((c) => c.id == targetId);
  if (!matches) return;

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final key = _commentKeys[targetId];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.2,
      );
    }
    if (!mounted) return;
    setState(() => _pulsingCommentId = targetId);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _pulsingCommentId = null);
  });
}
```

Call `_scrollToHighlightTargetIfNeeded();` right after `_comments` is first assigned from the loaded data (both in the `FutureBuilder` seeding branch from Task 4 and, if you kept a separate `initState`/`didUpdateWidget` path, there too — it must fire exactly once per successful load, not on every rebuild, so guard it the same way the `_comments == null` check already guards the seeding assignment).

- [ ] **Step 3: Render the pulse highlight**

Wrap each comment row's background container (whatever `Container`/`Card` currently forms the row's visible background) with an `AnimatedContainer` that reacts to `_pulsingCommentId`:

```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 300),
  color: comment.id == _pulsingCommentId
      ? companyTheme.primaryColor.withValues(alpha: 0.18)
      : Colors.transparent,
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: <existing row content>,
)
```

- [ ] **Step 4: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Manual verification**

Comment on a post from a second test account, tap the resulting push notification on the first account's device, confirm: Community opens → the correct post's comment sheet opens automatically → the list scrolls to the new comment → it briefly highlights.

- [ ] **Step 6: Commit**

```bash
git add lib/src/models/comments_widget.dart
git commit -m "feat(community): scroll to and highlight the comment a notification points at"
```

---

# Part G — @mentions

### Task 15: Backend — mentionable-users search endpoint

**Files:**
- Modify: `backend/app/Http/Controllers/Api/CommunityController.php` (add `mentionableUsers` action)
- Modify: `backend/routes/api.php`
- Test: `backend/tests/Feature/CommunityMentionTest.php` — create (this test file covers Tasks 15 and 16 together)

**Interfaces:**
- Produces: `GET /api/community/mentionable-users?q=<query>` → `{id, name, profilePic}[]`, limited to 10 results, scoped to the requester's company using the exact same OR-scope condition `CommunityController::index` already uses (so mention suggestions only include people who could plausibly see the post).

- [ ] **Step 1: Write the failing test (search half)**

Create `backend/tests/Feature/CommunityMentionTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommunityMentionTest extends TestCase
{
    use RefreshDatabase;

    public function test_search_returns_matching_users_in_the_same_company_only(): void
    {
        $me = User::factory()->create(['company_code' => 'ACME']);
        $sameCompany = User::factory()->create(['company_code' => 'ACME', 'name' => 'Jordan Rivera']);
        $otherCompany = User::factory()->create(['company_code' => 'OTHER', 'name' => 'Jordan Smith']);

        Sanctum::actingAs($me);
        $response = $this->getJson('/api/community/mentionable-users?q=Jordan');

        $response->assertOk();
        $names = collect($response->json())->pluck('name')->all();
        $this->assertContains('Jordan Rivera', $names);
        $this->assertNotContains('Jordan Smith', $names);
    }

    public function test_search_is_capped_at_10_results(): void
    {
        $me = User::factory()->create(['company_code' => 'ACME']);
        User::factory()->count(15)->create(['company_code' => 'ACME', 'name' => 'Test Match User']);

        Sanctum::actingAs($me);
        $response = $this->getJson('/api/community/mentionable-users?q=Test');

        $response->assertOk();
        $this->assertLessThanOrEqual(10, count($response->json()));
    }

    public function test_a_blank_query_returns_an_empty_list_not_the_whole_company(): void
    {
        $me = User::factory()->create(['company_code' => 'ACME']);
        User::factory()->count(3)->create(['company_code' => 'ACME']);

        Sanctum::actingAs($me);
        $response = $this->getJson('/api/community/mentionable-users?q=');

        $response->assertOk();
        $this->assertCount(0, $response->json());
    }
}
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommunityMentionTest`
Expected: FAIL (route doesn't exist — 404s)

- [ ] **Step 3: Read `CommunityController::index`'s company-scope query**

Open `CommunityController.php`, copy the exact OR-scope condition used at the top of `index` (matching on `company_code`/`company_name`, per the survey's lines 23-34) — the new endpoint must scope `User::query()` using the equivalent condition on the `User` model's own company fields (`company_code`, `company_name`, `active_company_code`, `active_company_name`), not the `CommunityPost` fields, since here we're filtering users, not posts.

- [ ] **Step 4: Implement `mentionableUsers`**

```php
public function mentionableUsers(Request $request): JsonResponse
{
    $user = $request->user();
    $query = trim((string) $request->query('q', ''));

    if ($query === '') {
        return response()->json([]);
    }

    $companyCode = $user->active_company_code ?? $user->company_code;
    $companyName = $user->active_company_name ?? $user->company_name;

    $matches = \App\Models\User::query()
        ->where(function ($q) use ($companyCode, $companyName) {
            $q->where('company_code', $companyCode)
                ->orWhere('company_name', $companyName)
                ->orWhere('active_company_code', $companyCode)
                ->orWhere('active_company_name', $companyName);
        })
        ->where('id', '!=', $user->id)
        ->where('name', 'ILIKE', "%{$query}%")
        ->orderBy('name')
        ->limit(10)
        ->get(['id', 'name', 'profile_pic']);

    return response()->json($matches->map(fn ($u) => [
        'id' => (string) $u->id,
        'name' => $u->name,
        'profilePic' => $u->profile_pic,
    ])->values());
}
```

- [ ] **Step 5: Register the route**

```php
Route::get('/community/mentionable-users', [CommunityController::class, 'mentionableUsers']);
```

Place it in `routes/api.php` near the other `/community/...` routes, **before** the `/community/posts/{post}` parameterized routes if Laravel's route-matching order in this file would otherwise let `{post}` swallow the literal `mentionable-users` segment (check the existing route file for how `/community/posts/{post}` vs any other literal `/community/...` route is already ordered, and follow the same placement rule to avoid a routing collision).

- [ ] **Step 6: Run the test to verify the search portion passes**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommunityMentionTest`
Expected: the 3 search tests PASS (mention-storage tests from Task 16 aren't written yet).

- [ ] **Step 7: Commit**

```bash
git add backend/app/Http/Controllers/Api/CommunityController.php backend/routes/api.php backend/tests/Feature/CommunityMentionTest.php
git commit -m "feat(community): add company-scoped mentionable-users search endpoint"
```

---

### Task 16: Backend — store mentions and notify mentioned users

**Files:**
- Create: `backend/database/migrations/2026_08_04_000003_add_mentions_to_posts_and_comments.php`
- Modify: `backend/app/Models/CommunityPost.php`
- Modify: `backend/app/Models/NoteComment.php`
- Modify: `backend/app/Http/Controllers/Api/CommunityController.php` (`store`, `mapPost`)
- Modify: `backend/app/Http/Controllers/Api/CommentController.php` (`store`, `mapComment`)
- Modify: `backend/tests/Feature/CommunityMentionTest.php` (add mention-storage tests)

**Interfaces:**
- Produces: `community_posts.mentions` and `note_comments.mentions` — JSON columns, array-cast, shape `[{"userId": "123", "name": "Jordan Rivera"}, ...]`. `POST /community/posts` and `POST .../comments` both accept an optional `mentions` array in that same shape (the client already knows exactly who it mentioned, from Task 15's search results — no server-side text parsing needed). Both `mapPost`/`mapComment` responses gain a `mentions` key with that same shape.

**Design decision:** mentions are stored as an explicit array the *client* supplies (from what the user actually picked in the autocomplete dropdown), not parsed server-side from `@username` text. This avoids all ambiguity from duplicate/changed display names and matches how `note`/`data` JSON columns already work in this codebase (client-constructed structured payloads, not text-mined). The server's only job is to validate every mentioned `userId` is real and in the same company (so a client can't use this to spam-notify or fingerprint arbitrary users), then fan out notifications.

- [ ] **Step 1: Write the migration**

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('community_posts', function (Blueprint $table) {
            $table->json('mentions')->nullable()->after('note');
        });
        Schema::table('note_comments', function (Blueprint $table) {
            $table->json('mentions')->nullable()->after('comment');
        });
    }

    public function down(): void
    {
        Schema::table('community_posts', function (Blueprint $table) {
            $table->dropColumn('mentions');
        });
        Schema::table('note_comments', function (Blueprint $table) {
            $table->dropColumn('mentions');
        });
    }
};
```

- [ ] **Step 2: Add casts and fillable**

In `CommunityPost.php`, add `'mentions'` to `$fillable` and to `casts()`: `'mentions' => 'array',`.
In `NoteComment.php`, add `'mentions'` to `$fillable` and add a `casts()` method (it currently has none): `protected function casts(): array { return ['mentions' => 'array']; }`.

- [ ] **Step 3: Add the mention-storage tests to `CommunityMentionTest`**

Append to the same test class from Task 15:

```php
public function test_mentioning_a_user_in_a_post_stores_the_mention_and_notifies_them(): void
{
    $author = User::factory()->create(['company_code' => 'ACME']);
    $mentioned = User::factory()->create(['company_code' => 'ACME', 'name' => 'Jordan Rivera']);

    Sanctum::actingAs($author);
    $response = $this->postJson('/api/community/posts', [
        'title' => 'Test post',
        'category' => 'General',
        'note' => [['type' => 'text', 'value' => 'hey @Jordan Rivera check this out']],
        'color' => 0xFFFFFFFF,
        'mentions' => [['userId' => (string) $mentioned->id, 'name' => 'Jordan Rivera']],
    ]);

    $response->assertOk()->assertJsonPath('mentions.0.userId', (string) $mentioned->id);
    $this->assertDatabaseHas('notifications', [
        'user_id' => (string) $mentioned->id,
        'type' => 'community_mention',
    ]);
}

public function test_mentioning_a_user_outside_the_company_is_rejected(): void
{
    $author = User::factory()->create(['company_code' => 'ACME']);
    $outsider = User::factory()->create(['company_code' => 'OTHER']);

    Sanctum::actingAs($author);
    $response = $this->postJson('/api/community/posts', [
        'title' => 'Test post',
        'category' => 'General',
        'note' => [['type' => 'text', 'value' => 'hey there']],
        'color' => 0xFFFFFFFF,
        'mentions' => [['userId' => (string) $outsider->id, 'name' => 'Outsider']],
    ]);

    $response->assertStatus(422);
}

public function test_mentioning_yourself_does_not_notify_you(): void
{
    $author = User::factory()->create(['company_code' => 'ACME']);

    Sanctum::actingAs($author);
    $this->postJson('/api/community/posts', [
        'title' => 'Test post',
        'category' => 'General',
        'note' => [['type' => 'text', 'value' => 'talking to myself']],
        'color' => 0xFFFFFFFF,
        'mentions' => [['userId' => (string) $author->id, 'name' => $author->name]],
    ])->assertOk();

    $this->assertDatabaseMissing('notifications', [
        'user_id' => (string) $author->id,
        'type' => 'community_mention',
    ]);
}

public function test_mentioning_a_user_in_a_comment_stores_the_mention_and_notifies_them(): void
{
    $postOwner = User::factory()->create(['company_code' => 'ACME']);
    $commenter = User::factory()->create(['company_code' => 'ACME']);
    $mentioned = User::factory()->create(['company_code' => 'ACME', 'name' => 'Jordan Rivera']);
    $post = CommunityPost::create([
        'user_id' => $postOwner->id, 'username' => $postOwner->name, 'title' => 'Test',
        'note' => [['type' => 'text', 'value' => 'x']], 'color' => 0xFFFFFFFF,
        'category' => 'General', 'saved' => false,
    ]);

    Sanctum::actingAs($commenter);
    $response = $this->postJson("/api/community/posts/{$post->id}/comments", [
        'comment' => 'hey @Jordan Rivera look',
        'mentions' => [['userId' => (string) $mentioned->id, 'name' => 'Jordan Rivera']],
    ]);

    $response->assertOk()->assertJsonPath('mentions.0.userId', (string) $mentioned->id);
    $this->assertDatabaseHas('notifications', [
        'user_id' => (string) $mentioned->id,
        'type' => 'community_mention',
    ]);
}
```

- [ ] **Step 4: Run to confirm the new tests fail**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommunityMentionTest`
Expected: the 4 new tests FAIL, the 3 search tests from Task 15 still PASS.

- [ ] **Step 5: Add mention validation + storage + notification fan-out helper**

Add a private helper to both `CommunityController` and `CommentController` (duplicate this small method in both — it's short and each controller's `User $user`/company-scope context differs slightly; do not over-abstract into a shared trait for a 15-line method per YAGNI):

```php
private function validateAndFilterMentions(?array $mentions, User $author): array
{
    if (empty($mentions)) {
        return [];
    }

    $companyCode = $author->active_company_code ?? $author->company_code;
    $companyName = $author->active_company_name ?? $author->company_name;

    $validIds = \App\Models\User::query()
        ->whereIn('id', collect($mentions)->pluck('userId'))
        ->where(function ($q) use ($companyCode, $companyName) {
            $q->where('company_code', $companyCode)
                ->orWhere('company_name', $companyName)
                ->orWhere('active_company_code', $companyCode)
                ->orWhere('active_company_name', $companyName);
        })
        ->pluck('id')
        ->map(fn ($id) => (string) $id)
        ->all();

    $filtered = collect($mentions)
        ->filter(fn ($m) => in_array((string) ($m['userId'] ?? ''), $validIds, true))
        ->values()
        ->all();

    if (count($filtered) !== count($mentions)) {
        abort(422, 'One or more mentioned users could not be found in your company.');
    }

    return $filtered;
}
```

Add `use App\Models\User;` to both controllers if not already imported.

- [ ] **Step 6: Wire into `CommunityController::store`**

Add `'mentions' => ['sometimes', 'nullable', 'array'], 'mentions.*.userId' => ['required_with:mentions', 'string'], 'mentions.*.name' => ['required_with:mentions', 'string']` to the validation rules. After validation, before creating the post:

```php
$mentions = $this->validateAndFilterMentions($validated['mentions'] ?? null, $user);
```

Add `'mentions' => $mentions,` to the `CommunityPost::create([...])` array. After the post is created, fan out notifications:

```php
foreach ($mentions as $mention) {
    if ((string) $mention['userId'] === (string) $user->id) {
        continue;
    }
    Notification::createFor(
        (string) $mention['userId'],
        'community_mention',
        sprintf('%s mentioned you in a post', $user->name),
        null,
        ['postId' => (string) $post->id, 'mentionedByUserId' => (string) $user->id],
    );
}
```

Add `'mentions' => $post->mentions ?? [],` to `mapPost`.

- [ ] **Step 7: Wire into `CommentController::store`** (same shape)

Same validation rules addition, same `validateAndFilterMentions` call, `'mentions' => $mentions,` in `NoteComment::create([...])`, and after creation:

```php
foreach ($mentions as $mention) {
    if ((string) $mention['userId'] === (string) $user->id) {
        continue;
    }
    Notification::createFor(
        (string) $mention['userId'],
        'community_mention',
        sprintf('%s mentioned you in a comment', $user->name),
        Str::limit(trim((string) $validated['comment']), 80),
        ['postId' => (string) $post->id, 'commentId' => (string) $comment->id, 'mentionedByUserId' => (string) $user->id],
    );
}
```

Add `'mentions' => $comment->mentions ?? [],` to `mapComment`.

- [ ] **Step 8: Run the full test file**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=CommunityMentionTest`
Expected: all 7 tests PASS.

- [ ] **Step 9: Run the full backend suite**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml`
Expected: all tests pass, no regressions in `CommunityPostHeartTest`/`CommentAvatarTest`/`CommentReactionTest`/`CommentReplyTest`.

- [ ] **Step 10: Commit**

```bash
git add backend/database/migrations/2026_08_04_000003_add_mentions_to_posts_and_comments.php \
  backend/app/Models/CommunityPost.php backend/app/Models/NoteComment.php \
  backend/app/Http/Controllers/Api/CommunityController.php backend/app/Http/Controllers/Api/CommentController.php \
  backend/tests/Feature/CommunityMentionTest.php
git commit -m "feat(community): store @mentions and notify mentioned users, scoped to the same company"
```

---

### Task 17: Frontend — mention search service + autocomplete widget

**Files:**
- Create: `lib/src/services/mention_api_service.dart`
- Create: `lib/src/widgets/mention_text_field.dart`
- Test: `test/unit/mention_text_field_test.dart` — create

**Interfaces:**
- Produces: `MentionApiService.instance.search(String query)` → `Future<List<MentionCandidate>>` where `MentionCandidate{id, name, profilePic}`. `MentionTextField` — a drop-in replacement for a multi-line `TextField` that shows a suggestion overlay when the user types `@`, and exposes `List<MentionCandidate> get selectedMentions` plus a `TextEditingController`-compatible way to read the final text (reuse the caller's own `TextEditingController` via a required `controller` parameter, matching how `notes_type.dart`/`comments_widget.dart` already manage their text controllers — do not have this widget own its own controller).

- [ ] **Step 1: Create `MentionApiService`**

```dart
import 'package:selfcare_projects/src/services/api_client.dart';
import 'package:selfcare_projects/src/services/auth_service.dart';

class MentionCandidate {
  const MentionCandidate({required this.id, required this.name, this.profilePic});

  factory MentionCandidate.fromJson(Map<String, dynamic> json) {
    return MentionCandidate(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      profilePic: json['profilePic'] as String?,
    );
  }

  final String id;
  final String name;
  final String? profilePic;
}

class MentionApiService {
  MentionApiService._();

  static final MentionApiService instance = MentionApiService._();
  final ApiClient _api = ApiClient.instance;

  Future<List<MentionCandidate>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final session = AuthService.instance.currentSession;
    if (session == null) return const [];

    final response = await _api.getJson(
      '/api/community/mentionable-users?q=${Uri.encodeQueryComponent(trimmed)}',
      token: session.token,
    );
    final list = response['data'] ?? response;
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MentionCandidate.fromJson)
        .toList();
  }
}
```

(Note: `ApiClient.getJson` returns `Future<Map<String, dynamic>>` per its existing signature, but this endpoint's Laravel response is a bare JSON array (`response()->json($matches->map(...))`), not a `{...}` object — check `ApiClient._decodeResponse`'s handling of a top-level JSON array response (the survey noted `_decodeResponse` wraps non-`Map` decoded JSON as `{'data': data}` — confirm this by reading `api_client.dart`'s `_decodeResponse` method before writing this, since if that wrapping is already in place, `response['data']` is exactly correct and the `response['data'] ?? response` fallback above handles both cases safely either way).

- [ ] **Step 2: Write the failing widget test for `MentionTextField`**

Create `test/unit/mention_text_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/mention_api_service.dart';
import 'package:selfcare_projects/src/widgets/mention_text_field.dart';

void main() {
  testWidgets('typing @ followed by text shows matching suggestions', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MentionTextField(
            controller: controller,
            searchOverride: (query) async => [
              const MentionCandidate(id: '1', name: 'Jordan Rivera'),
              const MentionCandidate(id: '2', name: 'Jordan Lee'),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hey @Jor');
    await tester.pumpAndSettle();

    expect(find.text('Jordan Rivera'), findsOneWidget);
    expect(find.text('Jordan Lee'), findsOneWidget);
  });

  testWidgets('selecting a suggestion inserts the name and records the mention', (tester) async {
    final controller = TextEditingController();
    final key = GlobalKey<MentionTextFieldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MentionTextField(
            key: key,
            controller: controller,
            searchOverride: (query) async => [const MentionCandidate(id: '1', name: 'Jordan Rivera')],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hey @Jor');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jordan Rivera'));
    await tester.pumpAndSettle();

    expect(controller.text, 'hey @Jordan Rivera ');
    expect(key.currentState!.selectedMentions.length, 1);
    expect(key.currentState!.selectedMentions.first.id, '1');
  });
}
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `flutter test test/unit/mention_text_field_test.dart`
Expected: FAIL (`lib/src/widgets/mention_text_field.dart` doesn't exist)

- [ ] **Step 4: Implement `MentionTextField`**

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/mention_api_service.dart';

class MentionTextField extends StatefulWidget {
  const MentionTextField({
    super.key,
    required this.controller,
    this.decoration,
    this.maxLines = 5,
    this.searchOverride,
  });

  final TextEditingController controller;
  final InputDecoration? decoration;
  final int? maxLines;
  final Future<List<MentionCandidate>> Function(String query)? searchOverride;

  @override
  State<MentionTextField> createState() => MentionTextFieldState();
}

class MentionTextFieldState extends State<MentionTextField> {
  final List<MentionCandidate> _selectedMentions = [];
  List<MentionCandidate> _suggestions = [];
  Timer? _debounce;
  int? _mentionStartIndex;

  List<MentionCandidate> get selectedMentions => List.unmodifiable(_selectedMentions);

  Future<List<MentionCandidate>> _search(String query) {
    return widget.searchOverride?.call(query) ?? MentionApiService.instance.search(query);
  }

  void _onChanged(String text) {
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0) return;

    final upToCursor = text.substring(0, cursor);
    final atIndex = upToCursor.lastIndexOf('@');
    if (atIndex == -1 || (atIndex > 0 && !RegExp(r'\s').hasMatch(upToCursor[atIndex - 1]) && atIndex != 0)) {
      setState(() {
        _mentionStartIndex = null;
        _suggestions = [];
      });
      return;
    }

    final query = upToCursor.substring(atIndex + 1);
    if (query.contains(' ') || query.isEmpty) {
      setState(() {
        _mentionStartIndex = null;
        _suggestions = [];
      });
      return;
    }

    _mentionStartIndex = atIndex;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
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
      selection: TextSelection.collapsed(offset: before.length + candidate.name.length + 2),
    );
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
          maxLines: widget.maxLines,
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/unit/mention_text_field_test.dart`
Expected: PASS

- [ ] **Step 6: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/src/services/mention_api_service.dart lib/src/widgets/mention_text_field.dart test/unit/mention_text_field_test.dart
git commit -m "feat(community): add @mention search service and autocomplete text field widget"
```

---

### Task 18: Frontend — wire mentions into post/comment/reply composers, render highlighted + tappable mentions

**Files:**
- Modify: `lib/src/features/authentication/screen/notes/notes_type.dart` (use `MentionTextField` for the post body input, send `mentions` on create)
- Modify: `lib/src/models/comments_widget.dart` (use `MentionTextField` for comment/reply input, send `mentions`, render highlighted mentions in comment/reply text)
- Modify: `lib/src/models/note_card.dart` (render highlighted mentions in post body text)
- Modify: `lib/src/services/community_api_service.dart` (`Note`/`createPost` gains `mentions`)
- Modify: `lib/src/services/comments_api_service.dart` (`addComment` gains `mentions` param, `CommunityComment` gains `mentions` field)
- Modify: `lib/src/widgets/linkified_text.dart` (extend to also highlight `@name` mentions and make them tappable, alongside URLs)

**Interfaces:**
- Consumes: `MentionTextField` (Task 17), `mentions` field/param on post & comment create (Task 16).

- [ ] **Step 1: Extend `LinkifiedText`/`buildLinkifiedSpans` to also highlight mentions**

Add an optional `mentions` parameter so the same widget handles both URL and @mention highlighting in one pass (they're both "find substrings, make them tappable" — sharing the span-builder avoids maintaining two overlapping regex/span-walking implementations):

```dart
List<InlineSpan> buildLinkifiedSpans(
  String text, {
  required TextStyle baseStyle,
  required TextStyle linkStyle,
  required void Function(String url) onTap,
  List<MentionSpanTarget> mentions = const [],
  TextStyle? mentionStyle,
  void Function(String userId)? onMentionTap,
}) {
  // existing URL-matching logic finds `matches` for URLs; additionally,
  // for each entry in `mentions`, find `'@' + entry.name` as a literal
  // substring (case-sensitive exact match against what was actually
  // inserted at mention-selection time) and add it to the same sorted
  // match list, tagged with its type (url vs mention) so the final
  // span-building loop applies `linkStyle`+onTap or `mentionStyle`+onMentionTap
  // accordingly. Merge-sort both match lists by start offset before
  // walking the text once, the same way the URL-only version does today.
}

class MentionSpanTarget {
  const MentionSpanTarget({required this.userId, required this.name});
  final String userId;
  final String name;
}
```

Implement the merge precisely: build two lists of `(start, end, type, payload)` — one from `_urlPattern.allMatches(text)`, one from scanning `text` for each `'@${m.name}'` literal occurrence (use `text.indexOf('@${m.name}')`, and if a name could appear more than once, find all occurrences via a loop advancing past each found index) — concatenate, sort by `start`, then drop any mention match that overlaps a URL match's range (URLs win on overlap, which in practice won't happen since `@Name` and `https://...` can't overlap), then walk the merged, sorted list exactly like the existing single-pass loop does, choosing `linkStyle`/`onTap` for URL entries and `mentionStyle ?? linkStyle`/`onMentionTap` for mention entries.

Update `LinkifiedText`'s widget-level constructor to accept and thread through `mentions`, `mentionStyle`, `onMentionTap`.

- [ ] **Step 2: Add a `MemberProfileSheet` for "tap a mention → view profile"**

No general-purpose "view another user's profile" screen was found elsewhere in the app to reuse, so add a minimal, self-contained bottom sheet — consistent with how this module already surfaces secondary info (`LeaderboardScoreBreakdownSheet`, `LeaderboardInfoSheet`) — rather than a full navigable screen, since that keeps this task independent of unrelated navigation/routing decisions.

Create the sheet inline in `comments_widget.dart` and `note_card.dart` (or factor into a small shared file `lib/src/widgets/member_profile_sheet.dart` if both need it — prefer the shared file to avoid duplicating the same ~30 lines twice):

```dart
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/services/mention_api_service.dart';

void showMemberProfileSheet(BuildContext context, {required String userId, required String name, String? profilePic}) {
  showModalBottomSheet(
    context: context,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundImage: (profilePic?.isNotEmpty ?? false) ? NetworkImage(profilePic!) : null,
            child: (profilePic?.isNotEmpty ?? false) ? null : const Icon(Icons.person, size: 36),
          ),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    ),
  );
}
```

Since neither the post nor comment payload currently carries the mentioned user's `profilePic` back (only `{userId, name}` per Task 16's stored shape), call this with `profilePic: null` for now — the fallback icon renders correctly. (Enriching this with a live profile picture would require either an extra per-user lookup call or extending the `mentions` JSON shape to include `profilePic`, either of which is a reasonable small follow-up but is out of scope here since the acceptance criteria only requires opening *a* profile view, not a fully-featured one.)

- [ ] **Step 3: Wire into post creation (`notes_type.dart`)**

Replace the post-body `TextField` (wherever the "Learning"/note text is composed — check whether this screen already uses a single free-text body field vs. a structured `note` list; wire `MentionTextField` in for whichever field is the free-text body) with `MentionTextField`, keep a `GlobalKey<MentionTextFieldState>` to read `.selectedMentions` at submit time, and pass them into `createPost`:

```dart
final mentions = _mentionFieldKey.currentState?.selectedMentions ?? const [];
await CommunityApiService.instance.createPost(
  // ...existing arguments unchanged...
  mentions: mentions.map((m) => {'userId': m.id, 'name': m.name}).toList(),
);
```

Add the `mentions` parameter to `CommunityApiService.createPost`:

```dart
Future<Note> createPost({
  required String title,
  required String category,
  required List<Map<String, String>> note,
  required int color,
  bool saved = false,
  List<Map<String, String>> mentions = const [],
}) async {
  final response = await _api.postJson(
    '/api/community/posts',
    {
      'title': title,
      'category': category,
      'note': note,
      'color': color,
      'saved': saved,
      if (mentions.isNotEmpty) 'mentions': mentions,
    },
    token: _token,
  );
  // ...existing response parsing, unchanged...
}
```

- [ ] **Step 4: Wire into comment/reply composition (`comments_widget.dart`)**

Replace the comment-input `TextField` with `MentionTextField` (keyed the same way), and update the `addComment`/`_toggleReaction`-adjacent submit flow to pass `mentions` through to `_api.addComment(..., mentions: ...)`, matching the pattern in Step 3. Update `CommentsApiService.addComment` to accept and send `mentions` the same way `createPost` does.

- [ ] **Step 5: Render highlighted, tappable mentions in post bodies and comments**

In `note_card.dart`, update the `LinkifiedText` call from Task 6 to also pass mentions:

```dart
LinkifiedText(
  textContent,
  style: const TextStyle(fontSize: 16, color: Color.fromARGB(221, 19, 19, 19), height: 1.5),
  mentions: widget.note.mentions
      .map((m) => MentionSpanTarget(userId: m['userId']!, name: m['name']!))
      .toList(),
  mentionStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
  onMentionTap: (userId) {
    final m = widget.note.mentions.firstWhere((m) => m['userId'] == userId);
    showMemberProfileSheet(context, userId: userId, name: m['name']!);
  },
)
```

This requires `Note` (in `note_model.dart`) to gain a `mentions` field (`List<Map<String, String>>`, default `const []`, parsed from the post JSON's `mentions` key) — add it alongside `Note`'s other fields, following whatever parsing convention the rest of that class already uses.

Apply the identical change to `comments_widget.dart`'s `LinkifiedText` call from Task 6, using `comment.mentions` (add `final List<Map<String, String>> mentions;` to `CommunityComment`, parsed from the comment JSON's `mentions` key, default `const []`).

- [ ] **Step 6: Run the analyzer and full test suite**

Run: `flutter analyze && flutter test`
Expected: `No issues found!`, all tests pass.

- [ ] **Step 7: Manual verification**

Compose a post, type `@` and a name, select a suggestion, confirm the name is inserted. Post it. Confirm the mentioned user receives a push notification. View the post, confirm the mention renders bold/colored. Tap it, confirm the profile sheet opens with the right name. Repeat for a comment and a reply.

- [ ] **Step 8: Commit**

```bash
git add lib/src/features/authentication/screen/notes/notes_type.dart lib/src/models/comments_widget.dart \
  lib/src/models/note_card.dart lib/src/services/community_api_service.dart \
  lib/src/services/comments_api_service.dart lib/src/widgets/linkified_text.dart \
  lib/src/widgets/member_profile_sheet.dart lib/src/models/note_model.dart
git commit -m "feat(community): wire @mentions into post/comment/reply composers with highlighted, tappable rendering"
```

---

## Final Verification (run after all parts are merged)

- [ ] Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml` — all backend tests pass.
- [ ] Run: `flutter analyze` — `No issues found!`
- [ ] Run: `flutter test` — all tests pass, including every new file added above.
- [ ] Manual pass on both an iOS simulator and an Android emulator covering every acceptance-criteria bullet from the original spec: post a Learning (no black screen), tap a link in a post, hit the title limit, comment and see it appear instantly, tap a comment notification and land on the highlighted comment, see avatars, reply to a comment, react to a comment, mention a user end-to-end (autocomplete → notification → tap-to-profile).

---

## Self-Review Notes

- **Spec coverage:** all 9 numbered spec items map to tasks — #1→Tasks 1-2, #2→Tasks 5-6, #3→Task 3, #4→Task 4, #5→Tasks 13-14, #6→Tasks 7-8, #7→Tasks 11-12, #8→Tasks 9-10, #9→Tasks 15-18.
- **Placeholder scan:** no "TBD"/"handle appropriately" phrasing left in any step; the few spots that say "match the existing X convention" are paired with an explicit instruction to read the current file first (Task 2 Step 1, Task 12 Step 1) rather than guessing — these are read-then-apply instructions, not placeholders, since the target shape is fully specified.
- **Type/name consistency:** `CommunityComment` field additions (`profilePic`, `reactionsCount`, `reactedByMe`, `parentId`, `mentions`) are introduced once each (Tasks 8, 10, 12, 18) and referenced identically in every later task; `CommentReactionState`/`MentionCandidate`/`MentionSpanTarget` are each defined exactly once (Tasks 10, 17, 18) before use.
