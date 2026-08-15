import 'package:flutter/material.dart';

import '../models/crew_member.dart';
import '../models/job.dart';
import '../state/app_state.dart';
import 'calendar_state.dart';
import 'calendar_theme.dart';
import 'date_math.dart';
import 'event.dart';

/// The width one rig's lane gets before the sheet starts scrolling sideways.
///
/// Four columns of numbers and a line of address have to fit; below this the
/// address wraps to four words a line and the lane stops being readable.
const double kLaneWidth = 300;

/// How wide the whole window has to be before the lanes sit side by side.
const double kSideBySide = 760;

/// One day of work, laid out the way the yard's paper sheet is.
///
/// A lane per rig, a row per job, and what each one owes at the foot of it —
/// the same shape the office has been keeping by hand. Everything on it is
/// read off the board: nothing here is a second copy of a job that could
/// disagree with the calendar.
///
/// For an owner or a manager. It is a money document, and it uses the same
/// rule as every other figure in the app.
Future<void> showDaySheet(BuildContext context) {
  final cal = CalendarScope.read(context);
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CalendarScope(state: cal, child: const DaySheetScreen()),
    ),
  );
}

/// One lane of the sheet: a rig, and the work that needs it.
class Lane {
  const Lane({required this.rig, required this.jobs, required this.colour});

  final String rig;
  final List<Job> jobs;
  final Color colour;

  /// What this lane is still owed. The figure the foot of the column carries.
  int get owed => jobs.fold(0, (sum, job) => sum + job.owes);
}

/// The lanes for [day], in the order the board learned the rigs.
///
/// A job that needs two rigs appears under both, because it occupies both —
/// that is the whole point of a sheet somebody loads a yard from, and it is
/// why the lane totals are not added together anywhere.
List<Lane> lanesFor(AppState app, DateTime day) {
  final onDay = [
    for (final job in app.jobs)
      if (job.scheduledFor case final at?)
        if (sameDay(at, day)) job,
  ]..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!));

  final rigs = <String>[];
  for (final job in onDay) {
    for (final rig in job.equipment) {
      if (!rigs.contains(rig)) rigs.add(rig);
    }
  }
  rigs.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return [
    for (var i = 0; i < rigs.length; i++)
      Lane(
        rig: rigs[i],
        jobs: [
          for (final job in onDay)
            if (job.equipment.contains(rigs[i])) job,
        ],
        // The rig's own colour, so a lane here and a block on the day view
        // are the same colour for the same trailer.
        colour: WorkCalendar(rigs[i]).colour,
      ),
  ];
}

/// Whoever has a job in hand on [day] — the sheet's last column.
List<CrewMember> workingOn(AppState app, DateTime day) {
  final ids = <String>{
    for (final job in app.jobs)
      if (job.scheduledFor case final at?)
        if (sameDay(at, day)) ?job.assignedTo,
  };
  return [
    for (final member in app.crew)
      if (ids.contains(member.id)) member,
  ];
}

class DaySheetScreen extends StatelessWidget {
  const DaySheetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);
    final cal = CalendarScope.of(context);
    final day = cal.selected;
    final lanes = lanesFor(app, day);

    return Scaffold(
      backgroundColor: p.groupedBg,
      appBar: AppBar(
        backgroundColor: p.groupedBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 8,
        title: Text('Day sheet', style: t.navTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done', style: t.body.copyWith(color: p.accent)),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WhichDay(day: day),
          Expanded(
            child: lanes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Nothing booked for this day.',
                        textAlign: TextAlign.center,
                        style: t.secondary,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      // Wide enough for two lanes side by side and it reads
                      // like the paper sheet. Narrower and it stacks, because
                      // four columns of figures inside a phone's width is a
                      // table nobody can read on a truck bonnet.
                      final across = box.maxWidth >= kSideBySide;
                      return across
                          ? _Across(lanes: lanes, day: day)
                          : _Down(lanes: lanes, day: day);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The day the sheet is for, and the way to the one either side of it.
class _WhichDay extends StatelessWidget {
  const _WhichDay({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.separator, width: 0.5)),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'The day before',
            onTap: () => cal.select(day.subtract(const Duration(days: 1))),
            excludeSemantics: true,
            child: IconButton(
              onPressed: () =>
                  cal.select(day.subtract(const Duration(days: 1))),
              tooltip: 'The day before',
              icon: Icon(Icons.chevron_left_rounded, color: p.accent),
            ),
          ),
          Expanded(
            child: Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                longDay(day),
                textAlign: TextAlign.center,
                style: t.bodyStrong.copyWith(fontSize: 16),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'The day after',
            onTap: () => cal.select(day.add(const Duration(days: 1))),
            excludeSemantics: true,
            child: IconButton(
              onPressed: () => cal.select(day.add(const Duration(days: 1))),
              tooltip: 'The day after',
              icon: Icon(Icons.chevron_right_rounded, color: p.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// The paper layout: a column per rig, side by side, scrolling sideways when
/// there are more rigs than window.
class _Across extends StatelessWidget {
  const _Across({required this.lanes, required this.day});

  final List<Lane> lanes;
  final DateTime day;

  /// How wide the crew column is. Names and a unit number, no more.
  static const double _crewWidth = 220;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // Twelve of padding either side, twelve between every column.
        final gaps = 24 + 12 * lanes.length;
        final spare = box.maxWidth - gaps - _crewWidth;
        // Share out whatever room is going, but never squeeze a lane below
        // the width its four columns need — past that the sheet scrolls.
        final width = (spare / lanes.length).clamp(kLaneWidth, double.infinity);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            // As tall as the window, so every lane's total sits on the same
            // line at the foot of the page — the way the paper sheet rules it.
            constraints: BoxConstraints(minHeight: box.maxHeight - 24),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final lane in lanes) ...[
                    SizedBox(
                      width: width,
                      child: _LaneColumn(lane: lane, footAtTheBottom: true),
                    ),
                    const SizedBox(width: 12),
                  ],
                  SizedBox(
                    width: _crewWidth,
                    child: _WhosWorking(day: day),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The same sheet on a phone: one lane after another, each keeping its own
/// heading and its own total.
class _Down extends StatelessWidget {
  const _Down({required this.lanes, required this.day});

  final List<Lane> lanes;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final lane in lanes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LaneColumn(lane: lane),
          ),
        _WhosWorking(day: day),
      ],
    );
  }
}

/// One rig's column: its name, its work, and what it is owed.
class _LaneColumn extends StatelessWidget {
  const _LaneColumn({required this.lane, this.footAtTheBottom = false});

  final Lane lane;

  /// Whether the total drops to the foot of a stretched column.
  ///
  /// Only true where the lanes are given a height to fill — side by side. In
  /// a stacked list the column has no height of its own to push against, and
  /// a total floating below its own lane would belong to nothing.
  final bool footAtTheBottom;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The heading carries the rig's colour the way the paper sheet
          // carries a filled band.
          Container(
            decoration: BoxDecoration(
              color: lane.colour,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Semantics(
              header: true,
              // A node of its own, said plainly: without this the heading is
              // folded into whichever row happens to sit next to it, and the
              // rig the lane is for stops being announced at all.
              container: true,
              label:
                  '${lane.rig}. ${lane.jobs.length} '
                  '${lane.jobs.length == 1 ? 'job' : 'jobs'}.',
              excludeSemantics: true,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      lane.rig,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyStrong.copyWith(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Text(
                    '${lane.jobs.length}',
                    style: t.bodyStrong.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const _LaneHeader(),
          for (var i = 0; i < lane.jobs.length; i++) ...[
            if (i > 0) Divider(height: 0.5, thickness: 0.5, color: p.hairline),
            _JobRow(job: lane.jobs[i]),
          ],
          if (footAtTheBottom) const Spacer(),
          Container(
            decoration: BoxDecoration(
              color: p.fill,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(9),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: MergeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Still owed',
                      style: t.secondary.copyWith(fontSize: 13),
                    ),
                  ),
                  Text(
                    '\$${lane.owed}',
                    style: t.bodyStrong.copyWith(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The column names, once per lane, the way the sheet rules them.
class _LaneHeader extends StatelessWidget {
  const _LaneHeader();

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final style = t.secondary.copyWith(fontSize: 11);

    return Container(
      decoration: BoxDecoration(
        color: p.groupedBg,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(width: 58, child: Text('Time', style: style)),
            SizedBox(width: 56, child: Text('Owes', style: style)),
            Expanded(child: Text('Customer · paid by', style: style)),
          ],
        ),
      ),
    );
  }
}

/// One job on the sheet, and the way into it.
class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    final at = job.scheduledFor;
    // Midnight is how a day-only booking is stored — see the calendar.
    final time = at == null
        ? ''
        : (at.hour == 0 && at.minute == 0 ? 'All day' : clockLabel(at));
    final method = job.paymentMethod.trim();
    final where = job.city.isEmpty ? job.address : job.city;

    return Semantics(
      button: true,
      label:
          // Not the rig: the lane's own heading has just said it.
          '${job.customer}. '
          '${time.isEmpty ? '' : '$time. '}'
          '${job.owes == 0 ? 'Settled.' : 'Owes \$${job.owes}.'}'
          '${method.isEmpty ? '' : ' Paid by $method.'}',
      onTap: () {
        Navigator.of(context).pop();
        cal.openEvent(job.id);
      },
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).pop();
          cal.openEvent(job.id);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 58,
                child: Text(time, style: t.secondary.copyWith(fontSize: 13)),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  job.owes == 0 ? '—' : '\$${job.owes}',
                  style: t.body.copyWith(
                    fontSize: 14,
                    // Nothing outstanding is not worth the ink of a figure;
                    // something outstanding is the point of the sheet.
                    color: job.owes == 0 ? p.tertiaryLabel : p.label,
                    fontWeight: job.owes == 0
                        ? FontWeight.w400
                        : FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      [
                        if (method.isNotEmpty) method,
                        if (where.isNotEmpty) where,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.secondary.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The last column of the sheet: who is on today, and what they have.
class _WhosWorking extends StatelessWidget {
  const _WhosWorking({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);
    final crew = workingOn(app, day);

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: p.label,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Semantics(
              header: true,
              container: true,
              child: Text(
                "Who's working",
                style: t.bodyStrong.copyWith(fontSize: 16, color: p.bg),
              ),
            ),
          ),
          if (crew.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Nobody has taken any of it yet.',
                style: t.secondary.copyWith(fontSize: 13),
              ),
            ),
          for (final member in crew)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.fill,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        member.initials.isEmpty
                            ? initialsFor(member.name)
                            : member.initials,
                        style: t.secondary.copyWith(fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        member.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.body.copyWith(fontSize: 14),
                      ),
                    ),
                    if (member.unit.isNotEmpty)
                      Text(
                        member.unit,
                        style: t.secondary.copyWith(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
