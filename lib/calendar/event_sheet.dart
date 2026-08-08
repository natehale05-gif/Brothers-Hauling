import 'package:flutter/material.dart';

import '../data/seed_data.dart';
import '../models/job.dart';
import '../state/app_state.dart';
import 'calendar_state.dart';
import 'calendar_theme.dart';
import 'date_math.dart';
import 'event.dart';
import 'event_editor.dart';

/// One job, opened from the calendar.
///
/// Apple's event detail is a sheet over the calendar rather than a new screen,
/// so the day you were looking at stays behind it. Same here — a dispatcher
/// checking an address should not lose their place in the week.
class EventSheet extends StatelessWidget {
  const EventSheet({super.key, required this.event});

  /// Null when the open job has gone — deleted underneath, or filtered out by
  /// hiding its calendar. The sheet closes itself rather than showing a blank.
  final CalendarEvent? event;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final cal = CalendarScope.of(context);
    final open = event;

    if (open == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => cal.closeEvent());
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        label: 'Job details',
        explicitChildNodes: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                button: true,
                label: 'Close',
                onTap: cal.closeEvent,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: cal.closeEvent,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.8,
                  maxWidth: 560,
                ),
                decoration: BoxDecoration(
                  color: p.groupedBg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                ),
                child: _Detail(event: open),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);
    final app = AppScope.of(context);
    final job = event.job;
    final worker = crewById(job.assignedTo);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: event.colour,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    event.calendar.label,
                    style: t.secondary.copyWith(color: event.colour),
                  ),
                ),
                if (app.canEditJobs)
                  Semantics(
                    button: true,
                    label: 'Edit job',
                    onTap: () => showEventEditor(context, job: job),
                    excludeSemantics: true,
                    child: TextButton(
                      onPressed: () => showEventEditor(context, job: job),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      child: Text(
                        'Edit',
                        style: t.body.copyWith(fontSize: 15, color: p.accent),
                      ),
                    ),
                  ),
                Semantics(
                  button: true,
                  label: 'Close',
                  onTap: cal.closeEvent,
                  excludeSemantics: true,
                  child: IconButton(
                    onPressed: cal.closeEvent,
                    tooltip: 'Close',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Icon(Icons.close_rounded, color: p.secondaryLabel),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 20),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    job.customer,
                    style: t.largeTitle.copyWith(fontSize: 26),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    event.allDay
                        ? '${longDay(event.start)} · all-day'
                        : '${longDay(event.start)} · '
                              '${timeRange(event.start, event.end)}',
                    style: t.secondary,
                  ),
                ),
                _Group(
                  rows: [
                    _Row(label: 'Job', value: job.id),
                    _Row(
                      label: 'Where',
                      value: job.city.isEmpty
                          ? job.address
                          : '${job.address}, ${job.city}',
                    ),
                    _Row(label: 'Window', value: job.window),
                    _Row(
                      label: 'Alert',
                      value: job.alertMinutes == null
                          ? ''
                          : alertLabel(job.alertMinutes),
                    ),
                    _Row(label: 'Contact', value: job.contact),
                    _Row(label: 'Phone', value: job.phone),
                  ],
                ),
                _Group(
                  rows: [
                    _Row(label: 'Material', value: job.material),
                    _Row(label: 'Volume', value: job.volume),
                    _Row(label: 'Weight', value: job.weight),
                    // Stated, never enforced — see the rig decision.
                    _Row(label: 'Rig needed', value: job.equipment),
                    _Row(label: 'Goes to', value: job.disposal),
                  ],
                ),
                _Group(
                  rows: [
                    _Row(
                      label: 'Status',
                      value: switch (job.status) {
                        JobStatus.requested => 'Booked, not priced',
                        JobStatus.open => 'Nobody has taken it',
                        JobStatus.assigned => 'Waiting on a yes',
                        JobStatus.active => kStages[job.stage],
                        JobStatus.done => 'Closed',
                      },
                    ),
                    _Row(label: 'Driver', value: worker?.name ?? 'Nobody yet'),
                    if (app.canSeeMoney)
                      _Row(label: 'Bills at', value: '\$${job.billed}'),
                  ],
                ),
                if (job.access.trim().isNotEmpty)
                  _Group(
                    rows: [_Row(label: 'Access', value: job.access)],
                  ),
                if (job.hazards.isNotEmpty)
                  _Group(
                    rows: [
                      for (final hazard in job.hazards)
                        _Row(label: 'Hazard', value: hazard, alert: true),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An inset grouped table, the way iOS draws one.
class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final shown = rows.where((r) => r.value.trim().isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              shown[i],
              if (i < shown.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: p.hairline,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.alert = false});

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: Text(label, style: t.secondary)),
            Expanded(
              child: Text(
                value,
                style: t.body.copyWith(
                  fontSize: 15,
                  color: alert ? p.accent : p.label,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
