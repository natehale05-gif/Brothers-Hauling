/// A driver on the board.
///
/// [appOpen] is the whole tracking story: position only reports while someone
/// has the app in front of them. When it goes false, dispatch keeps
/// [lastSeen]/[lastPlace] so nobody is simply "gone".
class CrewMember {
  const CrewMember({
    required this.id,
    required this.name,
    required this.initials,
    required this.unit,
    required this.onShift,
    required this.appOpen,
    required this.rig,
    this.lastSeen,
    this.lastPlace,
  });

  final String id;
  final String name;
  final String initials;
  final String unit;
  final bool onShift;
  final bool appOpen;

  /// Trailers/decks this driver is checked out on. A job whose equipment is not
  /// in this list cannot be volunteered for.
  final List<String> rig;

  final String? lastSeen;
  final String? lastPlace;

  /// Equipment strings are compared with whitespace stripped so
  /// "Dump trailer 14k" and "Dump trailer14k" are the same rig.
  bool canRun(String equipment) {
    String squash(String s) => s.replaceAll(RegExp(r'\s'), '');
    return rig.any((r) => squash(r) == squash(equipment));
  }
}
