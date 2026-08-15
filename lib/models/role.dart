/// The three access levels. Everything the app shows or hides keys off this.
///
/// The shape follows the way the logins are handed out. There is one owner
/// account; every driver gets their own, because their name is on the job, the
/// hours and the map; and the rest of the crew share a single login, which is
/// why an employee is never the person a job is assigned to.
enum Role {
  admin('Admin', 'Everything — the crew, the money, every job.'),
  driver(
    'Driver',
    'Their own login: the work with their name on it, what it is '
        'owed, and where everyone else is.',
  ),
  employee(
    'Employee',
    'The shared login: the board, job details, and before / after photos.',
  );

  const Role(this.label, this.blurb);

  final String label;
  final String blurb;

  /// Whether jobs are put on this person by name.
  ///
  /// Employees sign in on one shared login, so "assigned to an employee" would
  /// mean assigned to everybody at once. Dispatch puts work on a driver, or on
  /// the owner, both of whom are one person at one login.
  bool get takesJobs => this != Role.employee;

  /// Drivers see what a job bills and what is still owed on it — they are the
  /// ones taking the money at the kerb. The shared login does not.
  bool get seesMoney => this != Role.employee;

  /// Which access levels this one is allowed to hire.
  ///
  /// Only the owner, and the owner can make anybody — including another owner.
  /// Nobody else can mint an account at all, which is what keeps "add crew"
  /// from being a privilege escalation with a friendly form on top of it.
  List<Role> get canHire => switch (this) {
    Role.admin => const [Role.employee, Role.driver, Role.admin],
    Role.driver || Role.employee => const [],
  };

  bool canHireRole(Role other) => canHire.contains(other);
}

/// Reads a level back by name, or null when the name means nothing.
///
/// Managers were folded into the owner when the logins were cut down to one
/// owner, a driver each, and one shared crew login. Files written before that
/// still say `manager` — an account, a session, a roster entry — and dropping
/// those would lock somebody out of their own yard on upgrade. A manager comes
/// back as an owner, which is where their permissions went.
Role? roleFrom(Object? name) => switch (name) {
  'admin' || 'manager' => Role.admin,
  'driver' => Role.driver,
  'employee' => Role.employee,
  _ => null,
};
