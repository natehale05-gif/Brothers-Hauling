import 'package:flutter/material.dart';

import '../models/job.dart';
import '../theme/haul_theme.dart';

/// The five-segment progress rail. Segments are decoration — the stage name
/// above them carries the meaning — so the whole thing is announced once as
/// "Stage 3 of 5, Loading".
class StageRail extends StatelessWidget {
  const StageRail({
    super.key,
    required this.stage,
    this.showLabel = true,
    this.trailing,
  });

  final int stage;

  final bool showLabel;

  /// Appended to the stage line, e.g. "· 14 min out".
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final capped = stage.clamp(0, kStages.length - 1);
    final label = kStages[capped];
    final segments = kStages.length - 1; // "Closed" isn't a segment

    return Semantics(
      label:
          'Stage ${(capped + 1).clamp(1, segments)} of $segments, $label'
          '${trailing != null ? ', $trailing' : ''}',
      excludeSemantics: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLabel)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                trailing == null
                    ? label.toUpperCase()
                    : '${label.toUpperCase()} · ${trailing!.toUpperCase()}',
                style: HaulText.eyebrow.copyWith(color: HaulColors.go),
              ),
            ),
          Row(
            children: [
              for (var i = 0; i < segments; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: i <= capped ? HaulColors.go : HaulColors.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
