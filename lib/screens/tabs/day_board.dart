import 'package:flutter/material.dart';

import '../../models/job.dart';
import '../../state/app_state.dart';
import '../../theme/haul_theme.dart';
import '../../widgets/primitives.dart';

/// How far either side of today the view can be paged.
///
/// Bounded rather than infinite so the page controller has a real index, and
/// so "swipe forever" cannot quietly become "lost in 2043 with no way back".
const int kDayRange = 180;

/// Every job for one day, on a grid, with the days either side a swipe away.
///
/// Two ways to move on purpose. A phone gets the swipe, because that is what a
/// thumb does. A desktop gets arrows and the left/right keys, because a mouse
/// has nothing to swipe with — dragging a page sideways with a trackpad is
/// possible but nobody discovers it, and a keyboard user cannot do it at all.
class DayBoard extends StatefulWidget {
  const DayBoard({
    super.key,
    this.selectedJobId,
    this.only,
    this.pinned,
    this.tile,
    this.emptyMessage = 'Swipe or use the arrows to look at another day.',
  });

  final String? selectedJobId;

  /// Which jobs this view is about. Null means every job, which is the
  /// dispatcher's day. A driver's board narrows it to what they can take on.
  final bool Function(Job job)? only;

  /// Shown above the day bar, on every day.
  ///
  /// For the things that are not about a day at all and must not be swiped
  /// past: a booking waiting to be priced, a job pushed to a driver that wants
  /// an answer now.
  final Widget? pinned;

  /// What one cell of the grid is.
  ///
  /// Null gives the compact planning tile. A board somebody has to act on
  /// passes the full job card instead, so the day layout does not cost the
  /// driver the hold-to-volunteer control that is the whole point of it.
  final Widget Function(Job job, bool selected)? tile;

  final String emptyMessage;

  @override
  State<DayBoard> createState() => _DayBoardState();
}

class _DayBoardState extends State<DayBoard> {
  PageController? _pages;
  int _lastOffset = 0;

  PageController _controllerFor(int offset) {
    final existing = _pages;
    if (existing != null) return existing;
    return _pages = PageController(initialPage: offset + kDayRange);
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  void _goTo(int offset) {
    final controller = _pages;
    final page = offset + kDayRange;
    if (controller == null || !controller.hasClients) return;
    // Neighbouring days animate; "jump back to today" from three weeks out
    // does not, because a two-second blur past twenty days is not navigation.
    if ((offset - _lastOffset).abs() <= 1) {
      controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpToPage(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final offset = state.dayOffset;
    final controller = _controllerFor(offset);

    // The state is the source of truth for which day is showing; the arrows
    // and the keyboard change it, and the pager is brought into line here.
    if (offset != _lastOffset) {
      final previous = _lastOffset;
      _lastOffset = offset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final page = _pages?.hasClients ?? false ? _pages!.page?.round() : null;
        if (page != offset + kDayRange) {
          _lastOffset = previous;
          _goTo(offset);
          _lastOffset = offset;
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The day bar is navigation, so it stays put. Everything else lives
        // inside the page's own scroll — a pinned band with a fixed share of
        // the height overflows the moment the day bar grows at large text on a
        // short screen, and there is no share that is right for every device.
        _DayBar(offset: offset, only: widget.only),
        const SizedBox(height: 12),
        Expanded(
          child: PageView.builder(
            controller: controller,
            itemCount: kDayRange * 2 + 1,
            onPageChanged: (page) {
              _lastOffset = page - kDayRange;
              state.showDay(page - kDayRange);
            },
            itemBuilder: (context, page) => _DayPage(
              offset: page - kDayRange,
              selectedJobId: widget.selectedJobId,
              only: widget.only,
              tile: widget.tile,
              header: widget.pinned,
              emptyMessage: widget.emptyMessage,
            ),
          ),
        ),
      ],
    );
  }
}

/// The date, the arrows, and the way back to today.
class _DayBar extends StatelessWidget {
  const _DayBar({required this.offset, this.only});

  final int offset;
  final bool Function(Job job)? only;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final day = state.dayFor(offset);
    // Counts what this view is about, not what the day holds — "3 jobs" over a
    // board showing one would be a lie in the heading.
    final count = state.jobsOn(day, only: only).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border.all(color: hc.line),
        borderRadius: BorderRadius.circular(HaulSpace.radius),
      ),
      child: Row(
        children: [
          HaulIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: 'Show ${describeDay(state, offset - 1)}',
            onPressed: () => state.stepDay(-1),
          ),
          Expanded(
            child: Semantics(
              // One announcement for the whole heading: a screen reader user
              // wants "Tuesday 5 August, 3 jobs", not four fragments.
              header: true,
              liveRegion: true,
              label:
                  '${describeDay(state, offset)}, '
                  '${count == 1 ? '1 job' : '$count jobs'}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      relativeDayLabel(offset).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: ht.eyebrow.copyWith(
                        color: offset == 0 ? hc.brand : hc.inkSoft,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      formatDay(day),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: ht.sectionTitle,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (offset != 0)
            Semantics(
              button: true,
              label: 'Back to today',
              onTap: state.showToday,
              excludeSemantics: true,
              child: TextButton(
                onPressed: state.showToday,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, HaulSpace.tap),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: hc.brand,
                ),
                child: Text(
                  'TODAY',
                  style: ht.action.copyWith(fontSize: 11, color: hc.brand),
                ),
              ),
            ),
          HaulIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Show ${describeDay(state, offset + 1)}',
            onPressed: () => state.stepDay(1),
          ),
        ],
      ),
    );
  }
}

class _DayPage extends StatelessWidget {
  const _DayPage({
    required this.offset,
    required this.emptyMessage,
    this.selectedJobId,
    this.only,
    this.tile,
    this.header,
  });

  final int offset;
  final String emptyMessage;
  final String? selectedJobId;
  final bool Function(Job job)? only;
  final Widget Function(Job job, bool selected)? tile;

  /// Shown above the grid on every day — the things that are not about a day
  /// at all and must not be swiped past.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final day = state.dayFor(offset);
    final jobs = state.jobsOn(day, only: only);
    final loose = offset == 0
        ? state.unscheduledJobs.where(only ?? (_) => true).toList()
        : const <Job>[];

    if (jobs.isEmpty && loose.isEmpty) {
      // A day view can hide work rather than lose it. Saying how much is
      // sitting on other days is the difference between an empty screen and a
      // driver who never finds out Thursday is full.
      final elsewhere = state.jobs
          .where((j) => (only?.call(j) ?? true) && j.scheduledDay != day)
          .length;
      final empty = EmptyState(
        title: 'Nothing on ${relativeDayLabel(offset).toLowerCase()}',
        message: elsewhere == 0
            ? emptyMessage
            : '${elsewhere == 1 ? '1 job' : '$elsewhere jobs'} on other days. '
                  '$emptyMessage',
      );
      if (header == null) return empty;
      return ListView(padding: EdgeInsets.zero, children: [header!, empty]);
    }

    // Compact planning tiles unless the caller wants real cards.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final build =
        tile ??
        (Job job, bool selected) => SizedBox(
          height: 150 * scale,
          child: _DayTile(job: job, selected: selected),
        );

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ?header,
        if (jobs.isNotEmpty)
          _Grid(jobs: jobs, selectedJobId: selectedJobId, tile: build)
        else
          const EmptyState(
            title: 'Nothing booked in',
            message: 'The jobs below have not been given a day yet.',
          ),
        if (loose.isNotEmpty) ...[
          const SizedBox(height: 6),
          const SectionHeader(title: 'No day set', topPadding: 10),
          _Grid(jobs: loose, selectedJobId: selectedJobId, tile: build),
        ],
      ],
    );
  }
}

/// The grid itself.
///
/// Sized by a maximum tile width rather than a fixed column count, so the same
/// widget is one column on a phone and four across a desktop window without
/// anybody hard-coding breakpoints.
class _Grid extends StatelessWidget {
  const _Grid({required this.jobs, required this.tile, this.selectedJobId});

  final List<Job> jobs;
  final String? selectedJobId;

  /// What one cell is. The dispatcher's day gets a compact tile; a board
  /// somebody has to act on gets the full card, buttons and all.
  final Widget Function(Job job, bool selected) tile;

  @override
  Widget build(BuildContext context) {
    // Wrap rather than GridView: a card sizes itself, and a fixed-extent cell
    // would either clip it or leave a hole under it at large text.
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        // Wide enough that a phone gets a single readable column and a desktop
        // window gets three or four, without either being a breakpoint.
        final columns = (constraints.maxWidth / 420).floor().clamp(1, 4);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final job in jobs)
              SizedBox(width: width, child: tile(job, job.id == selectedJobId)),
          ],
        );
      },
    );
  }
}

/// One job, compressed to what you need to plan a day: when, what, where, who.
class _DayTile extends StatelessWidget {
  const _DayTile({required this.job, required this.selected});

  final Job job;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final worker = state.crew.where((c) => c.id == job.assignedTo).firstOrNull;

    final when = job.scheduledFor == null
        ? 'No day set'
        : formatClock(job.scheduledFor!);
    final who = worker?.name ?? 'Nobody yet';

    return Semantics(
      button: true,
      selected: selected,
      label:
          '$when, ${job.type}, ${job.customer}'
          '${job.city.isEmpty ? '' : ' in ${job.city}'}. '
          '${worker == null ? 'Not staffed.' : 'Run by $who.'}',
      onTap: () => state.openJobCard(job),
      excludeSemantics: true,
      child: Material(
        color: hc.surface,
        borderRadius: BorderRadius.circular(HaulSpace.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => state.openJobCard(job),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? hc.brand : hc.line),
              borderRadius: BorderRadius.circular(HaulSpace.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      when,
                      style: ht.mono.copyWith(color: hc.brand, fontSize: 13),
                    ),
                    const Spacer(),
                    _StatusDot(job: job),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  job.type.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ht.sectionTitle,
                ),
                Text(
                  job.customer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ht.secondary,
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 14,
                      color: worker == null ? hc.alert : hc.inkSoft,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ht.small.copyWith(
                          color: worker == null ? hc.alert : hc.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Status as a shape and a colour, never colour alone — the tile's semantic
/// label says the same thing in words.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final (colour, icon) = switch (job.status) {
      JobStatus.requested => (hc.violet, Icons.language_rounded),
      JobStatus.open => (hc.alert, Icons.error_outline_rounded),
      JobStatus.assigned => (hc.violet, Icons.schedule_rounded),
      JobStatus.active => (hc.go, Icons.local_shipping_outlined),
      JobStatus.done => (hc.inkSoft, Icons.check_circle_outline_rounded),
    };
    return Icon(icon, size: 15, color: colour);
  }
}

/// "Today", "Tomorrow", "Yesterday", or the weekday.
String relativeDayLabel(int offset) => switch (offset) {
  0 => 'Today',
  1 => 'Tomorrow',
  -1 => 'Yesterday',
  _ => offset > 0 ? 'In $offset days' : '${-offset} days ago',
};

String formatDay(DateTime day) =>
    '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';

/// The full spoken form, for tooltips and announcements.
String describeDay(AppState state, int offset) =>
    '${relativeDayLabel(offset)}, ${formatDay(state.dayFor(offset))}';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
