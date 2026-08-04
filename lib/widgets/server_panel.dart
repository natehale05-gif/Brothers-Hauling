import 'package:flutter/material.dart';

import '../data/accounts.dart';
import '../models/crew_member.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import 'primitives.dart';

/// Turning the owner's machine into the board everybody else reads.
///
/// The honest version of "no cloud": the data sits on one laptop on the yard's
/// network, and this says out loud what that costs — the laptop has to be awake
/// and on the same network. Crew devices keep working offline in the meantime,
/// because the outbox was built for exactly that.
class ServerPanel extends StatelessWidget {
  const ServerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    if (!state.canManageServer) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hc.surface,
          border: Border.all(color: state.serving ? hc.go : hc.line),
          borderRadius: BorderRadius.circular(HaulSpace.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('THIS DEVICE', style: ht.blockTitle),
                  ),
                ),
                if (state.serving)
                  Pill.go(label: 'Serving')
                else
                  const Pill(label: 'Off'),
              ],
            ),
            const SizedBox(height: 8),

            if (!state.canServe)
              Text(
                'A browser cannot be the dispatch server. Run the app on the '
                'office laptop and the crew can sync to it from there.',
                style: ht.small,
              )
            else ...[
              Text(
                state.serving
                    ? 'The crew can sign in to this machine from the yard '
                          'network. It has to stay awake to answer them — a '
                          'closed laptop is a board nobody can reach, though '
                          'their phones keep working and catch up after.'
                    : 'Hold the board here and let the crew sync to it. '
                          'Nothing leaves the yard network, and nobody needs '
                          'an account anywhere else.',
                style: ht.small,
              ),
              const SizedBox(height: 12),

              if (state.serving && state.serverAddresses.isNotEmpty) ...[
                Text('THEY TYPE IN', style: ht.eyebrow),
                const SizedBox(height: 4),
                for (final address in state.serverAddresses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: SelectableText(
                      '$address:${state.serverPort}',
                      style: ht.mono.copyWith(color: hc.ink, fontSize: 15),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  state.serverAddresses.length > 1
                      ? 'More than one because this machine is on more than '
                            'one network. If the first does not work, try the '
                            'next.'
                      : 'Same Wi-Fi as this machine.',
                  style: ht.small.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 12),
              ],

              _ServeButton(on: state.serving),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServeButton extends StatelessWidget {
  const _ServeButton({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    return Semantics(
      button: true,
      label: on
          ? 'Stop serving the board from this device'
          : 'Serve the board from this device',
      onTap: () => state.setServing(!on),
      excludeSemantics: true,
      child: OutlinedButton.icon(
        onPressed: () => state.setServing(!on),
        icon: Icon(
          on ? Icons.stop_circle_outlined : Icons.dns_outlined,
          size: 18,
          color: on ? hc.alert : hc.brand,
        ),
        label: Text(
          on ? 'STOP SERVING' : 'SERVE FROM THIS DEVICE',
          style: ht.action.copyWith(
            fontSize: 12,
            color: on ? hc.alert : hc.brand,
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, HaulSpace.tap),
          side: BorderSide(color: on ? hc.alert : hc.brand),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
          ),
        ),
      ),
    );
  }
}

/// Giving somebody a way in, or taking it away.
///
/// The password is typed here, hashed, and never held: from this point the
/// owner's machine holds a PBKDF2 digest and no way back to what was typed.
Future<void> showLoginSheet(BuildContext context, CrewMember member) {
  final state = AppScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => AppScope(
      state: state,
      child: _LoginSheet(member: member),
    ),
  );
}

class _LoginSheet extends StatefulWidget {
  const _LoginSheet({required this.member});

  final CrewMember member;

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _username = TextEditingController(
    text: _existing?.username ?? _suggested,
  );
  final _password = TextEditingController();
  bool _saving = false;

  String get _suggested {
    final first = widget.member.name.split(RegExp(r'\s+')).first;
    return first.toLowerCase();
  }

  Account? get _existing {
    for (final account in AppScope.read(context).accounts) {
      if (account.crewId == widget.member.id) return account;
    }
    return null;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    final ok = await state.setLogin(
      member: widget.member,
      username: _username.text,
      password: _password.text,
    );
    if (!mounted) return;
    if (ok) {
      navigator.pop();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final existing = _existing;

    return AlertDialog(
      backgroundColor: hc.surface,
      title: Text('${widget.member.name}’s login', style: ht.heading),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                existing == null
                    ? 'They will use this to sign in on their own phone.'
                    : 'Setting a new password replaces the old one. Anything '
                          'they are already signed in on keeps working until '
                          'you take the login away.',
                style: ht.small,
              ),
              const SizedBox(height: 14),
              HaulTextField(
                controller: _username,
                label: 'Signs in as',
                hint: 'kara',
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'They need a name.' : null,
              ),
              const SizedBox(height: 12),
              HaulTextField(
                controller: _password,
                label: 'Password',
                obscure: true,
                helper:
                    'Stored scrambled. Nobody — including you — can read it '
                    'back off this machine afterwards, so write it down '
                    'somewhere before you close this.',
                validator: (v) =>
                    (v ?? '').length < 6 ? 'Six characters or more.' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            onPressed: _saving
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    await state.removeLogin(existing.username);
                    if (mounted) navigator.pop();
                  },
            child: Text(
              'TAKE IT AWAY',
              style: ht.action.copyWith(fontSize: 12, color: hc.alert),
            ),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: ht.action.copyWith(fontSize: 13, color: hc.inkSoft),
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: hc.brand,
            foregroundColor: hc.onBrand,
            minimumSize: const Size(0, HaulSpace.tap),
          ),
          child: Text(
            'SAVE',
            style: ht.action.copyWith(fontSize: 12, color: hc.onBrand),
          ),
        ),
      ],
    );
  }
}
