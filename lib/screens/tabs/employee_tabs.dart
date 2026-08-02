import 'package:flutter/material.dart';

import '../../models/job.dart';
import '../../state/app_state.dart';
import '../../theme/haul_theme.dart';
import '../../widgets/job_card.dart';
import '../../widgets/primitives.dart';

/// What a driver sees first: anything pushed at them, then the open board.
class EmployeeBoardTab extends StatelessWidget {
  const EmployeeBoardTab({super.key, this.selectedJobId});

  final String? selectedJobId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final pushed = state.myJobs
        .where((j) => j.status == JobStatus.assigned)
        .toList();
    final board = state.openBoard;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pushed.isNotEmpty) ...[
          const SectionHeader(
            title: 'Assigned to you',
            trailing: Pill.violet(label: 'Needs your yes'),
          ),
          for (final j in pushed)
            JobCard(
              job: j,
              mode: JobCardMode.mine,
              selected: j.id == selectedJobId,
            ),
          const SizedBox(height: 8),
        ],
        SectionHeader(
          title: 'Up for grabs',
          trailing: Text('${board.length} OPEN', style: HaulText.eyebrow),
        ),
        if (board.isEmpty)
          const EmptyState(
            title: "Board's clear",
            message: 'Every load has a driver. New work posts through the day.',
          )
        else
          for (final j in board)
            JobCard(
              job: j,
              mode: JobCardMode.board,
              selected: j.id == selectedJobId,
            ),
      ],
    );
  }
}

/// The driver's own plate, plus what they've already closed today.
class EmployeeMineTab extends StatelessWidget {
  const EmployeeMineTab({super.key, this.selectedJobId});

  final String? selectedJobId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final mine = state.myJobs;
    final done = state.myDone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'My jobs',
          trailing: Text('${mine.length} ACTIVE', style: HaulText.eyebrow),
        ),
        if (mine.isEmpty)
          const EmptyState(
            title: 'Nothing on your plate',
            message:
                'Head to the board and hold a card to volunteer for a load.',
          )
        else
          for (final j in mine)
            JobCard(
              job: j,
              mode: JobCardMode.mine,
              selected: j.id == selectedJobId,
            ),
        if (done.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Closed today',
            trailing: Semantics(
              label: 'Earned today: ${state.myEarned} dollars',
              excludeSemantics: true,
              child: Text(
                '\$${state.myEarned}',
                style: HaulText.money.copyWith(fontSize: 16),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: HaulColors.surface,
              border: Border.all(color: HaulColors.line),
              borderRadius: BorderRadius.circular(HaulSpace.radius),
            ),
            child: Column(
              children: [
                for (var i = 0; i < done.length; i++)
                  MergeSemantics(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: i == done.length - 1
                          ? null
                          : const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: HaulColors.line),
                              ),
                            ),
                      child: Row(
                        children: [
                          const Flexible(
                            child: Pill.go(
                              label: 'Done',
                              icon: Icons.check_rounded,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(done[i].type, style: HaulText.bodyStrong),
                                Text(done[i].id, style: HaulText.mono),
                              ],
                            ),
                          ),
                          Text(
                            '\$${done[i].payout}',
                            style: HaulText.money.copyWith(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
