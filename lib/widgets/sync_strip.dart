import 'package:flutter/material.dart';

import '../data/board_repository.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import 'primitives.dart';

/// Says whether the work on this device has actually reached dispatch.
///
/// The whole point is to never imply more than is true. "Saved" is a lie when a
/// change is sitting in a queue in a dead zone — a driver who closes a job and
/// sees a tick will assume they are done and stop caring, and if that change
/// later fails they find out at payroll. So the three states are stated plainly,
/// and the only one that reads as finished is the one that is.
///
/// Hidden entirely when everything is settled: an always-on green banner is
/// noise the eye stops seeing, which makes it useless on the day it turns red.
class SyncStrip extends StatelessWidget {
  const SyncStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final sync = state.syncState;

    if (!state.storageIsDurable) return const _StorageWarning();
    if (sync.settled) return const SizedBox.shrink();

    final failed = sync.failed > 0;
    final colour = failed ? HaulColors.alert : HaulColors.brand;
    final message = _message(sync);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      decoration: BoxDecoration(
        color: failed ? HaulColors.alertWash : HaulColors.brandWash,
        border: const Border(bottom: BorderSide(color: HaulColors.line)),
      ),
      child: Row(
        children: [
          // Only the message is collapsed into one announced node. Wrapping
          // the whole row would take the button's semantics with it and leave
          // a screen reader user able to hear the problem but not fix it.
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: message,
              excludeSemantics: true,
              container: true,
              child: Row(
                children: [
                  Icon(
                    failed
                        ? Icons.error_outline_rounded
                        : Icons.cloud_upload_outlined,
                    size: 18,
                    color: colour,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message,
                      style: HaulText.small.copyWith(
                        fontSize: 13,
                        color: colour,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Action(failed: failed),
        ],
      ),
    );
  }

  static String _message(SyncState sync) {
    if (sync.failed > 0) {
      final n = sync.failed;
      return '${n == 1 ? '1 change' : '$n changes'} dispatch never got. '
          'Tap to try again.';
    }
    final n = sync.pending;
    final count = n == 1 ? '1 change' : '$n changes';
    return sync.offline
        ? '$count saved on this phone — no signal to send them yet.'
        : '$count saved on this phone, sending…';
  }
}

/// Shown when the device gave us nowhere to write.
///
/// This is the one failure the driver genuinely cannot work around, so it says
/// exactly what the consequence is rather than something reassuring.
class _StorageWarning extends StatelessWidget {
  const _StorageWarning();

  @override
  Widget build(BuildContext context) {
    const message =
        'This phone will not let the app save anything. Your work is kept '
        'until you close the app, and then it is gone.';

    return Semantics(
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        decoration: const BoxDecoration(
          color: HaulColors.alertWash,
          border: Border(bottom: BorderSide(color: HaulColors.line)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: HaulColors.alert,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: HaulText.small.copyWith(
                  fontSize: 13,
                  color: HaulColors.alert,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Semantics(
      button: true,
      label: failed
          ? 'Try sending the failed changes again'
          : 'Send the saved changes now',
      excludeSemantics: true,
      child: TextButton(
        onPressed: () => failed ? state.retryFailedSync() : state.syncNow(),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, HaulSpace.tap),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: failed ? HaulColors.alert : HaulColors.brand,
        ),
        child: Text(
          failed ? 'RETRY' : 'SEND NOW',
          style: HaulText.action.copyWith(
            fontSize: 12,
            color: failed ? HaulColors.alert : HaulColors.brand,
          ),
        ),
      ),
    );
  }
}

/// A small mark on a job card whose changes have not reached dispatch.
///
/// Card-level rather than only a global banner, because "3 changes pending"
/// does not tell a driver *which* job to worry about when they are looking at
/// one specific card.
class UnsyncedChip extends StatelessWidget {
  const UnsyncedChip({super.key});

  @override
  Widget build(BuildContext context) {
    return const Pill(
      label: 'Not sent yet',
      icon: Icons.cloud_upload_outlined,
      semanticLabel: 'Changes to this job have not reached dispatch yet',
    );
  }
}
