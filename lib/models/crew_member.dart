import 'role.dart';

/// The initials shown on an avatar, worked out from a name.
///
/// One-word names get two letters from the single word rather than one, so a
/// crew of "Dave" and "Danny" do not both come out as "D".
String initialsFor(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final only = words.single;
    return (only.length == 1 ? only : only.substring(0, 2)).toUpperCase();
  }
  return (words.first[0] + words.last[0]).toUpperCase();
}

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
    this.role = Role.employee,
    this.lastSeen,
    this.lastPlace,
  });

  final String id;
  final String name;
  final String initials;
  final String unit;
  final bool onShift;
  final bool appOpen;

  /// What this person is allowed to see and do.
  ///
  /// Defaults to employee, which is the safe direction to be wrong in: a record
  /// written before this field existed comes back as a driver rather than
  /// silently as an owner.
  final Role role;

  /// Trailers/decks this driver is checked out on. A job whose equipment is not
  /// in this list cannot be volunteered for.
  final List<String> rig;

  final String? lastSeen;
  final String? lastPlace;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'initials': initials,
    'unit': unit,
    'onShift': onShift,
    'appOpen': appOpen,
    'rig': rig,
    'role': role.name,
    'lastSeen': lastSeen,
    'lastPlace': lastPlace,
  };

  factory CrewMember.fromJson(Map<String, Object?> json) => CrewMember(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    initials: json['initials'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    onShift: json['onShift'] as bool? ?? false,
    appOpen: json['appOpen'] as bool? ?? false,
    rig: (json['rig'] as List?)?.cast<String>() ?? const [],
    role: Role.values.firstWhere(
      (r) => r.name == json['role'],
      // Absent or unrecognised reads as employee. Guessing upwards would hand
      // someone the money screens on the strength of a typo.
      orElse: () => Role.employee,
    ),
    lastSeen: json['lastSeen'] as String?,
    lastPlace: json['lastPlace'] as String?,
  );

  /// Equipment strings are compared with whitespace stripped so
  /// "Dump trailer 14k" and "Dump trailer14k" are the same rig.
  bool canRun(String equipment) {
    String squash(String s) => s.replaceAll(RegExp(r'\s'), '');
    return rig.any((r) => squash(r) == squash(equipment));
  }
}
