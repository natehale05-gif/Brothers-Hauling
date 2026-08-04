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
  const DayBoard({super.key, this.selectedJobId});

  final String? selectedJobId;

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
        _DayBar(offset: offset),
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
            ),
          ),
        ),
      ],
    );
  }
}

/// The date, the arrows, and the way back to today.
class _DayBar extends StatelessWidget {
  const _DayBar({required this.offset});

  final int offset;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final day = state.dayFor(offset);
    final count = state.jobsOn(day).length;

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
  const _DayPage({required this.offset, this.selectedJobId});

  final int offset;
  final String? selectedJobId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final day = state.dayFor(offset);
    final jobs = state.jobsOn(day);
    final loose = offset == 0 ? state.unscheduledJobs : const <Job>[];

    if (jobs.isEmpty && loose.isEmpty) {
      return EmptyState(
        title: 'Nothing on ${relativeDayLabel(offset).toLowerCase()}',
        message: 'Swipe or use the arrows to look at another day.',
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (jobs.isNotEmpty)
          _Grid(jobs: jobs, selectedJobId: selectedJobId)
        else
          const EmptyState(
            title: 'Nothing booked in',
            message: 'The jobs below have not been given a day yet.',
          ),
        if (loose.isNotEmpty) ...[
          const SizedBox(height: 6),
          const SectionHeader(title: 'No day set', topPadding: 10),
          _Grid(jobs: loose, selectedJobId: selectedJobId),
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
  const _Grid({required this.jobs, this.selectedJobId});

  final List<Job> jobs;
  final String? selectedJobId;

  @override
  Widget build(BuildContext context) {
    // Tiles grow with the text scale — otherwise the largest supported text
    // simply overflows a fixed-height cell.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return GridView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        // Wide enough that a phone gets a single readable column and a desktop
        // window gets three or four, without either being a breakpoint.
        maxCrossAxisExtent: 420,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 150 * scale,
      ),
      itemCount: jobs.length,
      itemBuilder: (context, i) =>
          _DayTile(job: jobs[i], selected: jobs[i].id == selectedJobId),
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
