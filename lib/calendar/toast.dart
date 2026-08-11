import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'calendar_theme.dart';

/// What the app says back.
///
/// The state has been saying these all along — a refused price, a job put on
/// the board, a photo filed, a close-out blocked — and until now nothing drew
/// them. An app that answers into the void is worse than one that says
/// nothing, because the silence reads as "that worked".
///
/// Over everything, including an open job sheet, since most of what it has to
/// say is about the button just pressed on one.
class AppToast extends StatelessWidget {
  const AppToast({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final said = AppScope.of(context).toast;
    if (said == null) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: IgnorePointer(
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: p.label,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                said,
                textAlign: TextAlign.center,
                style: t.body.copyWith(fontSize: 14, color: p.bg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
