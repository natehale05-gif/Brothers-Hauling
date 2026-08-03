import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/haul_theme.dart';

/// Hold-to-commit. Volunteering for a load is a real commitment and a phone in
/// a truck gets bumped, so a stray tap must not sign anyone up for a job.
///
/// Three ways to fire it, because "press and hold" alone locks out a lot of
/// people:
///
///  * **Pointer** — press and hold for [holdDuration].
///  * **Keyboard** — hold Enter or Space; the same fill runs.
///  * **Assistive tech / reduced-motion** — a single activation opens a confirm
///    dialog instead. Screen reader and switch users get the same protection
///    against a mis-fire without having to sustain a gesture at all.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.idleLabel,
    required this.blockedLabel,
    required this.onConfirmed,
    required this.confirmTitle,
    required this.confirmMessage,
    this.enabled = true,
    this.holdDuration = const Duration(milliseconds: 850),
  });

  final String idleLabel;

  /// Shown instead of [idleLabel] when [enabled] is false, and it says *why* —
  /// a disabled control with no reason is a dead end.
  final String blockedLabel;

  final VoidCallback onConfirmed;
  final String confirmTitle;
  final String confirmMessage;
  final bool enabled;
  final Duration holdDuration;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener(_onStatus);

  bool _keyHeld = false;

  /// A completed hold is followed by a pointer-up, which the tap recognizer
  /// reports as a tap. Without this the driver would claim the job and then be
  /// asked whether they meant to.
  bool _justFired = false;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _fill.value = 0;
      _keyHeld = false;
      _justFired = true;
      HapticFeedback.mediumImpact();
      widget.onConfirmed();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  void _startHold() {
    if (!widget.enabled) return;
    _justFired = false;
    _fill.forward(from: 0);
  }

  void _cancelHold() {
    if (_fill.isAnimating) _fill.stop();
    _fill.value = 0;
  }

  /// The no-gesture path: confirm in a dialog instead of sustaining a press.
  Future<void> _confirmViaDialog() async {
    if (!widget.enabled) return;
    if (_justFired) {
      // This is the release of a hold that already committed.
      _justFired = false;
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.confirmTitle, style: HaulText.heading),
        content: Text(widget.confirmMessage, style: HaulText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: HaulColors.brand,
              foregroundColor: HaulColors.asphalt,
            ),
            child: const Text('Yes, take it'),
          ),
        ],
      ),
    );
    if (ok ?? false) widget.onConfirmed();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isActivator =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isActivator) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      _keyHeld = true;
      _startHold();
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      if (_keyHeld) {
        _keyHeld = false;
        _cancelHold();
      }
      return KeyEventResult.handled;
    }
    // KeyRepeatEvent: the hold is already running, swallow it.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Screen readers and switch control can't express "keep holding", and
    // reduced-motion users shouldn't have to watch a bar fill. Both get the
    // dialog.
    final noGestures =
        MediaQuery.accessibleNavigationOf(context) ||
        MediaQuery.disableAnimationsOf(context);

    final label = widget.enabled ? widget.idleLabel : widget.blockedLabel;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: label,
      hint: widget.enabled
          ? (noGestures
                ? 'Activate to confirm'
                : 'Press and hold to confirm, or activate for a confirmation prompt')
          : null,
      onTap: widget.enabled ? _confirmViaDialog : null,
      excludeSemantics: true,
      child: Focus(
        onKeyEvent: widget.enabled ? _onKey : null,
        canRequestFocus: widget.enabled,
        child: Builder(
          builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: noGestures ? null : (_) => _startHold(),
              onTapUp: noGestures ? null : (_) => _cancelHold(),
              onTapCancel: noGestures ? null : _cancelHold,
              // A plain tap on the accessible path, and a safety net on the
              // gesture path for anyone who taps instead of holding.
              onTap: widget.enabled ? _confirmViaDialog : null,
              child: MouseRegion(
                cursor: widget.enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.forbidden,
                child: AnimatedBuilder(
                  animation: _fill,
                  builder: (context, _) {
                    final pct = _fill.value;
                    final armed = pct > 0.55;
                    return Container(
                      height: HaulSpace.tap + 4,
                      decoration: BoxDecoration(
                        color: HaulColors.raised,
                        border: Border(
                          top: BorderSide(
                            color: focused ? HaulColors.brand : HaulColors.line,
                            width: focused ? 3 : 1,
                          ),
                        ),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(HaulSpace.radius - 1),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // The fill doubles as the progress indicator; the
                          // hazard stripes are the same language as the yard.
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: pct,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      HaulColors.brand,
                                      Color(0xFFC9A800),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.enabled
                                        ? Icons.bolt_rounded
                                        : Icons.lock_outline_rounded,
                                    size: 17,
                                    color: armed
                                        ? HaulColors.asphalt
                                        : HaulColors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      (pct > 0 && pct < 1
                                              ? 'Keep holding'
                                              : label)
                                          .toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style: HaulText.action.copyWith(
                                        color: armed
                                            ? HaulColors.asphalt
                                            : widget.enabled
                                            ? HaulColors.white
                                            : HaulColors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
