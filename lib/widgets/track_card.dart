import 'package:flutter/material.dart';

import '../data/seed_data.dart';
import '../models/job.dart';
import '../theme/haul_theme.dart';
import 'event_log.dart';
import 'primitives.dart';
import 'route_strip.dart';

/// One driver, one leg, live. This is the card dispatch actually watches.
class TrackCard extends StatelessWidget {
  const TrackCard({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final worker = crewById(job.assignedTo);
    if (worker == null) return const SizedBox.shrink();

    final phase = job.phase;
    final online = worker.appOpen;
    final pct = phase.moving
        ? job.progress
        : job.stage >= 2
        ? 1.0
        : 0.0;
    final from = job.stage <= 2 ? 'Yard' : job.city;
    final to = job.stage <= 2
        ? job.city
        : (job.hasDisposalStop ? job.disposal : 'Delivery point');

    return Opacity(
      // Faded because we have not heard from this app recently. The line at the
      // bottom of the card states that in words.
      opacity: online ? 1 : 0.66,
      child: HaulBlock(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CrewAvatar.muted(initials: worker.initials),
                const SizedBox(width: 11),
                Expanded(
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(worker.name, style: ht.bodyStrong),
                        const SizedBox(height: 2),
                        Text(
                          '${worker.unit} · ${job.id} · ${job.type}',
                          style: ht.small,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Flexible so a long phase label ellipsises instead of
                // pushing the card past its own edge on a small phone.
                Flexible(child: _statusPill(phase, online)),
              ],
            ),
            const SizedBox(height: 14),
            RouteStrip(
              progress: pct,
              from: from,
              to: to,
              middle: phase.moving
                  ? '${job.etaMinutes()} min out'
                  : phase.key == 'on_site'
                  ? 'Loading now'
                  : '',
            ),
            const SizedBox(height: 10),
            EventLog(events: job.events, limit: 4),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (online)
                  const PingDot(size: 7)
                else
                  Padding(
                    padding: EdgeInsets.only(right: 6, top: 1),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      size: 13,
                      color: hc.inkSoft,
                    ),
                  ),
                Expanded(
                  child: Text(
                    online
                        ? 'Pinging now — app is open'
                        : 'App closed. Last ping ${worker.lastSeen ?? "—"} '
                              'near ${worker.lastPlace ?? "unknown"}.',
                    style: ht.small.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(Phase phase, bool online) {
    if (phase.moving) {
      return Pill.brand(
        label: phase.label,
        icon: Icons.navigation_rounded,
        semanticLabel: 'Status: ${phase.label}, moving',
      );
    }
    if (online) {
      return Pill.go(
        label: phase.label,
        icon: Icons.podcasts_rounded,
        semanticLabel: 'Status: ${phase.label}, app open',
      );
    }
    return Pill(
      label: phase.label,
      icon: Icons.wifi_off_rounded,
      semanticLabel: 'Status: ${phase.label}, app closed',
    );
  }
}
