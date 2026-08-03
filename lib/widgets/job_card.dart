import 'package:flutter/material.dart';

import '../data/seed_data.dart';
import '../models/job.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import 'hold_button.dart';
import 'primitives.dart';
import 'sync_strip.dart';
import 'stage_rail.dart';

/// How a job card behaves depends on where it is being shown.
enum JobCardMode {
  /// Up for grabs — hold to volunteer.
  board,

  /// Assigned to or run by the signed-in driver.
  mine,

  /// Dispatch's view — opens details and staffing.
  manage,
}

class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.mode,
    this.selected = false,
  });

  final Job job;
  final JobCardMode mode;

  /// Highlighted because it is the job open in the side pane (wide layouts).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final state = AppScope.of(context);
    final runnable = state.canRun(job);
    final worker = crewById(job.assignedTo);
    final isMineActive =
        job.assignedTo == kMeId && job.status == JobStatus.active;
    final lockedOut = mode == JobCardMode.board && !runnable;

    final border = selected
        ? hc.brand
        : isMineActive
        ? hc.go
        : job.status == JobStatus.assigned
        ? hc.violet
        : hc.line;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border.all(color: border, width: selected ? 2 : 1),
        borderRadius: BorderRadius.circular(HaulSpace.radius),
      ),
      clipBehavior: Clip.antiAlias,
      // Dimming the card is a visual shorthand for "wrong rig"; the fact chip
      // below spells it out so the meaning does not live in opacity alone.
      child: Opacity(
        opacity: lockedOut ? 0.62 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: _Headline(job: job, showBilled: state.canSeeMoney),
            ),
            if (job.status == JobStatus.active)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: StageRail(
                  stage: job.stage,
                  trailing: job.phase.moving
                      ? '${job.etaMinutes()} min out'
                      : null,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FactChip(
                    icon: Icons.place_outlined,
                    label: '${job.miles} mi · ${job.deadhead} out',
                  ),
                  FactChip(label: '${job.volume} · ${job.weight}'),
                  FactChip(
                    icon: lockedOut
                        ? Icons.warning_amber_rounded
                        : Icons.build_outlined,
                    label: lockedOut
                        ? '${job.equipment} — not your rig'
                        : job.equipment,
                    bad: lockedOut,
                  ),
                  FactChip(icon: Icons.schedule_rounded, label: job.window),
                  if (worker != null && !state.employeeView)
                    FactChip(
                      icon: Icons.person_outline_rounded,
                      label: worker.name,
                    ),
                  if (job.status == JobStatus.assigned)
                    Pill.violet(label: 'Awaiting accept'),
                  if (state.unsyncedJobIds.contains(job.id))
                    const UnsyncedChip(),
                ],
              ),
            ),
            ..._actions(context, state, runnable),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, AppState state, bool runnable) {
    switch (mode) {
      case JobCardMode.board:
        return [
          HoldButton(
            enabled: runnable,
            idleLabel: 'Hold to volunteer',
            blockedLabel: 'Wrong rig for this load',
            confirmTitle: 'Take ${job.id}?',
            confirmMessage:
                '${job.type} for ${job.customer} in ${job.city}. '
                'Pays \$${job.payout}. Dispatch will see you on it.',
            onConfirmed: () => state.claim(job),
          ),
        ];
      case JobCardMode.mine:
        if (job.status == JobStatus.assigned) {
          return [
            ActionBar(
              label: 'Accept this job',
              solid: true,
              semanticLabel: 'Accept ${job.id}, ${job.type}',
              onPressed: () => state.accept(job),
            ),
          ];
        }
        return [
          ActionBar(
            label: 'Open job card',
            semanticLabel: 'Open job card for ${job.id}, ${job.type}',
            onPressed: () => state.openJobCard(job),
          ),
        ];
      case JobCardMode.manage:
        return [
          ActionBar(
            label: 'Details & staffing',
            ghost: true,
            semanticLabel: 'Details and staffing for ${job.id}, ${job.type}',
            onPressed: () => state.openJobCard(job),
          ),
        ];
    }
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.job, required this.showBilled});

  final Job job;
  final bool showBilled;

  @override
  Widget build(BuildContext context) {
    final ht = HaulText.of(context);
    // Money is one idea; read it as one phrase rather than a number followed by
    // an orphaned caption.
    final moneyLabel = showBilled
        ? 'Bills at ${job.billed} dollars, driver payout ${job.payout} dollars'
        : 'Your cut, ${job.payout} dollars';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(job.type.toUpperCase(), style: ht.heading),
                ),
                const SizedBox(height: 4),
                Text('${job.customer} · ${job.city}', style: ht.secondary),
                const SizedBox(height: 6),
                Text(job.id, style: ht.mono),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          label: moneyLabel,
          excludeSemantics: true,
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${showBilled ? job.billed : job.payout}',
                style: ht.money,
              ),
              const SizedBox(height: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  showBilled ? 'billed · pays \$${job.payout}' : 'your cut',
                  textAlign: TextAlign.end,
                  style: ht.small.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
