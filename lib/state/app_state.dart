import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';

import '../data/board_repository.dart';
import '../data/ids.dart';
import '../data/seed_data.dart';
import '../data/store.dart';
import '../models/mutation.dart';
import '../models/crew_member.dart';
import '../models/job.dart';
import '../models/role.dart';
import '../services/location_service.dart';
import '../services/photo_service.dart';

/// Tabs, per role. Kept as an enum so a stale tab can never survive a role
/// switch — [AppState.enter] always lands on one this role owns.
enum HaulTab { board, mine, jobs, crew, tracking, overview }

extension HaulTabLabel on HaulTab {
  String get label => switch (this) {
    HaulTab.board => 'Board',
    HaulTab.mine => 'My jobs',
    HaulTab.jobs => 'Jobs',
    HaulTab.crew => 'Crew',
    HaulTab.tracking => 'Tracking',
    HaulTab.overview => 'Overview',
  };
}

/// Everything the board knows. One [ChangeNotifier] rather than a state
/// management package — the app has a single screen's worth of state and no
/// dependency here is a dependency that can't break a Windows or Linux build.
class AppState extends ChangeNotifier {
  AppState({
    List<Job>? jobs,
    BoardRepository? board,
    LocationService? location,
    PhotoService? photos,
    this.tickInterval = const Duration(milliseconds: 2500),
    this.autoAdvance = true,
    this.toastDuration = const Duration(milliseconds: 3800),
    this.storageIsDurable = true,
    Store? store,
    DateTime Function()? now,
    IdGenerator? idGenerator,
  }) : _prefs = store ?? MemoryStore(),
       _location = location ?? const GeolocatorLocationService(),
       photos = photos ?? ImagePickerPhotoService(),
       _now = now ?? DateTime.now,
       _ids = idGenerator ?? ids,
       _board =
           board ??
           LocalBoardRepository(store: MemoryStore(), seed: jobs, now: now) {
    _board.addListener(_onBoardChanged);
  }

  /// The board is no longer a list this class owns. Every change goes through
  /// the repository as a recorded mutation, so it survives the app dying and
  /// can be replayed at a server later.
  final BoardRepository _board;
  final IdGenerator _ids;

  BoardRepository get board => _board;
  SyncState get syncState => _board.syncState;
  Set<String> get unsyncedJobIds => _board.unsyncedJobIds;

  void _onBoardChanged() => notifyListeners();

  /// Reads whatever this device already had. Call once at startup.
  Future<void> restore() async {
    await _board.load();
    await _restoreThemeMode();
  }

  // ------------------------------------------------------------ appearance

  /// Where UI preferences live. Separate from the board on purpose: this is a
  /// setting on *this device*, not a fact about the business, so it is never
  /// queued for dispatch.
  final Store _prefs;

  static const _themeKey = 'theme.v1';

  ThemeMode _themeMode = ThemeMode.system;

  /// Dark, light, or whatever the device is set to.
  ///
  /// The default follows the device rather than forcing dark. A driver who has
  /// already told their phone they want light text on dark — or the reverse —
  /// has said everything they intend to say about it.
  ThemeMode get themeMode => _themeMode;

  Future<void> _restoreThemeMode() async {
    final stored = await _prefs.readString(_themeKey);
    final mode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      // Anything else — absent, or written by a build that knew more modes
      // than this one — falls back rather than throwing on launch.
      _ => null,
    };
    if (mode == null || mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    // Applied first, written second. A phone that refuses the write still
    // changes the screen; it just forgets by morning.
    await _prefs.writeString(_themeKey, mode.name);
  }

  /// Steps through the three modes. Deliberately a cycle rather than a switch:
  /// "follow the device" is a real answer and has to be reachable again after
  /// someone has overridden it.
  Future<void> cycleThemeMode() => setThemeMode(switch (_themeMode) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  });

  final LocationService _location;
  final PhotoService photos;

  /// How often the movement ticker fires, and the basis for how far a rig
  /// moves each step.
  final Duration tickInterval;

  /// False stops the periodic timer without changing the step maths — tests
  /// call [tick] directly instead of waiting on wall-clock time.
  final bool autoAdvance;

  /// Null leaves a toast up until it is replaced or dismissed.
  final Duration? toastDuration;

  /// False when the device refused to give us somewhere to write. The board
  /// still works for this session, but nothing survives closing the app, and
  /// the driver is told rather than left to find out.
  final bool storageIsDurable;

  final DateTime Function() _now;

  /// Progress the ticker animates. Kept out of the persisted board: it is a
  /// derived guess about where a truck is between two real events, not a fact
  /// worth writing down or syncing.
  final Map<String, double> _progress = {};

  Role? _role;
  HaulTab _tab = HaulTab.board;
  String? _openJobId;
  String? _toast;
  Job? _closedJob;
  bool _asEmployee = false;
  GpsFix _gps = const GpsFix(state: GpsState.off);

  Timer? _ticker;
  StreamSubscription<GpsFix>? _gpsSub;
  Timer? _toastTimer;

  // ---------------------------------------------------------------- reading

  List<Job> get jobs => [
    for (final job in _board.jobs)
      if (_progress[job.id] case final p?) job.copyWith(progress: p) else job,
  ];

  Role? get role => _role;
  HaulTab get tab => _tab;
  String? get toast => _toast;
  Job? get closedJob => _closedJob;
  bool get asEmployee => _asEmployee;
  GpsFix get gps => _gps;

  /// Everyone on the books, drivers and office alike.
  List<CrewMember> get crew => _board.crew;

  /// Just the people who run loads — who a job can be pushed at.
  List<CrewMember> get drivers =>
      crew.where((c) => c.role == Role.employee).toList();

  CrewMember get me => crew.firstWhere(
    (c) => c.id == kMeId,
    // The roster is data now, and data can be edited. A board whose "me" has
    // been removed should not take the app down on the next frame.
    orElse: () => kCrew.firstWhere((c) => c.id == kMeId),
  );

  // -------------------------------------------------------- editing a job

  /// Only an owner corrects a job, and not while standing in the crew's view.
  bool get canEditJobs => _role == Role.admin && !_asEmployee;

  /// Applies dispatch's corrections to [job].
  ///
  /// [fields] is the changed values keyed by the same names the job serialises
  /// under. Anything outside [EditJob.editable] is dropped rather than trusted:
  /// the record of what a driver actually did is not dispatch's to rewrite.
  Future<bool> editJob(Job job, Map<String, Object?> fields) async {
    if (!canEditJobs) {
      showToast('Only an owner can change job details.');
      notifyListeners();
      return false;
    }

    final allowed = {
      for (final e in fields.entries)
        if (EditJob.editable.contains(e.key)) e.key: e.value,
    };
    if (allowed.isEmpty) return false;

    final ok = await _board.apply(
      _stamp(
        (id, at) => EditJob(
          id: id,
          jobId: job.id,
          actorId: kMeId,
          at: at,
          fields: allowed,
        ),
      ),
    );
    if (!ok) {
      // Nothing actually differed, so there is nothing to announce.
      return false;
    }

    showToast('${job.id} updated.');
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------ hiring

  /// What the signed-in role is allowed to take on.
  ///
  /// Empty for a driver, and empty for anyone standing in the employee view —
  /// if you are looking at what your crew sees, you get what your crew gets.
  List<Role> get hirableRoles =>
      _asEmployee ? const [] : (_role?.canHire ?? const []);

  bool get canHire => hirableRoles.isNotEmpty;

  /// Puts someone on the books.
  ///
  /// Refuses a role the signed-in user is not allowed to hire, rather than
  /// trusting the form to have offered the right options — "add crew" must not
  /// become a privilege escalation with a friendly form on top of it.
  Future<bool> hire({
    required String name,
    required Role role,
    required String unit,
    required List<String> rig,
  }) async {
    if (!hirableRoles.contains(role)) {
      showToast('You cannot add a ${role.label.toLowerCase()}.');
      notifyListeners();
      return false;
    }

    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;

    final member = CrewMember(
      id: _ids.next('crew'),
      name: trimmed,
      initials: initialsFor(trimmed),
      unit: unit.trim(),
      // Nobody is on shift the moment they are hired, and nobody has the app
      // open before they have installed it. Starting them "live" would put a
      // driver on the tracking board who has never seen the thing.
      onShift: false,
      appOpen: false,
      rig: rig,
      role: role,
    );

    final ok = await _board.apply(
      _stamp(
        (id, at) =>
            AddCrewMember(id: id, actorId: kMeId, at: at, member: member),
      ),
    );
    if (!ok) return false;

    showToast('${member.name} added as ${role.label.toLowerCase()}.');
    notifyListeners();
    return true;
  }

  /// The job open in the detail pane, re-read from the list every time so it
  /// never shows a stale copy after a stage change.
  Job? get openJob {
    if (_openJobId == null) return null;
    for (final j in jobs) {
      if (j.id == _openJobId) return j;
    }
    return null;
  }

  /// A manager or admin can drop into the driver's view to see exactly what
  /// their crew sees — including having the money hidden.
  bool get employeeView => _role == Role.employee || _asEmployee;

  /// Money is visible to managers and admins, unless they've deliberately
  /// stepped into the employee view.
  bool get canSeeMoney => (_role?.seesMoney ?? false) && !_asEmployee;

  List<Job> get myJobs => jobs
      .where((j) => j.assignedTo == kMeId && j.status != JobStatus.done)
      .toList();

  List<Job> get openBoard =>
      jobs.where((j) => j.status == JobStatus.open).toList();

  List<Job> get activeAll => jobs
      .where(
        (j) => j.status == JobStatus.active || j.status == JobStatus.assigned,
      )
      .toList();

  List<Job> get doneAll =>
      jobs.where((j) => j.status == JobStatus.done).toList();

  List<Job> get myDone => doneAll.where((j) => j.assignedTo == kMeId).toList();

  /// Jobs with a driver actually between two stops right now.
  List<Job> get moving => jobs
      .where((j) => j.status == JobStatus.active && j.phase.moving)
      .toList();

  int get myEarned => myDone.fold(0, (s, j) => s + j.payout);
  int get revenue => doneAll.fold(0, (s, j) => s + j.billed);
  int get cost => doneAll.fold(0, (s, j) => s + j.payout + j.dumpFee);

  /// The tabs this role gets, in order.
  List<HaulTab> get navTabs {
    if (employeeView) return const [HaulTab.board, HaulTab.mine];
    return switch (_role) {
      Role.manager => const [HaulTab.jobs, HaulTab.crew, HaulTab.board],
      Role.admin => const [
        HaulTab.overview,
        HaulTab.tracking,
        HaulTab.jobs,
        HaulTab.crew,
      ],
      _ => const [HaulTab.board, HaulTab.mine],
    };
  }

  bool canRun(Job job) => me.canRun(job.equipment);

  // ---------------------------------------------------------------- writing

  /// Sign in. Starts location reporting and the movement ticker; both stop
  /// again in [signOut] and [dispose].
  void enter(Role role) {
    _role = role;
    _asEmployee = false;
    _tab = switch (role) {
      Role.employee => HaulTab.board,
      Role.manager => HaulTab.jobs,
      Role.admin => HaulTab.overview,
    };
    _startLocation();
    _startTicker();
    notifyListeners();
  }

  void signOut() {
    _role = null;
    _openJobId = null;
    _closedJob = null;
    _asEmployee = false;
    _stopLocation();
    _ticker?.cancel();
    _ticker = null;
    _gps = const GpsFix(state: GpsState.off);
    notifyListeners();
  }

  void setTab(HaulTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  void toggleEmployeeView() {
    _asEmployee = !_asEmployee;
    _tab = _asEmployee
        ? HaulTab.board
        : (_role == Role.admin ? HaulTab.overview : HaulTab.jobs);
    notifyListeners();
  }

  void openJobCard(Job job) {
    _openJobId = job.id;
    notifyListeners();
  }

  void closeJobCard() {
    if (_openJobId == null) return;
    _openJobId = null;
    notifyListeners();
  }

  void dismissClosedJob() {
    _closedJob = null;
    _tab = employeeView ? HaulTab.board : _tab;
    notifyListeners();
  }

  // Each of these records what the driver did and hands it to the board. The
  // repository applies it locally, writes it down, and syncs when it can — so
  // none of these methods can fail for lack of signal.

  Mutation _stamp(Mutation Function(String id, DateTime at) build) =>
      build(_ids.next('mut'), _now());

  /// Driver takes an unclaimed job off the board.
  Future<void> claim(Job job) async {
    final ok = await _board.apply(
      _stamp(
        (id, at) => ClaimJob(id: id, jobId: job.id, actorId: kMeId, at: at),
      ),
    );
    if (!ok) {
      // Another driver got there first — on this device that means the board
      // moved under us between the tap and the write.
      showToast('${job.id} is no longer open. Someone else took it.');
      notifyListeners();
      return;
    }
    _progress.remove(job.id);
    showToast("${job.id} is yours. Dispatch can see you're on it.");
    _openJobId = null;
    _tab = HaulTab.mine;
    notifyListeners();
  }

  /// Driver says yes to a job dispatch pushed at them.
  Future<void> accept(Job job) async {
    final ok = await _board.apply(
      _stamp(
        (id, at) => AcceptJob(id: id, jobId: job.id, actorId: kMeId, at: at),
      ),
    );
    if (!ok) {
      showToast('${job.id} is no longer waiting on you.');
      notifyListeners();
      return;
    }
    _progress.remove(job.id);
    showToast('Accepted ${job.id}.');
    notifyListeners();
  }

  /// Step the job to its next stage. Closing is refused until both photos are
  /// filed — that rule is the reason the photo slots exist, and it is enforced
  /// in the mutation too, so a replay cannot sneak past it.
  ///
  /// Returns true if the job moved.
  Future<bool> advance(Job job) async {
    final next = job.stage + 1;
    if (next >= kStages.length) return false;

    final closing = next == kStages.length - 1;
    if (closing && !job.photosComplete) {
      showToast('Add a before and an after photo before closing this job.');
      notifyListeners();
      return false;
    }

    final ok = await _board.apply(
      _stamp(
        (id, at) => AdvanceStage(
          id: id,
          jobId: job.id,
          actorId: kMeId,
          at: at,
          toStage: next,
        ),
      ),
    );
    if (!ok) return false;

    _progress.remove(job.id);
    if (closing) {
      _closedJob = _board.jobs.firstWhere((j) => j.id == job.id);
      _openJobId = null;
    }
    notifyListeners();
    return true;
  }

  // -------------------------------------------------- the on-site prompt

  /// Jobs whose before-photo prompt the driver has waved away.
  ///
  /// Not persisted: it is a "not this second" for the current sitting, not a
  /// decision worth remembering. Reopening the app should ask again, because
  /// the photo is still missing and the load is still there.
  final Set<String> _waivedPhotoPrompts = {};

  /// True once a driver is standing on site with no before shot filed.
  ///
  /// Derived rather than fired on arrival, deliberately. An event would need
  /// clearing, could be missed while the card was closed, and would go stale
  /// the moment the job was reopened. This answers the only question that
  /// matters — *is there still no before photo?* — every time it is asked.
  bool beforePhotoDue(Job job) =>
      job.assignedTo == kMeId &&
      job.status == JobStatus.active &&
      job.stage >= kOnSiteStage &&
      job.photosBefore.isEmpty &&
      !_waivedPhotoPrompts.contains(job.id);

  /// "Not right now." The prompt comes back next time the app opens.
  void waiveBeforePhotoPrompt(String jobId) {
    if (!_waivedPhotoPrompts.add(jobId)) return;
    notifyListeners();
  }

  /// Dispatch pushes a job at a driver. They still have to accept it.
  Future<void> assign(Job job, String crewId) async {
    final ok = await _board.apply(
      _stamp(
        (id, at) => AssignJob(
          id: id,
          jobId: job.id,
          actorId: kMeId,
          at: at,
          driverId: crewId,
        ),
      ),
    );
    if (!ok) {
      showToast('${job.id} could not be reassigned.');
      notifyListeners();
      return;
    }
    final name = crewById(crewId)?.name ?? 'the driver';
    showToast('${job.id} pushed to $name. They still have to accept it.');
    notifyListeners();
  }

  /// Ask for a shot and file it against [job]. No-ops if the driver backs out.
  Future<void> addPhoto(Job job, {required bool before}) async {
    final shot = await photos.capture(PhotoSource.camera);
    if (shot == null) return;

    final ok = await _board.apply(
      _stamp(
        (id, at) => AttachPhoto(
          id: id,
          jobId: job.id,
          actorId: kMeId,
          at: at,
          photoId: shot.id,
          photoName: shot.name,
          before: before,
        ),
      ),
      photo: shot,
    );
    if (!ok) {
      showToast('That photo could not be filed. Try again.');
      notifyListeners();
      return;
    }
    showToast('${before ? "Before" : "After"} photo filed on ${job.id}.');
    notifyListeners();
  }

  /// Push anything queued at the server now. Driver-initiated, so it does not
  /// wait out a backoff.
  Future<void> syncNow() => _board.sync(force: true);

  /// Put work the server refused back in the queue.
  Future<void> retryFailedSync() => _board.retryFailed();

  /// Transient message. Also announced to screen readers by the widget that
  /// renders it, so it isn't a visual-only signal.
  void showToast(String message) {
    _toast = message;
    _toastTimer?.cancel();
    final after = toastDuration;
    if (after == null) return;
    _toastTimer = Timer(after, () {
      _toast = null;
      notifyListeners();
    });
  }

  // ------------------------------------------------------------- internals

  void _startLocation() {
    _gpsSub?.cancel();
    _gpsSub = _location.watch().listen((fix) {
      _gps = fix;
      notifyListeners();
    }, onError: (_) {});
  }

  void _stopLocation() {
    _gpsSub?.cancel();
    _gpsSub = null;
  }

  /// Drivers in a travel phase close on their destination. Sped up relative to
  /// real road speed so the board visibly moves while you're looking at it.
  void _startTicker() {
    _ticker?.cancel();
    if (!autoAdvance) return;
    _ticker = Timer.periodic(tickInterval, (_) => tick());
  }

  /// One movement step. Public so tests can drive it without waiting on wall
  /// clock time.
  @visibleForTesting
  void tick() {
    var changed = false;
    for (final job in jobs) {
      if (job.status != JobStatus.active || !job.phase.moving) continue;
      if (job.progress >= 1) continue;

      final legMs = (job.legMiles / kAvgMph) * 3600 * 1000;
      final step = tickInterval.inMilliseconds / (legMs < 1 ? 1 : legMs) * 12;
      _progress[job.id] = (job.progress + step).clamp(0.0, 1.0);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _board.removeListener(_onBoardChanged);
    _ticker?.cancel();
    _toastTimer?.cancel();
    _stopLocation();
    super.dispose();
  }
}

/// Reaches [AppState] from anywhere in the tree and rebuilds on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!.notifier!;
  }

  /// Reads without subscribing — for callbacks that only ever write.
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!.notifier!;
  }
}
