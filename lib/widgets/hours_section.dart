import 'package:flutter/material.dart';

import '../models/crew_member.dart';
import '../models/job.dart' show formatClock;
import '../models/time_entry.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import 'primitives.dart';

/// Everybody's hours, one person at a time, on the screen the people are on.
///
/// Not a tab of its own: hours are a fact about a person, and the roster is
/// where the people already are. Looking somebody up and then looking their
/// time up somewhere else was two screens for one question.
///
/// Owner-only, and that includes the rates. A driver's own screens show them
/// their time and nothing about what it is worth — what somebody earns is
/// between them and payroll, and an app that announces it to whoever picks the
/// phone up is not doing anyone a favour.
class HoursSection extends StatelessWidget {
  const HoursSection({super.key});

  @override
  Widget build(BuildContext context) {
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    // The gate is here rather than at the call site so there is one place that
    // decides, and no screen can accidentally show this by forgetting to ask.
    if (!state.canSeeHoursAndPay) return const SizedBox.shrink();

    final sheets = state.timesheets;
    final total = sheets.fold(Duration.zero, (t, s) => t + s.worked);
    final running = sheets.where((s) => s.onTheClock).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Hours',
          topPadding: 22,
          trailing: Text(
            running == 1 ? '1 ON THE CLOCK' : '$running ON THE CLOCK',
            style: ht.eyebrow,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: StatTile(
                value: formatWorked(total),
                label: 'Hours on the books',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StatTile(value: '$running', label: 'On the clock'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Hours come from the jobs themselves — the clock starts when a '
            'driver takes a job on and stops when they close it. There is no '
            'timer to remember to start, and none to leave running overnight. '
            'Tap anyone above to read their time job by job.',
            style: ht.small.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Opens one person's hours, job by job.
Future<void> showTimesheet(BuildContext context, CrewMember member) {
  final state = AppScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => AppScope(
      state: state,
      child: _PersonSheet(member: member),
    ),
  );
}

/// One person's hours, job by job — the thing you check before paying someone.
class _PersonSheet extends StatelessWidget {
  const _PersonSheet({required this.member});

  final CrewMember member;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final sheet = state.timesheetFor(member);
    final pay = sheet.pay;

    return AlertDialog(
      backgroundColor: hc.surface,
      title: Text('${member.name} — hours', style: ht.heading),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyValueRow(
                label: 'Total',
                value: formatWorked(sheet.worked),
                valueStyle: ht.bodyStrong.copyWith(color: hc.brand),
              ),
              KeyValueRow(
                label: 'Rate',
                value: member.hourlyRate > 0
                    ? '\$${member.hourlyRate} an hour'
                    : 'Not set',
              ),
              KeyValueRow(
                label: 'Comes to',
                value: pay == null ? 'Set a rate first' : '\$$pay',
                divider: false,
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text('EVERY JOB', style: ht.blockTitle),
              ),
              const SizedBox(height: 8),
              if (sheet.entries.isEmpty)
                Text('No hours on the books yet.', style: ht.secondary)
              else
                for (final entry in sheet.entries) _EntryRow(entry: entry),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Close',
            style: ht.action.copyWith(fontSize: 13, color: hc.inkSoft),
          ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final worked = entry.workedBy(DateTime.now());

    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hc.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${entry.job.id} · ${entry.job.type}',
                    style: ht.bodyStrong,
                  ),
                  Text(
                    entry.running
                        ? 'Started ${formatClock(entry.startedAt)}, still on it'
                        : '${formatClock(entry.startedAt)} – '
                              '${formatClock(entry.finishedAt!)}',
                    style: ht.small.copyWith(
                      color: entry.running ? hc.go : hc.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatWorked(worked),
              style: ht.mono.copyWith(color: hc.ink, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
