/// Whether a company (by its InnerU `code`/`name` fields) is the Abundance
/// company this Quests redesign is scoped to. This is the single source of
/// truth for that check — see the design spec's "Existing gating bug"
/// section for why three separate ad hoc heuristics used to answer this
/// question differently.
class AbundanceCompany {
  const AbundanceCompany._();

  static bool matches(String? code, String? name) {
    final normalizedCode = (code ?? '').trim().toUpperCase();
    final normalizedName = (name ?? '').trim().toUpperCase();
    return normalizedCode == 'ABU15DN' || normalizedName == 'ABUNDANCE';
  }
}
