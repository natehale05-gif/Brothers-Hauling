import 'package:flutter/material.dart';

import '../theme/haul_theme.dart';

/// The truck-on-a-line that dispatch reads at a glance: where the rig started,
/// where it's going, and how far along it is.
///
/// Animated between ticks so the rig glides instead of jumping — except under
/// reduced motion, where it snaps to position instead.
class RouteStrip extends StatelessWidget {
  const RouteStrip({
    super.key,
    required this.progress,
    required this.from,
    required this.to,
    this.middle,
  });

  /// 0..1 along the leg.
  final double progress;

  final String from;
  final String to;

  /// The status line under the middle of the strip, e.g. "14 min out".
  final String? middle;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pct = progress.clamp(0.0, 1.0);
    const rigSize = 30.0;

    return Semantics(
      label:
          'Route from $from to $to, ${(pct * 100).round()} percent complete'
          '${middle != null && middle!.isNotEmpty ? ', $middle' : ''}',
      excludeSemantics: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: rigSize + 8,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The rig icon is centred on its position, so the travel band
                // is inset by half its width at each end to keep it on-strip.
                final travel = (constraints.maxWidth - rigSize).clamp(
                  0.0,
                  double.infinity,
                );
                final x = travel * pct;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Track
                    Positioned(
                      left: rigSize / 2,
                      right: rigSize / 2,
                      top: rigSize / 2 - 2,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: HaulColors.line,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Distance covered
                    Positioned(
                      left: rigSize / 2,
                      top: rigSize / 2 - 2,
                      child: AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 1200),
                        curve: Curves.linear,
                        height: 4,
                        width: x,
                        decoration: BoxDecoration(
                          color: HaulColors.brand,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    _cap(left: 0, hit: true),
                    _cap(right: 0, hit: pct >= 0.99),
                    AnimatedPositioned(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 1200),
                      curve: Curves.linear,
                      left: x,
                      top: 0,
                      child: Container(
                        width: rigSize,
                        height: rigSize,
                        decoration: BoxDecoration(
                          color: HaulColors.brand,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          size: 17,
                          color: HaulColors.asphalt,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(from, style: HaulText.small)),
              if (middle != null && middle!.isNotEmpty)
                Expanded(
                  flex: 2,
                  child: Text(
                    middle!,
                    textAlign: TextAlign.center,
                    style: HaulText.small,
                  ),
                ),
              Expanded(
                child: Text(
                  to,
                  textAlign: TextAlign.end,
                  style: HaulText.small,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cap({double? left, double? right, required bool hit}) {
    return Positioned(
      left: left == null ? null : left + 9,
      right: right == null ? null : right + 9,
      top: 9,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: hit ? HaulColors.brand : HaulColors.raised,
          shape: BoxShape.circle,
          border: Border.all(
            color: hit ? HaulColors.brand : HaulColors.line,
            width: 2,
          ),
        ),
      ),
    );
  }
}

/// The pulsing "we're hearing from this driver" dot. Purely decorative; the
/// text beside it always says the same thing in words.
class PingDot extends StatefulWidget {
  const PingDot({super.key, this.live = true, this.size = 10});

  final bool live;
  final double size;

  @override
  State<PingDot> createState() => _PingDotState();
}

class _PingDotState extends State<PingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Never loop an animation for someone who asked the OS to stop them.
    final animate = widget.live && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didUpdateWidget(PingDot old) {
    super.didUpdateWidget(old);
    if (old.live != widget.live) didChangeDependencies();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.live ? HaulColors.go : HaulColors.grey;
    return ExcludeSemantics(
      child: SizedBox(
        width: widget.size + 10,
        height: widget.size + 10,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (widget.live)
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final t = _c.value;
                    return Opacity(
                      opacity: (0.7 * (1 - t)).clamp(0.0, 1.0),
                      child: Container(
                        width: widget.size + 10 * t,
                        height: widget.size + 10 * t,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: color),
                        ),
                      ),
                    );
                  },
                ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
