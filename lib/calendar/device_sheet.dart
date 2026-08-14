import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'calendar_theme.dart';

/// Whether the work on this device has got anywhere yet.
///
/// The whole offline design rests on never claiming a change has reached
/// dispatch until it has. That promise is only worth anything if somebody can
/// see it, so this says how many changes are still on the device, how many the
/// server refused, and when the last one landed.
class SyncRow extends StatelessWidget {
  const SyncRow({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final app = AppScope.of(context);
    final sync = app.syncState;

    final IconData icon;
    final Color colour;
    final String status;

    if (sync.failed > 0) {
      icon = Icons.error_outline_rounded;
      colour = p.accent;
      status =
          '${sync.failed} '
          '${sync.failed == 1 ? 'change' : 'changes'} could not be sent. '
          'They are still here — nothing has been thrown away.';
    } else if (sync.offline) {
      icon = Icons.cloud_off_rounded;
      colour = p.secondaryLabel;
      status = sync.pending == 0
          ? 'No signal. Everything so far is saved on this device.'
          : '${sync.pending} '
                '${sync.pending == 1 ? 'change' : 'changes'} saved on this '
                'device, waiting for signal.';
    } else if (sync.pending > 0) {
      icon = Icons.cloud_upload_rounded;
      colour = p.secondaryLabel;
      status =
          '${sync.pending} '
          '${sync.pending == 1 ? 'change' : 'changes'} saved on this device, '
          'going out now.';
    } else {
      icon = Icons.cloud_done_rounded;
      colour = p.secondaryLabel;
      status = 'Everything is saved and sent.';
    }

    return _Block(
      icon: icon,
      colour: colour,
      title: 'This device',
      body: status,
    );
  }
}

/// The owner's machine as the board everybody else reads.
///
/// Only an owner sees it, and only on a platform that can listen on a port —
/// the web cannot, and says so rather than offering a switch that does
/// nothing.
class ServerRow extends StatelessWidget {
  const ServerRow({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);

    if (!app.canManageServer) return const SizedBox.shrink();

    if (!app.canServe) {
      return const _Block(
        icon: Icons.dns_outlined,
        title: 'Serving the crew',
        body:
            'A browser cannot listen on a port, so this device cannot be '
            'the one the crew syncs to. The desktop and phone builds can.',
      );
    }

    final serving = app.serving;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                serving ? Icons.dns_rounded : Icons.dns_outlined,
                size: 18,
                color: serving ? p.accent : p.secondaryLabel,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Serving the crew',
                  style: t.bodyStrong.copyWith(fontSize: 15),
                ),
              ),
              Semantics(
                button: true,
                checked: serving,
                label: serving
                    ? 'Stop serving the board'
                    : 'Serve the board from this device',
                onTap: () => app.setServing(!serving),
                excludeSemantics: true,
                child: Switch(
                  value: serving,
                  onChanged: app.setServing,
                  activeThumbColor: Colors.white,
                  activeTrackColor: p.accent,
                ),
              ),
            ],
          ),
          Semantics(
            liveRegion: true,
            child: Text(
              serving
                  ? 'The crew can reach this board on port ${app.serverPort}.'
                  : 'Off. The crew have whatever they last synced.',
              style: t.secondary.copyWith(fontSize: 13),
            ),
          ),
          if (serving && app.serverAddresses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                app.serverAddresses
                    .map((a) => '$a:${app.serverPort}')
                    .join('\n'),
                style: t.secondary.copyWith(fontSize: 13, color: p.label),
              ),
            ),
          if (app.accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Nobody has a login yet, so a running server would refuse '
                'everybody — which looks exactly like a broken network from '
                'the yard.',
                style: t.secondary.copyWith(fontSize: 13, color: p.accent),
              ),
            ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.icon,
    required this.title,
    required this.body,
    this.colour,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colour ?? p.secondaryLabel),
              const SizedBox(width: 8),
              // Expanded, not bare: at large text on a narrow phone a title
              // this long is wider than the sheet, and a Row will not wrap it.
              Expanded(
                child: Text(title, style: t.bodyStrong.copyWith(fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Semantics(
            liveRegion: true,
            child: Text(body, style: t.secondary.copyWith(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
