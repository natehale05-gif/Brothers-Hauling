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
}
