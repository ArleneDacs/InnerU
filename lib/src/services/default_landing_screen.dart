/// The user-selectable destination shown after InnerU restores a session.
///
/// Persist the stable [storageValue] rather than a tab index: normal and
/// Abundance companies expose different shells, so a semantic destination can
/// be mapped safely for each shell and unknown/unsupported values always fall
/// back to Dashboard.
enum DefaultLandingScreen {
  dashboard('dashboard', 'Dashboard', 2, 0),
  meditation('meditation', 'Meditation', 0, null),
  steps('steps', 'Step Tracker', 1, null),
  goals('goals', 'Goals', 3, 1),
  community('community', 'Community', 4, null);

  const DefaultLandingScreen(
    this.storageValue,
    this.label,
    this.standardSetupIndex,
    this.abundanceShellIndex,
  );

  /// Value stored by the API/database and in the persisted app session.
  final String storageValue;

  /// Label used by the Account Settings selector on the standard shell.
  final String label;

  /// Tab index in the standard and coach setup shells.
  final int standardSetupIndex;

  /// Matching tab in the Abundance shell, or null when that destination is
  /// not available there.
  final int? abundanceShellIndex;

  static DefaultLandingScreen fromStorageValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    for (final screen in values) {
      if (screen.storageValue == normalized) return screen;
    }
    return DefaultLandingScreen.dashboard;
  }

  /// Converts existing deep-link setup tab indexes into a semantic screen
  /// before a company-specific shell maps it to its own tabs.
  static DefaultLandingScreen fromStandardSetupIndex(int index) {
    for (final screen in values) {
      if (screen.standardSetupIndex == index) return screen;
    }
    return DefaultLandingScreen.dashboard;
  }

  /// The options that can be selected for the active company shell.
  static List<DefaultLandingScreen> availableFor({
    required bool isAbundance,
  }) {
    if (!isAbundance) return values;
    return values
        .where((screen) => screen.abundanceShellIndex != null)
        .toList(growable: false);
  }

  /// Resolves an unavailable Abundance choice to its Home/Dashboard tab.
  int get safeAbundanceShellIndex =>
      abundanceShellIndex ??
      DefaultLandingScreen.dashboard.abundanceShellIndex!;

  String labelFor({required bool isAbundance}) {
    if (isAbundance && this == DefaultLandingScreen.dashboard) {
      return 'Home';
    }
    if (isAbundance && this == DefaultLandingScreen.goals) {
      return 'Quests';
    }
    return label;
  }
}
