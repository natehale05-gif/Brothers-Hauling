import 'package:flutter/material.dart';

import '../../models/crew_member.dart';
import '../../models/job.dart' show formatClock;
import '../../models/time_entry.dart';
import '../../state/app_state.dart';
import '../../theme/haul_theme.dart';
import '../../widgets/primitives.dart';
import '../../widgets/route_strip.dart' show PingDot;

/// Everybody's hours, one person at a time.
///
/// Owner-only, and that includes the rates. A driver's own screens show them
/// their time and nothing about what it is worth — what somebody earns is
/// between them and payroll, and an app that announces it to whoever picks the
/// phone up is not doing anyone a favour.
class HoursTab extends StatelessWidget {
  const HoursTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final sheets = state.timesheets;
    final total = sheets.fold(Duration.zero, (t, s) => t + s.worked);
    final running = sheets.where((s) => s.onTheClock).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              child: StatTile(
                value: '$running',
                label: running == 1 ? 'On the clock' : 'On the clock',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const SectionHeader(title: 'By person'),
        for (final sheet in sheets) _PersonRow(sheet: sheet),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Hours come from the jobs themselves — the clock starts when a '
            'driver takes a job on and stops when they close it. There is no '
            'timer to remember to start, and none to leave running overnight.',
            style: ht.small.copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.sheet});

  final Timesheet sheet;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final pay = sheet.pay;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border.all(color: hc.line),
        borderRadius: BorderRadius.circular(HaulSpace.radius),
      ),
      child: Semantics(
        button: true,
        label:
            '${sheet.member.name}, ${describeWorked(sheet.worked)}'
            '${sheet.onTheClock ? ', on the clock now' : ''}'
            '${pay == null ? ', no rate set' : ', $pay dollars'}. '
            'Open their hours.',
        onTap: () => _open(context),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(HaulSpace.radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            child: Row(
              children: [
                CrewAvatar.muted(initials: sheet.member.initials, size: 34),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(sheet.member.name, style: ht.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        sheet.member.hourlyRate > 0
                            ? '\$${sheet.member.hourlyRate}/hr · '
                                  '${sheet.entries.length} '
                                  '${sheet.entries.length == 1 ? 'job' : 'jobs'}'
                            : 'No rate set · ${sheet.entries.length} '
                                  '${sheet.entries.length == 1 ? 'job' : 'jobs'}',
                        style: ht.small,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatWorked(sheet.worked),
                      style: ht.money.copyWith(fontSize: 17),
                    ),
                    Text(
                      // A rate nobody has set reads as missing, not as free.
                      pay == null ? 'no rate' : '\$$pay',
                      style: ht.small.copyWith(fontSize: 11),
                    ),
                  ],
                ),
                if (sheet.onTheClock) ...[
                  const SizedBox(width: 8),
                  PingDot(live: true, size: 9),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final state = AppScope.of(context);
    showDialog<void>(
      context: context,
      builder: (_) => AppScope(
        state: state,
        child: _PersonSheet(member: sheet.member),
      ),
    );
  }
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
