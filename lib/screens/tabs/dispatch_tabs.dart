import 'package:flutter/material.dart';

import '../../data/seed_data.dart';
import '../../models/crew_member.dart';
import '../../models/job.dart';
import '../../models/role.dart';
import '../../state/app_state.dart';
import '../../theme/haul_theme.dart';
import '../../widgets/job_card.dart';
import '../../widgets/add_crew.dart';
import '../edit_job.dart';
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
    final hc = HaulColors.of(context);
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
                valueColor: open.isEmpty ? hc.ink : hc.alert,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: '${active.length}',
                label: 'In motion',
                valueColor: hc.go,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.requestedJobs.isNotEmpty) ...[
          SectionHeader(
            title: 'Came in from the website',
            trailing: Pill.violet(label: 'Needs pricing'),
          ),
          // Held back from the driver board on purpose: a job with no cut on
          // it is a job somebody can volunteer for at nothing a load.
          for (final j in state.requestedJobs)
            _BookingCard(job: j, selected: j.id == selectedJobId),
        ],
        if (open.isNotEmpty) ...[
          SectionHeader(
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
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final running = state.jobs
        .where((j) => j.status == JobStatus.active && j.assignedTo != null)
        .toList();
    final busy = running.map((j) => j.assignedTo).toSet();
    final drivers = state.drivers;
    final notTracking = [
      ...drivers.where((c) => c.onShift && !busy.contains(c.id)),
      ...drivers.where((c) => !c.onShift),
    ];
    final appsOpen = drivers.where((c) => c.appOpen).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Live crew',
          trailing: Text('$appsOpen APPS OPEN', style: ht.eyebrow),
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
            color: hc.surface,
            border: Border.all(color: hc.line),
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
                        : BoxDecoration(
                            border: Border(bottom: BorderSide(color: hc.line)),
                          ),
                    child: Row(
                      children: [
                        PingDot(live: notTracking[i].appOpen, size: 9),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(notTracking[i].name, style: ht.bodyStrong),
                              const SizedBox(height: 2),
                              Text(
                                notTracking[i].appOpen
                                    ? 'App open — no job assigned'
                                    : 'Last ping '
                                          '${notTracking[i].lastSeen ?? "—"} · '
                                          '${notTracking[i].lastPlace ?? "unknown"}',
                                style: ht.small,
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
            style: ht.small.copyWith(fontSize: 12),
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
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final crew = state.crew;
    final onShift = crew.where((c) => c.onShift).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Crew',
          trailing: Text('$onShift ON SHIFT', style: ht.eyebrow),
        ),
        if (state.canHire) const AddCrewButton(),
        Container(
          decoration: BoxDecoration(
            color: hc.surface,
            border: Border.all(color: hc.line),
            borderRadius: BorderRadius.circular(HaulSpace.radius),
          ),
          child: Column(
            children: [
              for (var i = 0; i < crew.length; i++)
                Builder(
                  builder: (context) {
                    final c = crew[i];
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

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: i == crew.length - 1
                          ? null
                          : BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: hc.line),
                              ),
                            ),
                      child: Row(
                        children: [
                          // The person reads as one thing; the control that
                          // changes their access is its own, so a screen
                          // reader does not fold a button into a sentence.
                          Expanded(
                            child: MergeSemantics(
                              child: Row(
                                children: [
                                  CrewAvatar.muted(
                                    initials: c.initials,
                                    size: 36,
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              margin: const EdgeInsets.only(
                                                right: 7,
                                              ),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: c.onShift
                                                    ? hc.go
                                                    : hc.line,
                                              ),
                                            ),
                                            Flexible(
                                              child: Text(
                                                c.name,
                                                style: ht.bodyStrong,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          // The level rides in the text rather
                                          // than as another chip: it is worth
                                          // seeing, not worth a column.
                                          '${c.role.label} · ${c.unit} · '
                                          '$detail',
                                          style: ht.small,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: c.appOpen
                                        ? Pill.go(label: 'Live')
                                        : const Pill(label: 'Dark'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          RoleControl(member: c),
                        ],
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

/// What somebody is allowed to see, and — for an owner — a way to change it.
///
/// The level is shown to everyone who can see the roster at all, because "who
/// is a manager here" is not a secret. It only becomes a control for an owner,
/// and never on their own row.
class RoleControl extends StatelessWidget {
  const RoleControl({super.key, required this.member});

  final CrewMember member;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    // The level is already on the row, in the line under the name. This is
    // only the control that changes it, so it stays an icon — on a small phone
    // at large text there is no room to print the word twice.
    if (!state.canSetRoles || member.id == kMeId) {
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label:
          'Change what ${member.name} can see. Currently '
          '${member.role.label.toLowerCase()}.',
      excludeSemantics: true,
      child: PopupMenuButton<Role>(
        tooltip: 'Change access',
        initialValue: member.role,
        color: hc.surface,
        onSelected: (role) => state.setCrewRole(member, role),
        itemBuilder: (context) => [
          for (final role in Role.values)
            PopupMenuItem<Role>(
              value: role,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(role.label, style: ht.bodyStrong),
                  Text(role.blurb, style: ht.small),
                ],
              ),
            ),
        ],
        child: SizedBox(
          width: 40,
          height: HaulSpace.tap,
          child: Icon(
            Icons.manage_accounts_outlined,
            size: 22,
            color: hc.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// The owner's screen: money, who's rolling, and what still needs a driver.
class OverviewTab extends StatelessWidget {
  const OverviewTab({super.key});

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
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
                valueColor: hc.go,
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
                valueColor: open.isEmpty ? hc.ink : hc.alert,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(
                value: '${moving.length}',
                label: 'On the road now',
                valueColor: hc.brand,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SectionHeader(
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
                              color: week[i] == 0 ? hc.line : hc.brand,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            dayLetters[i],
                            style: ht.eyebrow.copyWith(letterSpacing: 0),
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
                color: hc.surface,
                border: Border.all(color: hc.line),
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
                                Text(j.type.toUpperCase(), style: ht.heading),
                                const SizedBox(height: 4),
                                Text(
                                  'Unclaimed · window ${j.window}',
                                  style: ht.secondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Semantics(
                          label: 'Bills at ${j.billed} dollars',
                          excludeSemantics: true,
                          child: Text('\$${j.billed}', style: ht.money),
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

/// A booking waiting on a price.
///
/// Not a [JobCard]: the driver-facing card leads with the money, and the whole
/// point of this one is that there isn't any yet. It leads with what the
/// customer asked for and ends in the two things dispatch has to do — put a
/// number on it, then let the crew see it.
class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.job, required this.selected});

  final Job job;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final priced = job.billed > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border.all(color: selected ? hc.brand : hc.line),
        borderRadius: BorderRadius.circular(HaulSpace.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label:
                'Open the booking from ${job.customer}, '
                '${priced ? "priced at ${job.billed} dollars" : "not priced yet"}',
            onTap: () => state.openJobCard(job),
            excludeSemantics: true,
            child: InkWell(
              onTap: () => state.openJobCard(job),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.type.toUpperCase(), style: ht.heading),
                    const SizedBox(height: 3),
                    Text(
                      [
                        job.customer,
                        if (job.city.isNotEmpty) job.city,
                      ].join(' · '),
                      style: ht.secondary,
                    ),
                    if (job.access.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        job.access,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: ht.small,
                      ),
                    ],
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Pill(label: job.id, icon: Icons.tag_rounded),
                        Pill(label: job.window, icon: Icons.schedule_rounded),
                        if (!priced)
                          const Pill.violet(label: 'No price yet')
                        else
                          Pill.brand(label: 'Bills at \$${job.billed}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: hc.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: 'Price ${job.id} and fill in its details',
                    onTap: () => showEditJobSheet(context, job),
                    excludeSemantics: true,
                    child: TextButton(
                      onPressed: () => showEditJobSheet(context, job),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, HaulSpace.tap),
                        foregroundColor: hc.inkSoft,
                      ),
                      child: Text(
                        'FILL IN THE DETAILS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ht.action.copyWith(
                          fontSize: 12,
                          color: hc.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 28, color: hc.line),
                Expanded(
                  child: Semantics(
                    button: true,
                    enabled: priced,
                    label: priced
                        ? 'Put ${job.id} on the board for the crew'
                        : "Put ${job.id} on the board — needs a driver's cut "
                              'first',
                    onTap: priced ? () => state.publishJob(job) : null,
                    excludeSemantics: true,
                    child: TextButton(
                      // Always tappable: tapping it while unpriced is how the
                      // driver's cut gets explained, and a dead grey button
                      // explains nothing.
                      onPressed: () => state.publishJob(job),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, HaulSpace.tap),
                        foregroundColor: priced ? hc.brand : hc.inkSoft,
                      ),
                      child: Text(
                        'PUT ON THE BOARD',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ht.action.copyWith(
                          fontSize: 12,
                          color: priced ? hc.brand : hc.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
