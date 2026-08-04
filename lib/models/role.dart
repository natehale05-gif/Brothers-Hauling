/// The three access levels. Everything the app shows or hides keys off this.
enum Role {
  admin('Admin', 'Everything — live crew tracking, money, every job.'),
  manager(
    'Manager',
    "Job pay, who's staffed where, plus the full employee view.",
  ),
  employee('Employee', 'The board, job details, and before / after photos.');

  const Role(this.label, this.blurb);

  final String label;
  final String blurb;

  /// Managers and admins see what a job bills at; employees see their cut.
  bool get seesMoney => this != Role.employee;

  /// Which access levels this one is allowed to hire.
  ///
  /// A manager can staff their own crew but cannot mint another manager, and
  /// nobody but an owner can make an owner — otherwise "add crew" is a
  /// privilege escalation with a friendly form on top of it.
  List<Role> get canHire => switch (this) {
    Role.admin => const [Role.employee, Role.manager, Role.admin],
    Role.manager => const [Role.employee],
    Role.employee => const [],
  };

  bool canHireRole(Role other) => canHire.contains(other);
}
