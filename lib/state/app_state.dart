import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/seed_data.dart';
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
    LocationService? location,
    PhotoService? photos,
    this.tickInterval = const Duration(milliseconds: 2500),
    this.autoAdvance = true,
    this.toastDuration = const Duration(milliseconds: 3800),
    DateTime Function()? now,
  }) : _jobs = List.of(jobs ?? kSeedJobs),
       _location = location ?? const GeolocatorLocationService(),
       photos = photos ?? ImagePickerPhotoService(),
       _now = now ?? DateTime.now;

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

  final DateTime Function() _now;

  List<Job> _jobs;
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

  List<Job> get jobs => List.unmodifiable(_jobs);
  Role? get role => _role;
  HaulTab get tab => _tab;
  String? get toast => _toast;
  Job? get closedJob => _closedJob;
  bool get asEmployee => _asEmployee;
  GpsFix get gps => _gps;

  CrewMember get me => kCrew.firstWhere((c) => c.id == kMeId);

  /// The job open in the detail pane, re-read from the list every time so it
  /// never shows a stale copy after a stage change.
  Job? get openJob {
    if (_openJobId == null) return null;
    for (final j in _jobs) {
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

  List<Job> get myJobs => _jobs
      .where((j) => j.assignedTo == kMeId && j.status != JobStatus.done)
      .toList();

  List<Job> get openBoard =>
      _jobs.where((j) => j.status == JobStatus.open).toList();

  List<Job> get activeAll => _jobs
      .where(
        (j) => j.status == JobStatus.active || j.status == JobStatus.assigned,
      )
      .toList();

  List<Job> get doneAll =>
      _jobs.where((j) => j.status == JobStatus.done).toList();

  List<Job> get myDone => doneAll.where((j) => j.assignedTo == kMeId).toList();

  /// Jobs with a driver actually between two stops right now.
  List<Job> get moving => _jobs
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

  /// Driver takes an unclaimed job off the board.
  void claim(Job job) {
    _patch(
      job.id,
      (j) => j.copyWith(
        status: JobStatus.active,
        assignedTo: kMeId,
        stage: 0,
        progress: 0,
        events: [
          JobEvent(
            time: _clock(),
            label: 'Volunteered for this job',
            kind: EventKind.flat,
          ),
        ],
      ),
    );
    showToast("${job.id} is yours. Dispatch can see you're on it.");
    _openJobId = null;
    _tab = HaulTab.mine;
    notifyListeners();
  }

  /// Driver says yes to a job dispatch pushed at them.
  void accept(Job job) {
    _patch(
      job.id,
      (j) => j.copyWith(
        status: JobStatus.active,
        stage: 0,
        progress: 0,
        events: [
          JobEvent(
            time: _clock(),
            label: 'Accepted the job',
            kind: EventKind.flat,
          ),
        ],
      ),
    );
    showToast('Accepted ${job.id}.');
    notifyListeners();
  }

  /// Step the job to its next stage. Closing is refused until both photos are
  /// filed — that rule is the reason the photo slots exist.
  ///
  /// Returns true if the job moved.
  bool advance(Job job) {
    final next = job.stage + 1;

    if (next == 5) {
      if (!job.photosComplete) {
        showToast('Add a before and an after photo before closing this job.');
        notifyListeners();
        return false;
      }
      _patch(
        job.id,
        (j) => j.copyWith(
          status: JobStatus.done,
          stage: 5,
          progress: 1,
          events: [...j.events, j.transitionEvent(5, _clock())],
        ),
      );
      _closedJob = openJob ?? job;
      _openJobId = null;
      notifyListeners();
      return true;
    }

    if (next > 5) return false;

    _patch(
      job.id,
      (j) => j.copyWith(
        stage: next,
        progress: 0,
        events: [...j.events, j.transitionEvent(next, _clock())],
      ),
    );
    notifyListeners();
    return true;
  }

  /// Dispatch pushes a job at a driver. They still have to accept it.
  void assign(Job job, String crewId) {
    _patch(
      job.id,
      (j) => j.copyWith(status: JobStatus.assigned, assignedTo: crewId),
    );
    final name = crewById(crewId)?.name ?? 'the driver';
    showToast('${job.id} pushed to $name. They still have to accept it.');
    notifyListeners();
  }

  /// Ask for a shot and file it against [job]. No-ops if the driver backs out.
  Future<void> addPhoto(Job job, {required bool before}) async {
    final shot = await photos.capture(PhotoSource.camera);
    if (shot == null) return;
    _patch(
      job.id,
      (j) =>
          before ? j.copyWith(photoBefore: shot) : j.copyWith(photoAfter: shot),
    );
    showToast('${before ? "Before" : "After"} photo filed on ${job.id}.');
    notifyListeners();
  }

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

  void _patch(String id, Job Function(Job) update) {
    _jobs = [
      for (final j in _jobs)
        if (j.id == id) update(j) else j,
    ];
  }

  String _clock() {
    final d = _now();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

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
    _jobs = [
      for (final j in _jobs)
        if (j.status == JobStatus.active && j.phase.moving && j.progress < 1)
          () {
            final legMs = (j.legMiles / kAvgMph) * 3600 * 1000;
            final step =
                tickInterval.inMilliseconds / (legMs < 1 ? 1 : legMs) * 12;
            changed = true;
            return j.copyWith(progress: (j.progress + step).clamp(0.0, 1.0));
          }()
        else
          j,
    ];
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
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
