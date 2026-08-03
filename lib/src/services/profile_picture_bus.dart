import 'package:flutter/foundation.dart';

/// Broadcasts the signed-in user's profile picture URL the instant a new
/// photo finishes uploading.
///
/// Before this existed, each screen that shows the avatar (Dashboard,
/// Profile, ...) only refreshed it from its own initState or from
/// RouteObserver's didPopNext -- which depends on the exact push/pop shape
/// of the navigation stack at the moment of the edit. Editing from Profile
/// Settings pushes Edit Profile a couple of routes deep, and saving there
/// replaces that route with a fresh Profile page (so Profile itself updates
/// immediately) without ever popping back down to Dashboard, so Dashboard's
/// own cached avatar was left stale until something else forced it to
/// rebuild -- in practice, only a full app restart. Publishing here lets any
/// listening screen update itself the moment the upload succeeds, with no
/// dependency on which screens happen to be above it in the stack.
class ProfilePictureBus {
  ProfilePictureBus._();

  static final ValueNotifier<String?> latestUrl = ValueNotifier<String?>(null);

  static void publish(String? url) {
    final cleaned = url?.trim();
    latestUrl.value = (cleaned == null || cleaned.isEmpty) ? null : cleaned;
  }
}
