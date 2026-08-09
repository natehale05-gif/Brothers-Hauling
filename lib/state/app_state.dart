import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';

import '../data/accounts.dart';
import '../data/board_repository.dart';
import '../data/ids.dart';
import '../data/intake.dart';
import '../data/seed_data.dart';
import '../data/server_control.dart';
import '../data/store.dart';
import '../models/mutation.dart';
import '../models/time_entry.dart';
import '../models/crew_member.dart';
import '../models/job.dart';
import '../models/role.dart';
import '../services/alert_service.dart';
import '../services/location_service.dart';
import '../services/photo_service.dart';

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
    IntakeSource? intake,
    DateTime Function()? now,
    IdGenerator? idGenerator,
    ServerControl? server,
    AccountBook? accounts,
    AlertService? alerts,
    this.sampleLogins = true,
  }) : _prefs = store ?? MemoryStore(),
       // ignore: prefer_initializing_formals
       _server = server,
       _accounts = accounts ?? AccountBook(),
       _intake = intake ?? const NoIntakeSource(),
       _alerts = alerts ?? SilentAlertService(),
       _location = location ?? const GeolocatorLocationService(),
       photos = photos ?? ImagePickerPhotoService(),
       _now = now ?? DateTime.now,
       _ids = idGenerator ?? ids,
       _board =
           board ??
           LocalBoardRepository(store: MemoryStore(), seed: jobs, now: now) {
    _board.addListener(_onBoardChanged);
  }

  /// Whether a device with no accounts makes itself the sample ones.
  ///
  /// On by default, because a fresh install with no way in is an app nobody
  /// can open. Tests turn it off when they want to drive the empty case.
  final bool sampleLogins;

  /// The board is no longer a list this class owns. Every change goes through
  /// the repository as a recorded mutation, so it survives the app dying and
  /// can be replayed at a server later.
  final BoardRepository _board;
  final IdGenerator _ids;

  BoardRepository get board => _board;
  SyncState get syncState => _board.syncState;
  Set<String> get unsyncedJobIds => _board.unsyncedJobIds;

  final AlertService _alerts;

  void _onBoardChanged() {
    // The board moved, so whatever the device is holding is now out of date.
    unawaited(syncAlerts());
    notifyListeners();
  }

  /// Where website bookings come from. [NoIntakeSource] when none is wired up,
  /// which is a board that simply never gains a job on its own.
  final IntakeSource _intake;

  /// Reads whatever this device already had. Call once at startup.
  Future<void> restore() async {
    await _board.load();
    await _restoreThemeMode();
    await _restoreAccounts();
    await _restoreSession();
    // Anything booked while the app was closed is on the board before the
    // first frame, rather than appearing a second later.
    await checkForBookings();
  }

  // ------------------------------------------- serving the crew from here

  static const _accountsKey = 'accounts.v1';
  static const _sessionKey = 'session.v1';

  final ServerControl? _server;

  /// The same book the server checks passwords against — see [AccountBook.adopt].
  final AccountBook _accounts;

  /// Whether this device could be the one the crew syncs to.
  ///
  /// False on the web, which cannot listen on a port — the panel says so
  /// rather than offering a button that does nothing.
  bool get canServe => _server?.supported ?? false;

  bool get serving => _server?.running ?? false;

  /// Addresses a driver could type in. Empty until the server is running.
  List<String> get serverAddresses => _server?.addresses ?? const [];

  int get serverPort => _server?.port ?? 0;

  /// Only an owner turns this device into the board everybody else reads.
  bool get canManageServer => _role == Role.admin && !_asEmployee;

  /// Who has a login, in the order they were added.
  ///
  /// The book holds password hashes and nothing else — the owner runs the
  /// server and still cannot read what anybody typed.
  List<Account> get accounts => _accounts.accounts.toList();

  bool hasLogin(String crewId) =>
      _accounts.accounts.any((a) => a.crewId == crewId);

  Future<void> _restoreAccounts() async {
    final stored = AccountBook.decode(await _prefs.readString(_accountsKey));
    _accounts.adopt(stored.accounts);

    // A device nobody has set up gets a way in, matched to the sample roster
    // the sample board is already about. Every one of them is flagged, and the
    // app keeps saying so until somebody replaces the password.
    if (_accounts.isEmpty && sampleLogins) {
      for (final (username, crewId, role) in kSampleLogins) {
        _accounts.put(
          Account(
            username: username,
            crewId: crewId,
            role: role,
            password: PasswordHash.of(kSamplePassword),
            sample: true,
          ),
        );
      }
      await _writeAccounts();
    }

    notifyListeners();
  }

  /// Signs back in as whoever was signed in when the app last closed.
  Future<void> _restoreSession() async {
    final raw = await _prefs.readString(_sessionKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final json = jsonDecode(raw);
      if (json is! Map) return;
      final stored = Session.fromJson(json.cast<String, Object?>());
      if (stored == null) return;

      // The account has to still exist and still hold that role. Somebody
      // demoted or removed while the app was closed does not get to keep the
      // level they had on the way out.
      final account = _accounts.accounts
          .where((a) => a.key == Account.normalise(stored.username))
          .firstOrNull;
      if (account == null || account.role != stored.role) {
        await _prefs.writeString(_sessionKey, '');
        return;
      }

      _session = stored;
      enter(stored.role);
    } catch (_) {
      // A session this build cannot read is a session nobody is signed in on.
      await _prefs.writeString(_sessionKey, '');
    }
  }

  Future<void> _writeAccounts() =>
      _prefs.writeString(_accountsKey, _accounts.encode());

  /// Gives somebody on the roster a way in.
  ///
  /// The password is hashed here and the plain text is never held, written or
  /// sent — which is what makes this safe to run on the owner's own laptop.
  Future<bool> setLogin({
    required CrewMember member,
    required String username,
    required String password,
  }) async {
    if (!canManageServer) {
      showToast('Only an owner can hand out logins.');
      notifyListeners();
      return false;
    }
    if (username.trim().isEmpty || password.isEmpty) {
      showToast('A login needs a name and a password.');
      notifyListeners();
      return false;
    }

    final ok = _accounts.put(
      Account(
        username: username.trim(),
        crewId: member.id,
        role: member.role,
        password: PasswordHash.of(password),
      ),
    );
    if (!ok) {
      showToast('Somebody else already signs in as that.');
      notifyListeners();
      return false;
    }

    await _writeAccounts();
    showToast('${member.name} can sign in now.');
    notifyListeners();
    return true;
  }

  /// Takes somebody's way in away.
  ///
  /// Their device stops working at its next request rather than at its next
  /// restart, which is the point of doing it at all.
  Future<bool> removeLogin(String username) async {
    if (!canManageServer) {
      showToast('Only an owner can take a login away.');
      notifyListeners();
      return false;
    }
    if (!_accounts.has(username)) return false;

    _accounts.remove(username);
    await _writeAccounts();
    showToast('$username can no longer sign in.');
    notifyListeners();
    return true;
  }

  /// Starts or stops serving the board to the crew from this device.
  Future<bool> setServing(bool on) async {
    final server = _server;
    if (!canManageServer || server == null || !server.supported) {
      showToast('This device cannot be the dispatch server.');
      notifyListeners();
      return false;
    }
    if (on == server.running) return true;

    if (on && _accounts.isEmpty) {
      // A server with no accounts refuses everybody, which looks exactly like
      // a broken network to the crew standing in the yard.
      showToast('Give somebody a login first, or nobody can connect.');
      notifyListeners();
      return false;
    }

    try {
      if (on) {
        await server.start();
        showToast('Serving the board from this device.');
      } else {
        await server.stop();
        showToast('Stopped serving.');
      }
    } catch (e) {
      // Port taken, permission refused, no network. Say which rather than
      // leaving a toggle that silently springs back.
      showToast('Could not start: $e');
      notifyListeners();
      return false;
    }

    notifyListeners();
    return true;
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
  Session? _session;
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

  /// Who is signed in on this device, or null when nobody is.
  Session? get session => _session;

  /// True once somebody has a way in at all. False on a device nobody has set
  /// up yet, which is the one state that offers to make the first account.
  bool get hasAccounts => _accounts.accounts.isNotEmpty;

  /// Logins still carrying the password the app printed on the login box.
  List<Account> get sampleAccounts =>
      _accounts.accounts.where((a) => a.sample).toList();
  String? get toast => _toast;
  Job? get closedJob => _closedJob;
  bool get asEmployee => _asEmployee;
  GpsFix get gps => _gps;

  /// Everyone on the books, drivers and office alike.
  List<CrewMember> get crew => _board.crew;

  /// Every rig the board has ever asked for, in alphabetical order.
  ///
  /// Read off the work rather than kept as a list of what the yard owns. A
  /// hard-coded fleet is a list somebody has to maintain and which is wrong the
  /// week a trailer is sold; this is only ever the kit that has actually been
  /// needed, and it grows the first time somebody types a new one.
  List<String> get knownRigs {
    final seen = <String>{};
    for (final job in _board.jobs) {
      seen.addAll(job.equipment);
    }
    return seen.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Just the people who run loads — who a job can be pushed at.
  List<CrewMember> get drivers =>
      crew.where((c) => c.role == Role.employee).toList();

  /// Who the app thinks you are — the roster entry the signed-in account is
  /// tied to.
  ///
  /// Was a constant, with a comment promising that a real build would resolve
  /// it from auth. It does now.
  String get meId => _session?.crewId ?? kMeId;

  CrewMember get me => crew.firstWhere(
    (c) => c.id == meId,
    // The roster is data now, and data can be edited. A board whose "me" has
    // been removed should not take the app down on the next frame.
    orElse: () => kCrew.firstWhere((c) => c.id == kMeId),
  );

  // ------------------------------------------------------------ the day view

  /// How far the day view has been moved from today, in days.
  ///
  /// An offset rather than a stored date, so a board left open overnight
  /// follows the calendar instead of insisting it is still yesterday.
  int _dayOffset = 0;

  int get dayOffset => _dayOffset;

  /// Midnight today, by the clock this state was given.
  DateTime get today {
    final now = _now();
    return DateTime(now.year, now.month, now.day);
  }

  /// The day currently on screen.
  DateTime get selectedDay => dayFor(_dayOffset);

  DateTime dayFor(int offset) {
    final base = today;
    return DateTime(base.year, base.month, base.day + offset);
  }

  /// Jumps the day view. [offset] is relative to today, not to where it is.
  void showDay(int offset) {
    if (offset == _dayOffset) return;
    _dayOffset = offset;
    notifyListeners();
  }

  /// One day forwards or back — the arrows, and the keyboard.
  void stepDay(int by) => showDay(_dayOffset + by);

  void showToday() => showDay(0);

  /// Everything happening on [day], earliest first.
  ///
  /// Every job, not just this user's — which is why the day view is a dispatch
  /// screen. A driver's board deliberately shows them their own work.
  ///
  /// Sorted by the scheduled time rather than by id, because a day view that
  /// does not read top-to-bottom in the order the day happens is a list, not a
  /// schedule.
  /// [only] narrows it to one view's jobs — a driver's board is the same day,
  /// filtered to what they can actually do something about.
  List<Job> jobsOn(DateTime day, {bool Function(Job job)? only}) {
    final target = DateTime(day.year, day.month, day.day);
    final out =
        jobs
            .where((j) => j.scheduledDay == target && (only?.call(j) ?? true))
            .toList()
          ..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!));
    return out;
  }

  /// Jobs nobody has committed to a day yet.
  ///
  /// Kept visible rather than hidden: a job with no date is not a job that has
  /// gone away, and parking it silently on today is how it gets missed
  /// tomorrow.
  List<Job> get unscheduledJobs =>
      jobs.where((j) => j.scheduledFor == null).toList();

  // ------------------------------------------------- bookings from the web

  /// Bookings that have come in and not been priced yet.
  List<Job> get requestedJobs =>
      jobs.where((j) => j.status == JobStatus.requested).toList();

  /// Reads the website and enters anything new on the board.
  ///
  /// Safe to call as often as you like: every booking carries the website's own
  /// id, and a job already holding that id is left alone. Returns how many were
  /// genuinely new.
  ///
  /// A source that is down returns nothing rather than throwing — the board is
  /// not allowed to break because the website is.
  Future<int> checkForBookings() async {
    final List<BookingRequest> bookings;
    try {
      bookings = await _intake.fetch();
    } catch (_) {
      return 0;
    }

    // Oldest first, so the board reads in the order people actually booked.
    // Sorted on a copy: what a source hands back is its own, and several of
    // them hand back a const list.
    final ordered = [...bookings]
      ..sort((a, b) => a.requestedAt.compareTo(b.requestedAt));

    final known = {for (final job in _board.jobs) ?job.bookingId};

    var added = 0;
    for (final booking in ordered) {
      if (known.contains(booking.id)) continue;
      final job = booking.toJob(_nextJobId());
      final ok = await _board.apply(
        _stamp((id, at) => CreateJob(id: id, actorId: meId, at: at, job: job)),
      );
      if (ok) {
        added++;
        known.add(booking.id);
      }
    }

    if (added > 0) {
      showToast(
        added == 1
            ? 'A new job came in from the website.'
            : '$added new jobs came in from the website.',
      );
    }
    notifyListeners();
    return added;
  }

  /// The next board-facing job number.
  ///
  /// Human-readable on purpose — "HL-4492" is what gets said down a phone, and
  /// a device-minted opaque id is not. The device id still exists underneath as
  /// the mutation's key, so two phones inventing the same number is a display
  /// collision rather than a lost job.
  String _nextJobId() {
    var highest = 4470;
    for (final job in _board.jobs) {
      final n = int.tryParse(job.id.replaceAll(RegExp(r'[^0-9]'), ''));
      if (n != null && n > highest) highest = n;
    }
    return 'HL-${highest + 1}';
  }

  /// Puts a priced booking onto the driver board.
  ///
  /// Refused while it still pays nothing: an unpriced job on the board is a job
  /// someone can volunteer for at nothing a load.
  Future<bool> publishJob(Job job) async {
    if (!canPriceJobs) {
      showToast('Only an owner or a manager can put a job on the board.');
      notifyListeners();
      return false;
    }
    if (job.billed <= 0) {
      showToast('Put a price on it before it goes to the crew.');
      notifyListeners();
      return false;
    }

    final ok = await _board.apply(
      _stamp(
        (id, at) => PublishJob(id: id, jobId: job.id, actorId: meId, at: at),
      ),
    );
    if (!ok) return false;

    showToast('${job.id} is on the board.');
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------- reminders

  /// What the device has been asked to buzz about, and when.
  List<Alert> get alerts => _alerts.scheduled;

  /// False once the phone has said no. The app says so rather than pretending
  /// the reminders are set.
  bool get alertsAllowed => _alertsAllowed;
  bool _alertsAllowed = true;

  /// False in a browser, which can only raise a reminder while the page is
  /// open. Worth saying rather than letting somebody close a tab expecting to
  /// be told about a nine o'clock.
  bool get alertsSurviveClosing => _alerts.firesWhenClosed;

  /// Asks the platform for permission, then reconciles.
  Future<bool> enableAlerts() async {
    _alertsAllowed = await _alerts.ensureAllowed();
    await syncAlerts();
    notifyListeners();
    return _alertsAllowed;
  }

  /// Brings the device's reminders into line with the board.
  ///
  /// Called on every board change rather than on the edit that caused it: a
  /// job can move because somebody else moved it and it synced here, and a
  /// reminder that only tracked local edits would go off at the old time.
  Future<void> syncAlerts() => _alerts.sync(alertsFor(jobs, _now()));

  // ------------------------------------------------ writing from the calendar

  /// Books a new job, and hands back the job as it landed.
  ///
  /// The id is minted here rather than by the caller so two jobs written in
  /// the same second cannot collide, and the whole thing goes through the same
  /// outbox as everything else — a job written in a dead zone is on the board
  /// before the phone finds signal.
  Future<Job?> addJob({
    required String type,
    required String customer,
    String address = '',
    String city = '',
    String contact = '',
    String phone = '',
    String access = '',
    String material = '',
    List<String> equipment = const [],
    String window = '',
    int billed = 0,
    int dumpFee = 0,
    DateTime? scheduledFor,
    int? minutes,
    int? alertMinutes,
  }) async {
    if (!canEditJobs) {
      showToast('Only an owner can add a job.');
      notifyListeners();
      return null;
    }

    final job = Job(
      id: _nextJobId(),
      type: type.trim(),
      customer: customer.trim(),
      address: address.trim(),
      city: city.trim(),
      contact: contact.trim(),
      phone: phone.trim(),
      access: access.trim(),
      material: material.trim(),
      volume: '',
      weight: '',
      equipment: [
        for (final rig in equipment)
          if (rig.trim().isNotEmpty) rig.trim(),
      ],
      disposal: '',
      dumpFee: dumpFee,
      window: window.trim(),
      miles: 0,
      deadhead: 0,
      billed: billed,
      scheduledFor: scheduledFor,
      minutes: minutes,
      alertMinutes: alertMinutes,
    );

    final ok = await _board.apply(
      _stamp((id, at) => CreateJob(id: id, actorId: meId, at: at, job: job)),
    );
    if (!ok) return null;

    showToast('${job.id} added.');
    notifyListeners();
    return job;
  }

  /// Takes a job off the board for good.
  ///
  /// Deliberately not offered for work a driver has already started: the
  /// movement log, the hours and the photos are the record of what happened,
  /// and deleting the job is not the way to correct a mistake on it.
  bool canDelete(Job job) =>
      canEditJobs &&
      job.startedAt == null &&
      job.status != JobStatus.active &&
      job.status != JobStatus.done;

  Future<bool> deleteJob(Job job) async {
    if (!canEditJobs) {
      showToast('Only an owner can delete a job.');
      notifyListeners();
      return false;
    }
    if (!canDelete(job)) {
      showToast('${job.id} has been worked — it cannot be deleted.');
      notifyListeners();
      return false;
    }

    final ok = await _board.apply(
      _stamp(
        (id, at) => DeleteJob(id: id, actorId: meId, at: at, jobId: job.id),
      ),
    );
    if (!ok) return false;

    showToast('${job.id} deleted.');
    notifyListeners();
    return true;
  }

  /// Moves a job to a new moment, and optionally changes how long it runs.
  ///
  /// One call rather than two edits so a drag across the grid is a single
  /// entry in the log and a single thing to undo.
  Future<bool> rescheduleJob(
    Job job, {
    required DateTime? startsAt,
    int? minutes,
  }) => editJob(job, {
    // Null is a real value here — it is how a job goes back to having no day.
    'scheduledFor': startsAt?.toUtc().toIso8601String(),
    'minutes': ?minutes,
  });

  // -------------------------------------------------------- editing a job

  /// Only an owner corrects a job, and not while standing in the crew's view.
  ///
  /// Was briefly relaxed to "anybody, when nobody is signed in", because
  /// nothing could sign in and the calendar would otherwise have been
  /// read-only. There is a login now, so the rule is the rule again.
  bool get canEditJobs => _role == Role.admin && !_asEmployee;

  /// Who may put a number on a job.
  ///
  /// Deliberately wider than [canEditJobs]. A manager runs the day: they are
  /// the one on the phone when a quote turns out to be wrong, and a yard where
  /// only the owner can price is a yard where work sits unpriced until he gets
  /// back. What a manager still cannot do is rewrite the job around the price
  /// — the address, the day and the rig stay the owner's.
  bool get canPriceJobs =>
      (_role == Role.admin || _role == Role.manager) && !_asEmployee;

  /// Sets what a job bills at, and what the tip charges to take it.
  ///
  /// Its own write path rather than a corner of [editJob], because the two are
  /// allowed to different people and a permission that depends on which keys
  /// happen to be in a map is a permission nobody can check by reading it.
  Future<bool> priceJob(
    Job job, {
    required int billed,
    required int dumpFee,
  }) async {
    if (!canPriceJobs) {
      showToast('Only an owner or a manager can price a job.');
      notifyListeners();
      return false;
    }
    if (billed < 0 || dumpFee < 0) {
      showToast('A price cannot be less than nothing.');
      notifyListeners();
      return false;
    }

    final ok = await _board.apply(
      _stamp(
        (id, at) => EditJob(
          id: id,
          jobId: job.id,
          actorId: meId,
          at: at,
          fields: {'billed': billed, 'dumpFee': dumpFee},
        ),
      ),
    );
    // Nothing differed — the price was already this. Not a failure.
    if (!ok) return false;

    showToast('${job.id} bills at \$$billed.');
    notifyListeners();
    return true;
  }

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
          actorId: meId,
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

  /// Only an owner moves somebody between levels.
  ///
  /// Deliberately narrower than [canHire]: a manager may take on a driver, but
  /// letting them promote one is the same escalation by a slower route.
  bool get canSetRoles => _role == Role.admin && !_asEmployee;

  /// Promotes or demotes [member].
  ///
  /// Refuses to touch the signed-in user's own level. Demoting yourself locks
  /// the owner screens behind a door you have just thrown the key over, and on
  /// a one-owner company it leaves nobody able to open it again. Since the
  /// actor must already be an owner, that guard alone keeps at least one owner
  /// standing.
  Future<bool> setCrewRole(CrewMember member, Role role) async {
    if (!canSetRoles) {
      showToast('Only an owner can change what someone can see.');
      notifyListeners();
      return false;
    }
    if (member.id == meId) {
      showToast('You cannot change your own access.');
      notifyListeners();
      return false;
    }
    if (member.role == role) return false;

    final ok = await _board.apply(
      _stamp(
        (id, at) => SetCrewRole(
          id: id,
          actorId: meId,
          at: at,
          crewId: member.id,
          role: role,
        ),
      ),
    );
    if (!ok) return false;

    showToast('${member.name} is now ${role.label.toLowerCase()}.');
    notifyListeners();
    return true;
  }

  /// Puts someone on the books.
  ///
  /// Refuses a role the signed-in user is not allowed to hire, rather than
  /// trusting the form to have offered the right options — "add crew" must not
  /// become a privilege escalation with a friendly form on top of it.
  Future<bool> hire({
    required String name,
    required Role role,
    required String unit,
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
      role: role,
    );

    final ok = await _board.apply(
      _stamp(
        (id, at) =>
            AddCrewMember(id: id, actorId: meId, at: at, member: member),
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
      .where((j) => j.assignedTo == meId && j.status != JobStatus.done)
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

  List<Job> get myDone => doneAll.where((j) => j.assignedTo == meId).toList();

  /// Jobs with a driver actually between two stops right now.
  List<Job> get moving => jobs
      .where((j) => j.status == JobStatus.active && j.phase.moving)
      .toList();

  int get revenue => doneAll.fold(0, (s, j) => s + j.billed);

  /// Disposal plus labour. Labour is hours × rate, which is why it cannot be
  /// read off the jobs alone.
  int get cost =>
      doneAll.fold(0, (s, j) => s + j.dumpFee) +
      timesheets.fold(0, (s, t) => s + (t.pay ?? 0));

  // ---------------------------------------------------------------- hours

  /// Everyone's paid time, derived from the jobs themselves.
  ///
  /// There is no timer to start and none to forget to stop: a job's own start
  /// and finish stamps are the timesheet, so a shift worked with no signal is
  /// already counted by the time the phone finds any.
  List<TimeEntry> get timeEntries => TimeEntry.from(_board.jobs);

  /// One per person, biggest first, so the eye lands on who has done the most.
  List<Timesheet> get timesheets {
    final byCrew = <String, List<TimeEntry>>{};
    for (final entry in timeEntries) {
      (byCrew[entry.crewId] ??= []).add(entry);
    }
    final out = [
      for (final member in crew)
        Timesheet(
          member: member,
          entries: byCrew[member.id] ?? const [],
          now: _now(),
        ),
    ]..sort((a, b) => b.minutes.compareTo(a.minutes));
    return out;
  }

  /// This person's hours. Everyone has one, even at zero.
  Timesheet timesheetFor(CrewMember member) => Timesheet(
    member: member,
    entries: timeEntries.where((e) => e.crewId == member.id).toList(),
    now: _now(),
  );

  /// Only an owner sees what anybody is paid — including their own figure.
  bool get canSeeHoursAndPay => _role == Role.admin && !_asEmployee;

  /// Only an owner watches the whole crew.
  ///
  /// A manager staffs the day and prices the work; "where is everybody right
  /// now, and what have they put in this week" is a different question, and it
  /// is the owner's. Same rule as the pay figures, and for the same reason.
  bool get canTrackCrew => _role == Role.admin && !_asEmployee;

  /// The job this person has in hand — the one they are on, or have been
  /// pushed and not yet answered. Null when their hands are empty.
  ///
  /// One job, not a list: a driver runs one load at a time, and a screen that
  /// says otherwise is showing a bug rather than a busy morning.
  Job? jobInHand(CrewMember member) {
    for (final job in _board.jobs) {
      if (job.assignedTo != member.id) continue;
      if (job.status == JobStatus.active || job.status == JobStatus.assigned) {
        return job;
      }
    }
    return null;
  }

  /// This person's hours since midnight, counting a job still running.
  Duration hoursToday(CrewMember member) {
    final today = this.today;
    return timeEntries
        .where((e) => e.crewId == member.id && e.day == today)
        .fold(Duration.zero, (total, e) => total + e.workedBy(_now()));
  }

  /// Everyone with a job actually in their hands right now.
  List<CrewMember> get working =>
      crew.where((c) => jobInHand(c) != null).toList();

  /// The driver's own hours. No money attached: what they are owed is payroll's
  /// business, and the app is not where somebody finds out their rate.
  Duration get myHoursToday {
    final today = this.today;
    return timeEntries
        .where((e) => e.crewId == meId && e.day == today)
        .fold(Duration.zero, (total, e) => total + e.workedBy(_now()));
  }

  // ---------------------------------------------------------------- writing

  /// Takes a username and password and, if they match, signs in.
  ///
  /// The password is checked against a hash and then dropped; nothing here
  /// holds it, writes it or sends it. What survives is a token, which is what
  /// makes signing somebody out possible without knowing what they typed.
  Future<bool> signIn(String username, String password) async {
    final session = _accounts.signIn(username, password);
    if (session == null) {
      // Deliberately one message for both halves: saying "no such user" tells
      // whoever is guessing which names are real.
      showToast('That username and password do not match.');
      notifyListeners();
      return false;
    }

    _session = session;
    await _prefs.writeString(_sessionKey, jsonEncode(session.toJson()));
    enter(session.role);
    return true;
  }

  /// Sign in. Starts location reporting and the movement ticker; both stop
  /// again in [signOut] and [dispose].
  void enter(Role role) {
    _role = role;
    _asEmployee = false;
    _startLocation();
    _startTicker();
    notifyListeners();
  }

  Future<void> signOut() async {
    final token = _session?.token;
    if (token != null) _accounts.signOut(token);
    _session = null;
    await _prefs.writeString(_sessionKey, '');

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

  void toggleEmployeeView() {
    _asEmployee = !_asEmployee;
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
    notifyListeners();
  }

  // Each of these records what the driver did and hands it to the board. The
  // repository applies it locally, writes it down, and syncs when it can — so
  // none of these methods can fail for lack of signal.

  Mutation _stamp(Mutation Function(String id, DateTime at) build) =>
      build(_ids.next('mut'), _now());

  /// Whether this job is there for the taking, by whoever is signed in.
  ///
  /// Open, unpriced work excepted, and not already somebody's. Deliberately
  /// not narrowed by level: an owner who drives is an ordinary thing in a
  /// yard this size, and the standing decision is that nothing about a rig or
  /// a job locks a person out of answering.
  bool canTake(Job job) =>
      role != null && job.status == JobStatus.open && !job.needsPricing;

  /// Whether this job is waiting on a yes from the person signed in.
  bool canAccept(Job job) =>
      role != null &&
      job.status == JobStatus.assigned &&
      job.assignedTo == meId;

  /// Driver takes an unclaimed job off the board.
  Future<void> claim(Job job) async {
    final ok = await _board.apply(
      _stamp(
        (id, at) => ClaimJob(id: id, jobId: job.id, actorId: meId, at: at),
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
    notifyListeners();
  }

  /// Driver says yes to a job dispatch pushed at them.
  Future<void> accept(Job job) async {
    final ok = await _board.apply(
      _stamp(
        (id, at) => AcceptJob(id: id, jobId: job.id, actorId: meId, at: at),
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
          actorId: meId,
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
      job.assignedTo == meId &&
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
          actorId: meId,
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
          actorId: meId,
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
    _alerts.dispose();
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
