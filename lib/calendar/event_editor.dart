import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoTextThemeData,
        CupertinoTheme,
        CupertinoThemeData;
import 'package:flutter/material.dart';

import '../models/job.dart';
import '../state/app_state.dart';
import 'calendar_state.dart';
import 'calendar_theme.dart';
import 'date_math.dart';

import 'form_bits.dart';

/// How long a new job runs unless somebody says otherwise.
const int kDefaultMinutes = 120;

/// The box for a rig the board has not seen before.
///
/// Named so a test can reach it: it sits in the middle of a long form beside
/// half a dozen other text fields, and finding it by position would break the
/// first time a row moves.
const Key kRigField = Key('rig-field');

/// The reminders offered, as minutes before the job starts.
///
/// Apple's list, minus the ones a hauling day has no use for. Null is no
/// reminder at all; zero is "when it starts".
const List<(int?, String)> kAlertChoices = [
  (null, 'None'),
  (0, 'At the time'),
  (15, '15 min before'),
  (30, '30 min before'),
  (60, '1 hour before'),
  (120, '2 hours before'),
  (1440, '1 day before'),
];

String alertLabel(int? minutes) {
  for (final (value, label) in kAlertChoices) {
    if (value == minutes) return label;
  }
  return '$minutes min before';
}

/// Opens the editor over the calendar.
///
/// One form for both jobs: [job] null is a new one, [job] set is a correction.
/// Apple uses the same screen for New Event and Edit Event and so does this —
/// two forms that must stay in step is two forms that drift.
Future<bool> showEventEditor(
  BuildContext context, {
  Job? job,
  DateTime? startAt,
  bool allDay = false,
}) async {
  final cal = CalendarScope.read(context);
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CalendarScope(
        state: cal,
        child: EventEditor(job: job, startAt: startAt, allDay: allDay),
      ),
    ),
  );
  return saved ?? false;
}

class EventEditor extends StatefulWidget {
  const EventEditor({super.key, this.job, this.startAt, this.allDay = false});

  /// Null for a new job.
  final Job? job;

  /// Where the tap landed, for a new job booked by tapping the grid.
  final DateTime? startAt;
  final bool allDay;

  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  late final TextEditingController _customer;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _phone;
  late final TextEditingController _access;
  late final TextEditingController _billed;
  late final TextEditingController _dumpFee;

  /// The rigs the job needs. Order is the order they were picked in, which is
  /// the order somebody would say them out loud.
  late List<String> _rigs;

  late bool _allDay;
  late DateTime _starts;
  late int _minutes;
  Repeat _repeat = Repeat.never;
  int _times = 4;
  int? _alert;
  bool _saving = false;

  bool get _isNew => widget.job == null;

  @override
  void initState() {
    super.initState();
    final job = widget.job;

    _customer = TextEditingController(text: job?.customer ?? '');
    _address = TextEditingController(text: job?.address ?? '');
    _city = TextEditingController(text: job?.city ?? '');
    _phone = TextEditingController(text: job?.phone ?? '');
    _access = TextEditingController(text: job?.access ?? '');
    _rigs = [...?job?.equipment];
    // Empty rather than "0": a job nobody has priced has no price, and a
    // nought in the box says somebody decided on one.
    _billed = TextEditingController(
      text: (job?.billed ?? 0) == 0 ? '' : '${job!.billed}',
    );
    _dumpFee = TextEditingController(
      text: (job?.dumpFee ?? 0) == 0 ? '' : '${job!.dumpFee}',
    );

    final at = job?.scheduledFor ?? widget.startAt;
    // A job stored at midnight is a day booking with no time — the same rule
    // the calendar reads it by.
    _allDay = job == null
        ? widget.allDay
        : (at != null && at.hour == 0 && at.minute == 0);
    _starts = at ?? _nextRoundHour();
    _minutes = job?.minutes ?? kDefaultMinutes;
    _alert = job?.alertMinutes;
  }

  DateTime _nextRoundHour() {
    final now = CalendarScope.read(context).now;
    final next = DateTime(now.year, now.month, now.day, now.hour + 1);
    return next;
  }

  @override
  void dispose() {
    for (final c in [
      _customer,
      _address,
      _city,
      _phone,
      _access,
      _billed,
      _dumpFee,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get _ends => _starts.add(Duration(minutes: _minutes));

  /// Midnight on the chosen day for an all-day job, the exact moment otherwise.
  DateTime get _stored => _allDay ? dayOf(_starts) : _starts;

  Future<void> _save() async {
    if (_customer.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Give the job a customer.')));
      return;
    }
    // A job with nothing on the truck is a job nobody can load for, and the
    // rig is what the job is called — so without one there is nothing on the
    // calendar to read. Dispatch is the only one who knows, and this is the
    // moment they know it: a customer booking off the website cannot say,
    // which is why the rule lives on this form and not in the domain.
    if (_rigs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Say what rig the job needs.')),
      );
      return;
    }

    setState(() => _saving = true);
    final app = AppScope.read(context);

    // Ask the platform at the moment somebody actually wants a reminder,
    // rather than with a prompt on first launch that means nothing yet.
    if (_alert != null) await app.enableAlerts();
    final job = widget.job;

    final bool ok;
    if (job == null) {
      // A repeat writes a real job per occurrence rather than one job that
      // claims to happen six times. Each haul is its own piece of work with
      // its own driver, hours and photos — a virtual occurrence has nowhere
      // to put any of that.
      final when = repeatDates(
        _stored,
        _repeat,
        count: _repeat == Repeat.never ? 1 : _times,
      );
      var made = 0;
      for (final at in when) {
        final added = await app.addJob(
          customer: _customer.text,
          address: _address.text,
          city: _city.text,
          phone: _phone.text,
          access: _access.text,
          equipment: _rigs,
          billed: dollarsFrom(_billed.text),
          dumpFee: dollarsFrom(_dumpFee.text),
          scheduledFor: _allDay ? dayOf(at) : at,
          // An all-day job has no length to speak of.
          minutes: _allDay ? null : _minutes,
          alertMinutes: _alert,
        );
        if (added != null) made++;
      }
      ok = made > 0;
    } else {
      // Only what actually changed goes on the wire — see EditJob.
      ok = await app.editJob(job, {
        'customer': _customer.text.trim(),
        'address': _address.text.trim(),
        'city': _city.text.trim(),
        'phone': _phone.text.trim(),
        'access': _access.text.trim(),
        'equipment': _rigs,
        'billed': dollarsFrom(_billed.text),
        'dumpFee': dollarsFrom(_dumpFee.text),
        'scheduledFor': _stored.toUtc().toIso8601String(),
        'minutes': _allDay ? null : _minutes,
        'alertMinutes': _alert,
      });
    }

    if (!mounted) return;
    setState(() => _saving = false);
    // An edit that changed nothing reports false and is not a failure — the
    // form is still done with.
    Navigator.of(context).pop(ok || !_isNew);
  }

  Future<void> _delete() async {
    final job = widget.job;
    if (job == null) return;

    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this job?'),
        content: Text(
          '${job.title} for ${job.customer} on '
          '${longDay(job.scheduledFor ?? DateTime.now())}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    final app = AppScope.read(context);
    final gone = await app.deleteJob(job);
    if (!mounted) return;
    if (gone) {
      CalendarScope.read(context).closeEvent();
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);
    final job = widget.job;

    return Scaffold(
      backgroundColor: p.groupedBg,
      appBar: AppBar(
        backgroundColor: p.groupedBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: t.body.copyWith(color: p.accent)),
        ),
        leadingWidth: 88,
        centerTitle: true,
        title: Text(_isNew ? 'New Job' : 'Edit Job', style: t.navTitle),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _isNew ? 'Add' : 'Done',
              style: t.bodyStrong.copyWith(
                color: _saving ? p.tertiaryLabel : p.accent,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          FormGroup(
            children: [
              FormRow(
                label: 'Customer',
                controller: _customer,
                hint: 'Who the job is for',
                autofocus: _isNew,
              ),
              // In the same box as the kind of work, because they are one
              // decision: what the job is decides what has to be on the truck,
              // and a rig chosen three groups further down is a rig somebody
              // scrolls past.
              _RigRow(
                chosen: _rigs,
                onChanged: (rigs) => setState(() => _rigs = rigs),
              ),
            ],
          ),
          FormGroup(
            children: [
              FormRow(
                label: 'Address',
                controller: _address,
                hint: 'Where to go',
              ),
              FormRow(label: 'Town', controller: _city, hint: ''),
              FormRow(
                label: 'Phone',
                controller: _phone,
                hint: '',
                keyboard: TextInputType.phone,
              ),
            ],
          ),
          FormGroup(
            children: [
              _SwitchRow(
                label: 'All-day',
                value: _allDay,
                onChanged: (on) => setState(() => _allDay = on),
              ),
              _WhenRow(
                label: 'Starts',
                at: _starts,
                dateOnly: _allDay,
                onChanged: (picked) => setState(() => _starts = picked),
              ),
              if (!_allDay)
                _WhenRow(
                  label: 'Ends',
                  at: _ends,
                  dateOnly: false,
                  onChanged: (picked) => setState(() {
                    // Dragging the end before the start would make a block with
                    // negative height; a quarter hour is the floor everywhere
                    // else in the calendar too.
                    final span = picked.difference(_starts).inMinutes;
                    _minutes = span < 15 ? 15 : span;
                  }),
                ),
              // Only when booking. Changing the repeat on a job that already
              // exists would have to mean either this one or all of them, and
              // there is no series here to mean "all of them" — each booking
              // wrote its own real job.
              if (_isNew)
                _RepeatRow(
                  repeat: _repeat,
                  times: _times,
                  onRepeat: (r) => setState(() => _repeat = r),
                  onTimes: (n) => setState(() => _times = n),
                ),
              _AlertRow(
                minutes: _alert,
                onChanged: (m) => setState(() => _alert = m),
              ),
            ],
          ),
          // Whoever opens this form can already price — an owner. Guarded
          // anyway rather than assumed, so widening who may edit a job later
          // does not quietly hand out the money with it.
          if (app.canPriceJobs)
            FormGroup(
              children: [
                FormRow(
                  label: 'Bills at',
                  controller: _billed,
                  hint: 'What the customer pays',
                  prefix: '\$',
                  keyboard: TextInputType.number,
                ),
                FormRow(
                  label: 'Disposal',
                  controller: _dumpFee,
                  hint: 'What the tip charges',
                  prefix: '\$',
                  keyboard: TextInputType.number,
                ),
              ],
            ),
          FormGroup(
            children: [
              FormRow(
                label: 'Notes',
                controller: _access,
                hint: 'Gate codes, where not to back down',
                lines: 3,
              ),
            ],
          ),
          if (job != null && app.canDelete(job))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Semantics(
                  button: true,
                  label: 'Delete job',
                  onTap: _delete,
                  excludeSemantics: true,
                  child: TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(
                      'Delete Job',
                      style: t.body.copyWith(color: p.accent),
                    ),
                  ),
                ),
              ),
            ),
          if (job != null && !app.canDelete(job))
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
              child: Text(
                'This job has been worked, so it cannot be deleted. The log, '
                'the hours and the photos are the record of what happened.',
                textAlign: TextAlign.center,
                style: t.secondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// What has to be on the truck — one rig, or several.
///
/// The choices are the rigs the board has already asked for rather than a
/// fleet written into the app, and anything can be typed in. A yard that hires
/// a chipper for one week should be able to book the job that afternoon and
/// have it offered as a choice the next time.
///
/// The same menu as the others, ticking every rig the job needs rather than
/// one. It shuts after each pick, which costs a tap per extra rig — worth it
/// against a menu that opens without publishing a single thing a screen
/// reader can read, which is what the stay-open kind turned out to do.
///
/// Stated, never enforced — see the rig decision. Saying a job needs a lowboy
/// tells whoever takes it what to hook up; it does not stop anybody taking it.
class _RigRow extends StatefulWidget {
  const _RigRow({required this.chosen, required this.onChanged});

  final List<String> chosen;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_RigRow> createState() => _RigRowState();
}

class _RigRowState extends State<_RigRow> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _toggle(String rig) {
    final next = [...widget.chosen];
    if (!next.remove(rig)) next.add(rig);
    widget.onChanged(next);
  }

  /// Takes whatever is in the box as a rig of its own.
  void _addTyped() {
    final rig = _typed.text.trim();
    if (rig.isEmpty) return;
    // Case-insensitively already there: select it rather than making a second
    // entry that means the same thing.
    final existing = [
      ...widget.chosen,
      ...AppScope.read(context).knownRigs,
    ].where((r) => r.toLowerCase() == rig.toLowerCase());
    final name = existing.isEmpty ? rig : existing.first;

    _typed.clear();
    if (widget.chosen.any((r) => r.toLowerCase() == name.toLowerCase())) return;
    widget.onChanged([...widget.chosen, name]);
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    // Everything the board knows, plus anything on this job that is new to it.
    final offered = <String>[
      ...widget.chosen,
      ...AppScope.of(context).knownRigs.where(
        (r) => !widget.chosen.any((c) => c.toLowerCase() == r.toLowerCase()),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceRow<String>(
          label: 'Rig needed',
          shown: widget.chosen.isEmpty
              ? 'Pick at least one'
              : widget.chosen.join(', '),
          // Several at once, so every rig on the job carries a tick.
          ticked: widget.chosen.contains,
          choices: [for (final rig in offered) (rig, rig)],
          onChanged: _toggle,
          valueColour: widget.chosen.isEmpty ? p.tertiaryLabel : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              const SizedBox(width: 96),
              Expanded(
                child: Semantics(
                  textField: true,
                  label: 'Another rig',
                  child: TextField(
                    key: kRigField,
                    controller: _typed,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addTyped(),
                    style: t.body.copyWith(fontSize: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: offered.isEmpty
                          ? 'What it takes to do the job'
                          : 'Something else',
                      hintStyle: t.body.copyWith(
                        fontSize: 15,
                        color: p.tertiaryLabel,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ),
              // An icon, not the word "Add" — the form's own save button says
              // Add on a new job, and two buttons a thumb apart reading the
              // same word is how somebody books a job they meant to keep
              // typing into.
              Semantics(
                button: true,
                label: 'Add this rig',
                onTap: _addTyped,
                excludeSemantics: true,
                child: IconButton(
                  onPressed: _addTyped,
                  tooltip: 'Add this rig',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  icon: Icon(Icons.add_rounded, color: p.accent),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// When to be told about it.
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.minutes, required this.onChanged});

  final int? minutes;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);

    // Wrapped in a record because "no reminder" is a real choice whose value
    // is null, and a menu cannot tell a null selection from a dismissed menu.
    // A one-field record is never null, so both survive the round trip.
    return ChoiceRow<(int?,)>(
      label: 'Alert',
      shown: alertLabel(minutes),
      ticked: (choice) => choice == (minutes,),
      choices: [for (final (value, label) in kAlertChoices) ((value,), label)],
      onChanged: (choice) => onChanged(choice.$1),
      trailing: minutes == null
          ? null
          : Icon(Icons.notifications_active_rounded, size: 18, color: p.accent),
    );
  }
}

/// How often it comes back, and how many times.
class _RepeatRow extends StatelessWidget {
  const _RepeatRow({
    required this.repeat,
    required this.times,
    required this.onRepeat,
    required this.onTimes,
  });

  final Repeat repeat;
  final int times;
  final ValueChanged<Repeat> onRepeat;
  final ValueChanged<int> onTimes;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChoiceRow<Repeat>(
          label: 'Repeat',
          shown: repeat == Repeat.never
              ? repeat.label
              : '${repeat.label}, $times times',
          ticked: (rule) => rule == repeat,
          choices: [for (final rule in Repeat.values) (rule, rule.label)],
          onChanged: onRepeat,
        ),
        if (repeat != Repeat.never)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text('How many', style: t.secondary),
                ),
                Expanded(
                  child: Semantics(
                    slider: true,
                    value: '$times times',
                    child: Slider(
                      value: times.toDouble(),
                      min: 2,
                      max: 26,
                      divisions: 24,
                      label: '$times',
                      activeColor: p.accent,
                      onChanged: (v) => onTimes(v.round()),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.body.copyWith(fontSize: 15))),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: p.accent,
          ),
        ],
      ),
    );
  }
}

/// A moment, opened onto a wheel the way iOS does it.
class _WhenRow extends StatefulWidget {
  const _WhenRow({
    required this.label,
    required this.at,
    required this.dateOnly,
    required this.onChanged,
  });

  final String label;
  final DateTime at;
  final bool dateOnly;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_WhenRow> createState() => _WhenRowState();
}

class _WhenRowState extends State<_WhenRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final shown = widget.dateOnly
        ? longDay(widget.at)
        : '${longDay(widget.at)}  ${clockLabel(widget.at)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: '${widget.label}, $shown',
          onTap: () => setState(() => _open = !_open),
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(widget.label, style: t.secondary),
                  ),
                  Expanded(
                    child: Text(
                      shown,
                      style: t.body.copyWith(
                        fontSize: 15,
                        color: _open ? p.accent : p.label,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The wheel opens inline rather than in its own screen, so the thing
        // being changed stays on screen while you change it.
        if (_open)
          SizedBox(
            height: 190,
            // The wheel is told what to set its text in. Left alone it asks
            // for SF Pro by name, which exists on an Apple device and nowhere
            // else — so on the web the wheel spins with nothing written on it.
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: p.brightness,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: t.body.copyWith(fontSize: 19),
                ),
              ),
              child: CupertinoDatePicker(
                mode: widget.dateOnly
                    ? CupertinoDatePickerMode.date
                    : CupertinoDatePickerMode.dateAndTime,
                initialDateTime: widget.at,
                minuteInterval: 5,
                use24hFormat: false,
                onDateTimeChanged: widget.onChanged,
              ),
            ),
          ),
      ],
    );
  }
}
