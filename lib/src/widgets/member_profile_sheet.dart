import 'package:flutter/material.dart';

/// A minimal "view member profile" bottom sheet, opened when a rendered
/// `@Name` mention (see [buildLinkifiedSpans] in linkified_text.dart) is
/// tapped in a post or comment. No general-purpose "view another user's
/// profile" screen exists elsewhere in the app to reuse, so this is a
/// small, self-contained sheet -- consistent with how this module already
/// surfaces secondary info (LeaderboardScoreBreakdownSheet,
/// LeaderboardInfoSheet in leaderboard_screen.dart) -- rather than a full
/// navigable screen.
///
/// Neither a post's nor a comment's stored `mentions` payload carries the
/// mentioned user's profile picture back (only `{userId, name}`, per the
/// backend's stored shape), so [profilePic] is nearly always null today and
/// the fallback person icon renders instead.
void showMemberProfileSheet(
  BuildContext context, {
  required String userId,
  required String name,
  String? profilePic,
}) {
  showModalBottomSheet(
    context: context,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundImage: (profilePic?.isNotEmpty ?? false)
                ? NetworkImage(profilePic!)
                : null,
            child: (profilePic?.isNotEmpty ?? false)
                ? null
                : const Icon(Icons.person, size: 36),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  );
}
