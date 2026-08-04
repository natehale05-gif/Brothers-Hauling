import 'package:flutter/material.dart';

import '../../models/job.dart';
import '../../models/time_entry.dart';
import '../../state/app_state.dart';
import '../../theme/haul_theme.dart';
import '../../widgets/job_card.dart';
import 'day_board.dart';
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

    return DayBoard(
      selectedJobId: selectedJobId,
      // Work going spare, and nothing else. A job already taken is on "My
      // jobs"; somebody else's running load is not this driver's business.
      only: (j) => j.status == JobStatus.open,
      emptyMessage: 'Swipe or use the arrows to look at another day.',
      // The full card, not a planning tile: hold-to-volunteer is the whole
      // reason a driver opens this screen, and a day layout must not cost it.
      tile: (job, selected) =>
          JobCard(job: job, mode: JobCardMode.board, selected: selected),
      // A job pushed to you wants an answer today, whatever day it runs. It
      // sits above the pager rather than behind a swipe nobody thought to make.
      pinned: pushed.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
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
              ),
            ),
    );
  }
}

/// The driver's own plate, plus what they've already closed today.
class EmployeeMineTab extends StatelessWidget {
  const EmployeeMineTab({super.key, this.selectedJobId});

  final String? selectedJobId;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final mine = state.myJobs;
    final done = state.myDone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'My jobs',
          trailing: Text('${mine.length} ACTIVE', style: ht.eyebrow),
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
          // Hours, not money. What those hours are worth is between the
          // driver and payroll, and the app is not where anyone finds out.
          SectionHeader(
            title: 'Closed today',
            trailing: Semantics(
              label:
                  'On the clock today: ${describeWorked(state.myHoursToday)}',
              excludeSemantics: true,
              child: Text(
                formatWorked(state.myHoursToday),
                style: ht.money.copyWith(fontSize: 16),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: hc.surface,
              border: Border.all(color: hc.line),
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
                          : BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: hc.line),
                              ),
                            ),
                      child: Row(
                        children: [
                          Flexible(
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
                                Text(done[i].type, style: ht.bodyStrong),
                                Text(done[i].id, style: ht.mono),
                              ],
                            ),
                          ),
                          Text(
                            formatWorked(done[i].workedBy(DateTime.now())),
                            style: ht.money.copyWith(fontSize: 16),
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
