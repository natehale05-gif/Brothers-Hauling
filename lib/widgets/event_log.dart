import 'package:flutter/material.dart';

import '../models/job.dart';
import '../theme/haul_theme.dart';

/// The movement log. Colour tells departures from arrivals at a glance, but the
/// icon and the wording carry it too — colour is never the only signal.
class EventLog extends StatelessWidget {
  const EventLog({super.key, required this.events, this.limit});

  final List<JobEvent> events;

  /// Show only the last N lines. Null shows everything.
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final shown = limit != null && events.length > limit!
        ? events.sublist(events.length - limit!)
        : events;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(e.time, style: HaulText.mono),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 1, right: 9),
                    child: Icon(_icon(e.kind), size: 13, color: _color(e.kind)),
                  ),
                  Expanded(
                    child: Text(
                      e.label,
                      style: HaulText.small.copyWith(
                        fontSize: 13,
                        color: _color(e.kind),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static IconData _icon(EventKind kind) => switch (kind) {
    EventKind.depart => Icons.navigation_rounded,
    EventKind.arrive => Icons.place_rounded,
    EventKind.flat => Icons.check_rounded,
  };

  static Color _color(EventKind kind) => switch (kind) {
    EventKind.depart => HaulColors.hivis,
    EventKind.arrive => HaulColors.go,
    EventKind.flat => HaulColors.white,
  };
}
