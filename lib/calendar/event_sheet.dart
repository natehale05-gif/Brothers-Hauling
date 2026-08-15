import 'package:flutter/material.dart';

import '../data/seed_data.dart';
import '../models/job.dart';
import '../state/app_state.dart';
import 'calendar_state.dart';
import 'calendar_theme.dart';
import 'date_math.dart';
import 'event.dart';
import 'event_editor.dart';
import 'form_bits.dart';
import 'price_sheet.dart';

/// One job, opened from the calendar.
///
/// Apple's event detail is a sheet over the calendar rather than a new screen,
/// so the day you were looking at stays behind it. Same here — a dispatcher
/// checking an address should not lose their place in the week.
class EventSheet extends StatelessWidget {
  const EventSheet({super.key, required this.event});

  /// Null when the open job has gone — deleted underneath, or filtered out by
  /// hiding its calendar. The sheet closes itself rather than showing a blank.
  final CalendarEvent? event;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final cal = CalendarScope.of(context);
    final open = event;

    if (open == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => cal.closeEvent());
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: 'Job details',
        explicitChildNodes: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                button: true,
                label: 'Close',
                onTap: cal.closeEvent,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: cal.closeEvent,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                  maxWidth: 560,
                ),
                decoration: BoxDecoration(
                  color: p.groupedBg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                ),
                child: _Detail(event: open),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);
    final app = AppScope.of(context);
    final job = event.job;
    final worker = crewById(job.assignedTo);
    // How many controls the header carries, and how wide the words on them
    // grow, both move — so the room for a label is measured rather than
    // guessed at one screen size.
    final tight =
        MediaQuery.sizeOf(context).width <
        300 * MediaQuery.textScalerOf(context).scale(14) / 14;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: event.colour,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                // The kind of work gives way to the buttons on a narrow
                // screen at large text. The dot beside it is the same fact in
                // a shape that always fits, and the sheet says it again in
                // words a line further down.
                if (!tight)
                  Expanded(
                    child: Text(
                      event.calendar.label,
                      style: t.secondary.copyWith(color: event.colour),
                    ),
                  )
                else
                  const Spacer(),
                if (app.canPriceJobs)
                  _HeaderAction(
                    word: 'Price',
                    spoken: 'Price job',
                    icon: Icons.attach_money_rounded,
                    tight: tight,
                    onTap: () => showPriceSheet(context, job),
                  ),
                if (app.canEditJobs)
                  _HeaderAction(
                    word: 'Edit',
                    spoken: 'Edit job',
                    icon: Icons.edit_rounded,
                    tight: tight,
                    onTap: () => showEventEditor(context, job: job),
                  ),
                Semantics(
                  button: true,
                  label: 'Close',
                  onTap: cal.closeEvent,
                  excludeSemantics: true,
                  child: IconButton(
                    onPressed: cal.closeEvent,
                    tooltip: 'Close',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Icon(Icons.close_rounded, color: p.secondaryLabel),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 20),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    job.customer,
                    style: t.largeTitle.copyWith(fontSize: 26),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    event.allDay
                        ? '${longDay(event.start)} · all-day'
                        : '${longDay(event.start)} · '
                              '${timeRange(event.start, event.end)}',
                    style: t.secondary,
                  ),
                ),
                // Before the details, not after them. Who is on a job is the
                // first thing anybody opening it wants to know, and making
                // dispatch scroll past the material and the dump fee to
                // change it is the wrong way round.
                _WhoIsOnIt(job: job),
                // For the person who has it: where they are up to and the
                // button that moves it on.
                _WorkIt(job: job),
                // The photos are everybody's — see the class comment.
                _Photos(job: job),
                _Group(
                  rows: [
                    _Row(label: 'Job', value: job.id),
                    _Row(
                      label: 'Where',
                      value: job.city.isEmpty
                          ? job.address
                          : '${job.address}, ${job.city}',
                      // Tapping an address opens the phone's own maps app with
                      // directions in it. Reading a street name off a screen
                      // and typing it into another app is the sort of thing
                      // people do at the wheel.
                      onTap: () => app.openDirections(job),
                      spoken: 'Directions to',
                    ),
                    _Row(label: 'Window', value: job.window),
                    _Row(
                      label: 'Alert',
                      value: job.alertMinutes == null
                          ? ''
                          : alertLabel(job.alertMinutes),
                    ),
                    _Row(label: 'Contact', value: job.contact),
                    _Row(
                      label: 'Phone',
                      value: job.phone,
                      onTap: () => app.callCustomer(job),
                      spoken: 'Call',
                    ),
                  ],
                ),
                _Group(
                  rows: [
                    _Row(label: 'Material', value: job.material),
                    _Row(label: 'Volume', value: job.volume),
                    _Row(label: 'Weight', value: job.weight),
                    // Stated, never enforced — see the rig decision.
                    _Row(label: 'Rig needed', value: job.equipmentLabel),
                    _Row(label: 'Goes to', value: job.disposal),
                  ],
                ),
                _Group(
                  rows: [
                    _Row(
                      label: 'Status',
                      value: switch (job.status) {
                        JobStatus.requested => 'Booked, not priced',
                        JobStatus.open => 'Nobody on it yet',
                        JobStatus.active => kStages[job.stage],
                        JobStatus.done => 'Closed',
                      },
                    ),
                    _Row(label: 'Driver', value: worker?.name ?? 'Nobody yet'),
                    if (app.canSeeMoney)
                      _Row(
                        label: 'Bills at',
                        value: job.billed == 0
                            ? 'Not priced yet'
                            : '\$${job.billed}',
                      ),
                    if (app.canSeeMoney && job.dumpFee > 0)
                      _Row(label: 'Disposal', value: '\$${job.dumpFee}'),
                    // Only once both halves are known. "$395 before labour" on
                    // a job with no tip fee entered is the same number twice
                    // dressed up as arithmetic.
                    if (app.canSeeMoney && job.billed > 0 && job.dumpFee > 0)
                      _Row(
                        label: 'Before labour',
                        value: '\$${job.beforeLabour}',
                      ),
                  ],
                ),
                if (job.access.trim().isNotEmpty)
                  _Group(
                    rows: [_Row(label: 'Access', value: job.access)],
                  ),
                // Last, because it is the longest thing on the sheet and the
                // only part nobody needs before the job is under way.
                _TheLog(job: job),
                if (job.hazards.isNotEmpty)
                  _Group(
                    rows: [
                      for (final hazard in job.hazards)
                        _Row(label: 'Hazard', value: hazard, alert: true),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A word in the sheet's header, or the icon it falls back to.
///
/// Two words and a close button do not fit 320 points at large text, and a
/// header that overflows is worse than one that speaks in symbols. What a
/// screen reader hears does not change either way.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.word,
    required this.spoken,
    required this.icon,
    required this.tight,
    required this.onTap,
  });

  final String word;
  final String spoken;
  final IconData icon;
  final bool tight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Semantics(
      button: true,
      label: spoken,
      onTap: onTap,
      excludeSemantics: true,
      child: tight
          ? IconButton(
              onPressed: onTap,
              tooltip: spoken,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(icon, color: p.accent),
            )
          : TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              child: Text(
                word,
                style: t.body.copyWith(fontSize: 15, color: p.accent),
              ),
            ),
    );
  }
}

/// Who is on the job.
///
/// Dispatch decides, and that is the whole of it — there is no volunteering
/// off the board and no yes to wait for. A job with somebody's name on it is
/// theirs from the moment it is put there.
///
/// Only the owner and the drivers are offered: the crew share one login, so a
/// job assigned to it would be assigned to everybody at once and its hours
/// would belong to nobody.
class _WhoIsOnIt extends StatelessWidget {
  const _WhoIsOnIt({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);

    // Nothing goes out unpriced. Whoever can fix that is offered the way to.
    if (job.needsPricing) {
      if (!app.canPriceJobs) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
          child: Text(
            'Nobody goes out on this until it has a price. It came in from '
            'the website and dispatch has not been through it yet.',
            textAlign: TextAlign.center,
            style: t.secondary.copyWith(fontSize: 13),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              label:
                  'Put a price on it. It came in from the website and nobody '
                  'goes out on it until it has one.',
              onTap: () => showPriceSheet(context, job),
              excludeSemantics: true,
              child: FilledButton(
                onPressed: () => showPriceSheet(context, job),
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(
                  'Put a price on it',
                  style: t.bodyStrong.copyWith(fontSize: 16, color: p.onAccent),
                ),
              ),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Text(
                'It came in from the website and nobody goes out on it until '
                'it has one.',
                textAlign: TextAlign.center,
                style: t.secondary.copyWith(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (!app.canAssign) return const SizedBox.shrink();

    final who = crewById(job.assignedTo);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: ChoiceRow<(String?,)>(
        label: 'Driver',
        spokenLabel: 'Who is on this job',
        shown: who?.name ?? 'Nobody yet',
        ticked: (choice) => choice.$1 == job.assignedTo,
        valueColour: who == null ? p.tertiaryLabel : p.label,
        choices: [
          (const (null,), 'Nobody yet'),
          for (final member in app.assignable) ((member.id,), member.name),
        ],
        // The empty string is how the board says "take it back off them" —
        // see AssignJob. Wrapped in a one-field record because a menu cannot
        // tell a null choice from a dismissed menu.
        onChanged: (choice) => app.assign(job, choice.$1 ?? ''),
      ),
    );
  }
}

/// The before and after shots, for anybody at all.
///
/// Deliberately not narrowed to the driver whose job it is. Half the work on a
/// site is done by whoever came along on the shared login, and the person
/// standing next to the pile with a phone out is the person who should be
/// taking the picture. Making them hand the job over first is how a site ends
/// up with no before shot and an argument three weeks later.
class _Photos extends StatelessWidget {
  const _Photos({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final app = AppScope.of(context);

    // Nothing to photograph until the job is real work. A website booking
    // nobody has priced has no site to stand on yet.
    if (job.needsPricing) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: _PhotoSlot(
                job: job,
                before: true,
                // Before the first load goes on. Once it does, the state of
                // the site beforehand is gone for good.
                due: app.beforePhotoDue(job),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _PhotoSlot(job: job, before: false)),
          ],
        ),
      ),
    );
  }
}

/// Running a job: the stage and the way on.
///
/// Only for the person the job belongs to. An owner watching from the office
/// can see where it has got to on the Status row, but the log and the hours
/// are the record of what a driver actually did — and a record somebody else
/// can fill in from a desk is not one. The photos are the exception, and they
/// are handled above.
class _WorkIt extends StatelessWidget {
  const _WorkIt({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);

    final mine = job.assignedTo == app.meId;
    if (!mine || job.status != JobStatus.active) return const SizedBox.shrink();

    final closing = job.stage == kStages.length - 2;
    // The one rule the photos exist for. Said before the button is pressed
    // rather than as a complaint afterwards.
    final blocked = closing && !job.photosComplete;
    final action = kStageActions[job.stage];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MergeSemantics(
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text('Up to', style: t.secondary),
                      ),
                      Expanded(
                        child: Text(
                          kStages[job.stage],
                          style: t.bodyStrong.copyWith(fontSize: 16),
                        ),
                      ),
                      Text(
                        '${job.stage + 1} of ${kStages.length}',
                        style: t.secondary.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            enabled: !blocked,
            label: blocked
                ? 'Close it out. Blocked: a before and an after photo have '
                      'to be on the job first.'
                : action,
            onTap: blocked ? null : () => app.advance(job),
            excludeSemantics: true,
            child: FilledButton(
              onPressed: blocked ? null : () => app.advance(job),
              style: FilledButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: p.onAccent,
                disabledBackgroundColor: p.fill,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                action,
                style: t.bodyStrong.copyWith(
                  fontSize: 16,
                  color: blocked ? p.tertiaryLabel : p.onAccent,
                ),
              ),
            ),
          ),
          if (blocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: ExcludeSemantics(
                child: Text(
                  'Both photos have to be on the job before it can be closed. '
                  'They are what settles an argument about the site weeks '
                  'later.',
                  textAlign: TextAlign.center,
                  style: t.secondary.copyWith(fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One of the two photo slots — the shot if there is one, the way to take it
/// if there is not.
class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({required this.job, required this.before, this.due = false});

  final Job job;
  final bool before;

  /// The driver is standing on site and this shot is still missing. Says so
  /// rather than waiting to refuse the close-out an hour later.
  final bool due;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);

    final shots = before ? job.photosBefore : job.photosAfter;
    final word = before ? 'Before' : 'After';
    final label = shots.isEmpty
        ? 'Take the $word photo'
        : 'Add another $word photo. ${shots.length} filed.';

    return Semantics(
      button: true,
      label: due ? '$label Needed now — you are on site.' : label,
      onTap: () => app.addPhoto(job, before: before),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => app.addPhoto(job, before: before),
        child: Container(
          height: 92,
          decoration: BoxDecoration(
            color: p.fill,
            borderRadius: BorderRadius.circular(8),
            border: due ? Border.all(color: p.accent, width: 2) : null,
            image: shots.isEmpty
                ? null
                : DecorationImage(
                    image: MemoryImage(shots.first.bytes),
                    fit: BoxFit.cover,
                  ),
          ),
          child: Stack(
            children: [
              if (shots.isEmpty)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.photo_camera_rounded,
                        size: 20,
                        color: due ? p.accent : p.secondaryLabel,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        word,
                        style: t.secondary.copyWith(
                          fontSize: 13,
                          color: due ? p.accent : p.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              // Over the photo, because the photo is the background: a count
              // on a coloured strip is readable whatever was in front of the
              // lens.
              if (shots.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Text(
                      shots.length == 1 ? word : '$word · ${shots.length}',
                      style: t.eventTitle.copyWith(color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What happened on the job, and when.
///
/// Written all along by the mutations that move a job — accepted, left the
/// yard, arrived, closed — and until now read by nothing. It is the answer to
/// "what time did they get there", which is the question a customer rings
/// about, and it is the one part of a job nobody types.
class _TheLog extends StatelessWidget {
  const _TheLog({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    if (job.events.isEmpty) return const SizedBox.shrink();

    // Newest last: a log is read down the way the day happened.
    final entries = [...job.events]..sort((a, b) => a.at.compareTo(b.at));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('What happened', style: t.secondary),
            ),
            for (var i = 0; i < entries.length; i++)
              MergeSemantics(
                // The rail's connector runs the height of the row, and a row
                // in a list has no height to run to until something measures
                // it. A handful of entries is cheap to measure twice.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // A rail down the left, the way a timeline reads: the dot
                      // is the moment, the line is the gap to the next one.
                      SizedBox(
                        width: 14,
                        child: Column(
                          children: [
                            const SizedBox(height: 5),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: switch (entries[i].kind) {
                                  EventKind.depart => p.accent,
                                  EventKind.arrive => p.accent,
                                  EventKind.flat => p.tertiaryLabel,
                                },
                                shape: BoxShape.circle,
                              ),
                            ),
                            if (i < entries.length - 1)
                              Expanded(
                                child: Container(width: 1, color: p.hairline),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 68,
                        child: Text(
                          entries[i].time,
                          style: t.secondary.copyWith(fontSize: 13),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: i < entries.length - 1 ? 10 : 0,
                          ),
                          child: Text(
                            entries[i].label,
                            style: t.body.copyWith(fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// An inset grouped table, the way iOS draws one.
class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final shown = rows.where((r) => r.value.trim().isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              shown[i],
              if (i < shown.length - 1)
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

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.alert = false,
    this.onTap,
    this.spoken,
  });

  final String label;
  final String value;
  final bool alert;

  /// Set on the rows that hand off to the phone — the address to maps, the
  /// number to the dialler. A row without one is a fact, not a control, and
  /// is not announced as a button.
  final VoidCallback? onTap;

  /// What the tap does, said before the value: "Call, 541-555-0148".
  final String? spoken;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final tappable = onTap != null;

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(label, style: t.secondary)),
          Expanded(
            child: Text(
              value,
              style: t.body.copyWith(
                fontSize: 15,
                // A tappable row is drawn in the accent colour, the way every
                // other link in the app is. There is no other way to tell.
                color: alert || tappable ? p.accent : p.label,
              ),
            ),
          ),
          if (tappable)
            Icon(
              label == 'Phone' ? Icons.phone_rounded : Icons.directions_rounded,
              size: 18,
              color: p.accent,
            ),
        ],
      ),
    );

    if (!tappable) return MergeSemantics(child: row);

    return Semantics(
      button: true,
      label: '${spoken ?? label}, $value',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}
