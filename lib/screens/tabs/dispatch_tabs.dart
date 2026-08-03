import 'package:flutter/material.dart';

import '../../data/seed_data.dart';
import '../../models/job.dart';
import '../../state/app_state.dart';
import '../../theme/haul_theme.dart';
import '../../widgets/job_card.dart';
import '../../widgets/primitives.dart';
import '../../widgets/route_strip.dart';
import '../../widgets/track_card.dart';

/// Every job, sorted by what needs a human: unclaimed first, then running,
/// then closed.
class JobsTab extends StatelessWidget {
  const JobsTab({super.key, this.selectedJobId});

  final String? selectedJobId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final open = state.openBoard;
    final active = state.activeAll;
    final done = state.doneAll;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: '${open.length}',
                label: 'Unclaimed',
                valueColor: open.isEmpty ? HaulColors.white : HaulColors.alert,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: '${active.length}',
                label: 'In motion',
                valueColor: HaulColors.go,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (open.isNotEmpty) ...[
          const SectionHeader(
            title: "Nobody's taken these",
            trailing: Pill.alert(label: 'Act'),
          ),
          for (final j in open)
            JobCard(
              job: j,
              mode: JobCardMode.manage,
              selected: j.id == selectedJobId,
            ),
        ],
        const SectionHeader(title: 'Running now', topPadding: 18),
        if (active.isEmpty)
          const EmptyState(
            title: 'Nothing in motion',
            message: 'Once a driver accepts, the job shows up here.',
          )
        else
          for (final j in active)
            JobCard(
              job: j,
              mode: JobCardMode.manage,
              selected: j.id == selectedJobId,
            ),
        if (done.isNotEmpty) ...[
          const SectionHeader(title: 'Closed', topPadding: 18),
          for (final j in done)
            JobCard(
              job: j,
              mode: JobCardMode.manage,
              selected: j.id == selectedJobId,
            ),
        ],
      ],
    );
  }
}

/// Live positions, and — just as important — who isn't reporting.
class TrackingTab extends StatelessWidget {
  const TrackingTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final running = state.jobs
        .where((j) => j.status == JobStatus.active && j.assignedTo != null)
        .toList();
    final busy = running.map((j) => j.assignedTo).toSet();
    final notTracking = [
      ...kCrew.where((c) => c.onShift && !busy.contains(c.id)),
      ...kCrew.where((c) => !c.onShift),
    ];
    final appsOpen = kCrew.where((c) => c.appOpen).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Live crew',
          trailing: Text('$appsOpen APPS OPEN', style: HaulText.eyebrow),
        ),
        if (running.isEmpty)
          const EmptyState(
            title: "Nobody's rolling",
            message:
                'Positions appear here the moment a driver accepts a job and '
                'opens the app.',
          )
        else
          for (final j in running) TrackCard(job: j),
        const SectionHeader(title: 'Not tracking', topPadding: 18),
        Container(
          decoration: BoxDecoration(
            color: HaulColors.surface,
            border: Border.all(color: HaulColors.line),
            borderRadius: BorderRadius.circular(HaulSpace.radius),
          ),
          child: Column(
            children: [
              for (var i = 0; i < notTracking.length; i++)
                MergeSemantics(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
                    decoration: i == notTracking.length - 1
                        ? null
                        : const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: HaulColors.line),
                            ),
                          ),
                    child: Row(
                      children: [
                        PingDot(live: notTracking[i].appOpen, size: 9),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                notTracking[i].name,
                                style: HaulText.bodyStrong,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                notTracking[i].appOpen
                                    ? 'App open — no job assigned'
                                    : 'Last ping '
                                          '${notTracking[i].lastSeen ?? "—"} · '
                                          '${notTracking[i].lastPlace ?? "unknown"}',
                                style: HaulText.small,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Pill(
                            label: notTracking[i].onShift ? 'On shift' : 'Off',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Positions only report while a driver has the app open. Closing '
            'the app stops tracking — the last known ping is kept so you know '
            'where someone dropped off.',
            style: HaulText.small.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Roster with what each driver is on right now.
class CrewTab extends StatelessWidget {
  const CrewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final onShift = kCrew.where((c) => c.onShift).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Crew',
          trailing: Text('$onShift ON SHIFT', style: HaulText.eyebrow),
        ),
        Container(
          decoration: BoxDecoration(
            color: HaulColors.surface,
            border: Border.all(color: HaulColors.line),
            borderRadius: BorderRadius.circular(HaulSpace.radius),
          ),
          child: Column(
            children: [
              for (var i = 0; i < kCrew.length; i++)
                Builder(
                  builder: (context) {
                    final c = kCrew[i];
                    Job? on;
                    for (final j in state.jobs) {
                      if (j.assignedTo == c.id && j.status != JobStatus.done) {
                        on = j;
                        break;
                      }
                    }
                    final detail = on != null
                        ? '${on.id} — ${on.phase.label}'
                              '${on.phase.moving ? ", ${on.etaMinutes()} min out" : ""}'
                        : c.onShift
                        ? 'Idle — no load'
                        : 'Off shift';

                    return MergeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: i == kCrew.length - 1
                            ? null
                            : const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: HaulColors.line),
                                ),
                              ),
                        child: Row(
                          children: [
                            CrewAvatar.muted(initials: c.initials, size: 36),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.only(right: 7),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: c.onShift
                                              ? HaulColors.go
                                              : HaulColors.line,
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(
                                          c.name,
                                          style: HaulText.bodyStrong,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${c.unit} · $detail',
                                    style: HaulText.small,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: c.appOpen
                                  ? const Pill.go(label: 'Live')
                                  : const Pill(label: 'Dark'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The owner's screen: money, who's rolling, and what still needs a driver.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final revenue = state.revenue;
    final cost = state.cost;
    final open = state.openBoard;
    final moving = state.moving;

    // Six days of history plus today's live figure.
    final week = <int>[520, 340, 890, 0, 705, 470, revenue];
    final max = week.fold(1, (m, v) => v > m ? v : m);
    const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatTile(
          value: '\$${_thousands(revenue)}',
          label: 'Billed today',
          hero: true,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: '\$${_thousands(revenue - cost)}',
                label: 'Margin',
                valueColor: HaulColors.go,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: '\$${_thousands(cost)}',
                label: 'Payout + disposal',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: '${open.length}',
                label: 'Unclaimed jobs',
                valueColor: open.isEmpty ? HaulColors.white : HaulColors.alert,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: '${moving.length}',
                label: 'On the road now',
                valueColor: HaulColors.brand,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SectionHeader(
          title: 'Moving right now',
          trailing: Pill.brand(label: 'Live'),
        ),
        if (moving.isEmpty)
          const EmptyState(
            message:
                "Nobody's between stops. Check Tracking for full crew status.",
          )
        else
          for (final j in moving) TrackCard(job: j),
        const SizedBox(height: 6),
        HaulBlock(
          title: 'Billed, last 7 days',
          child: Semantics(
            // A bar chart is unreadable to a screen reader; state the series.
            label: [
              'Billed, last 7 days.',
              for (var i = 0; i < week.length; i++)
                '${dayNames[i]}: ${week[i]} dollars.',
            ].join(' '),
            excludeSemantics: true,
            container: true,
            child: SizedBox(
              height: 118,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < week.length; i++) ...[
                    if (i > 0) const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: (week[i] / max * 88).clamp(3.0, 88.0),
                            decoration: BoxDecoration(
                              color: week[i] == 0
                                  ? HaulColors.line
                                  : HaulColors.brand,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dayLetters[i],
                            style: HaulText.eyebrow.copyWith(letterSpacing: 0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SectionHeader(title: 'Needs attention', topPadding: 6),
        if (open.isEmpty)
          const EmptyState(
            title: 'All clear',
            message: 'Every posted job has a driver on it.',
          )
        else
          for (final j in open)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: HaulColors.surface,
                border: Border.all(color: HaulColors.line),
                borderRadius: BorderRadius.circular(HaulSpace.radius),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: MergeSemantics(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  j.type.toUpperCase(),
                                  style: HaulText.heading,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Unclaimed · window ${j.window}',
                                  style: HaulText.secondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Semantics(
                          label: 'Bills at ${j.billed} dollars',
                          excludeSemantics: true,
                          child: Text('\$${j.billed}', style: HaulText.money),
                        ),
                      ],
                    ),
                  ),
                  ActionBar(
                    label: 'Assign someone',
                    ghost: true,
                    semanticLabel: 'Assign someone to ${j.id}, ${j.type}',
                    onPressed: () => state.openJobCard(j),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  static String _thousands(int v) {
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}
