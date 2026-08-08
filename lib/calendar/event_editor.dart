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
import 'event.dart';

/// How long a new job runs unless somebody says otherwise.
const int kDefaultMinutes = 120;

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
  late final TextEditingController _equipment;
  late final TextEditingController _kind;

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
    _equipment = TextEditingController(text: job?.equipment ?? '');
    _kind = TextEditingController(text: job?.type ?? '');

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
      _equipment,
      _kind,
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

    setState(() => _saving = true);
    final app = AppScope.read(context);

    // Ask the platform at the moment somebody actually wants a reminder,
    // rather than with a prompt on first launch that means nothing yet.
    if (_alert != null) await app.enableAlerts();
    final job = widget.job;
    final kind = _kind.text.trim().isEmpty ? 'Other work' : _kind.text.trim();

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
          type: kind,
          customer: _customer.text,
          address: _address.text,
          city: _city.text,
          phone: _phone.text,
          access: _access.text,
          equipment: _equipment.text,
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
        'type': kind,
        'customer': _customer.text.trim(),
        'address': _address.text.trim(),
        'city': _city.text.trim(),
        'phone': _phone.text.trim(),
        'access': _access.text.trim(),
        'equipment': _equipment.text.trim(),
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
          '${job.type} for ${job.customer} on '
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
          _Group(
            children: [
              _FieldRow(
                label: 'Customer',
                controller: _customer,
                hint: 'Who the job is for',
                autofocus: _isNew,
              ),
              _KindRow(controller: _kind, onChanged: () => setState(() {})),
            ],
          ),
          _Group(
            children: [
              _FieldRow(
                label: 'Address',
                controller: _address,
                hint: 'Where to go',
              ),
              _FieldRow(label: 'Town', controller: _city, hint: ''),
              _FieldRow(
                label: 'Phone',
                controller: _phone,
                hint: '',
                keyboard: TextInputType.phone,
              ),
            ],
          ),
          _Group(
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
          _Group(
            children: [
              _FieldRow(
                label: 'Rig needed',
                controller: _equipment,
                // Stated, never enforced — see the rig decision.
                hint: 'What it takes to do the job',
              ),
              _FieldRow(
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

/// An inset grouped table, the way iOS draws one.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: p.hairline,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.lines = 1,
    this.autofocus = false,
    this.keyboard,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final int lines;
  final bool autofocus;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SizedBox(width: 96, child: Text(label, style: t.secondary)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              maxLines: lines,
              minLines: 1,
              keyboardType: keyboard,
              textCapitalization: TextCapitalization.sentences,
              style: t.body.copyWith(fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: t.body.copyWith(
                  fontSize: 15,
                  color: p.tertiaryLabel,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The kind of work, typed or picked.
///
/// Free text with the known kinds offered, rather than a closed list: the
/// colour a job gets is matched off this string, and a yard that starts doing
/// something new should be able to book it the same afternoon.
class _KindRow extends StatelessWidget {
  const _KindRow({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = CalText.of(context);
    final chosen = WorkCalendar.values.firstWhere(
      (c) => c.label.toLowerCase() == controller.text.trim().toLowerCase(),
      orElse: () => WorkCalendar.other,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: SizedBox(
                width: 96,
                child: Text('Kind', style: t.secondary),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: TextField(
                  controller: controller,
                  onChanged: (_) => onChanged(),
                  style: t.body.copyWith(fontSize: 15, color: chosen.colour),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'What kind of work',
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final calendar in WorkCalendar.values)
                if (calendar != WorkCalendar.other)
                  Semantics(
                    button: true,
                    selected: chosen == calendar,
                    label: '${calendar.label} calendar',
                    onTap: () {
                      controller.text = calendar.label;
                      onChanged();
                    },
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () {
                        controller.text = calendar.label;
                        onChanged();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: calendar.colour.withValues(
                            alpha: chosen == calendar ? 1 : 0.16,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          calendar.label,
                          style: t.eventTitle.copyWith(
                            fontSize: 12,
                            color: chosen == calendar
                                ? Colors.white
                                : calendar.colour,
                          ),
                        ),
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

/// When to be told about it.
class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.minutes, required this.onChanged});

  final int? minutes;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              SizedBox(width: 96, child: Text('Alert', style: t.secondary)),
              Expanded(
                child: Text(
                  alertLabel(minutes),
                  style: t.body.copyWith(fontSize: 15),
                ),
              ),
              if (minutes != null)
                Icon(
                  Icons.notifications_active_rounded,
                  size: 18,
                  color: p.accent,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in kAlertChoices)
                Semantics(
                  button: true,
                  selected: value == minutes,
                  label: 'Alert $label',
                  onTap: () => onChanged(value),
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => onChanged(value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: value == minutes ? p.accent : p.fill,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        label,
                        style: t.eventTitle.copyWith(
                          fontSize: 12,
                          color: value == minutes ? p.onAccent : p.label,
                        ),
                      ),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              SizedBox(width: 96, child: Text('Repeat', style: t.secondary)),
              Expanded(
                child: Text(
                  repeat == Repeat.never
                      ? repeat.label
                      : '${repeat.label}, $times times',
                  style: t.body.copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rule in Repeat.values)
                Semantics(
                  button: true,
                  selected: rule == repeat,
                  label: rule.label,
                  onTap: () => onRepeat(rule),
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: () => onRepeat(rule),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: rule == repeat ? p.accent : p.fill,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        rule.label,
                        style: t.eventTitle.copyWith(
                          fontSize: 12,
                          color: rule == repeat ? p.onAccent : p.label,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
