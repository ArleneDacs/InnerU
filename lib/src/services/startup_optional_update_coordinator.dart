import 'package:selfcare_projects/src/services/app_update_service.dart';

/// One-shot state for an optional update discovered during startup.
///
/// The update check may finish while the splash is being replaced and the
/// root can rebuild several times as the local session stream settles. This
/// deliberately keeps the update result independent of either screen so only
/// one optional dialog is ever scheduled for a process launch.
class StartupOptionalUpdateCoordinator {
  AppUpdateCheckResult? _pending;
  bool _hasShown = false;

  bool get hasPending => _pending != null;
  bool get hasShown => _hasShown;

  /// Returns true only when [result] became this launch's first prompt.
  bool queue(AppUpdateCheckResult result) {
    if (!result.isOptional ||
        result.storeUrl == null ||
        _hasShown ||
        _pending != null) {
      return false;
    }

    _pending = result;
    return true;
  }

  /// Atomically consumes the pending prompt. It is marked shown before the
  /// dialog route opens so a rebuild cannot stack another copy above it.
  AppUpdateCheckResult? consume() {
    if (_hasShown || _pending == null) return null;
    final result = _pending!;
    _pending = null;
    _hasShown = true;
    return result;
  }
}
