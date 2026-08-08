import 'package:flutter/material.dart';

import '../data/accounts.dart';
import '../models/crew_member.dart';
import '../models/role.dart';
import '../state/app_state.dart';
import 'calendar_state.dart';
import 'calendar_theme.dart';

/// Who can get in, and at what level.
///
/// An owner's screen. The rule about who may hand out which level lives in
/// [Role.canHire] and is enforced in the state, not here — this only offers
/// what is allowed, which is a different thing from stopping what is not.
Future<void> showLogins(BuildContext context) {
  final cal = CalendarScope.read(context);
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CalendarScope(state: cal, child: const LoginsScreen()),
    ),
  );
}

class LoginsScreen extends StatelessWidget {
  const LoginsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);
    final accounts = app.accounts;
    final samples = app.sampleAccounts;

    return Scaffold(
      backgroundColor: p.groupedBg,
      appBar: AppBar(
        backgroundColor: p.groupedBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Logins', style: t.navTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Done', style: t.body.copyWith(color: p.accent)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (samples.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '${samples.length} '
                  '${samples.length == 1 ? 'login is' : 'logins are'} still on '
                  'the password this app printed on the sign-in screen. '
                  'Anybody who can read that screen can get in. Set a real '
                  'password on each, or remove the ones nobody needs.',
                  style: t.secondary.copyWith(fontSize: 13, color: p.label),
                ),
              ),
            ),
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Nobody can sign in to this device.',
                textAlign: TextAlign.center,
                style: t.secondary,
              ),
            ),
          for (final account in accounts)
            _AccountRow(account: account, app: app),
          const SizedBox(height: 16),
          _AddLogin(app: app),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.app});

  final Account account;
  final AppState app;

  CrewMember? get _member =>
      app.crew.where((c) => c.id == account.crewId).firstOrNull;

  Future<void> _setPassword(BuildContext context) async {
    final chosen = await _askForPassword(
      context,
      title: 'New password for ${account.username}',
    );
    if (chosen == null || !context.mounted) return;

    final member = _member;
    if (member == null) return;
    await app.setLogin(
      member: member,
      username: account.username,
      password: chosen,
    );
  }

  Future<void> _remove(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${account.username}?'),
        content: const Text(
          'They stop being able to sign in. Their jobs, hours and photos stay '
          'exactly where they are — this only takes away the way in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await app.removeLogin(account.username);
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final member = _member;
    final isMe = app.session?.username == account.username;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.username,
                        overflow: TextOverflow.ellipsis,
                        style: t.body.copyWith(fontSize: 15),
                      ),
                    ),
                    if (isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          '(you)',
                          style: t.secondary.copyWith(fontSize: 13),
                        ),
                      ),
                  ],
                ),
                Text(
                  '${account.role.label}'
                  '${member == null ? '' : ' · ${member.name}'}',
                  style: t.secondary.copyWith(fontSize: 13),
                ),
                if (account.sample)
                  Text(
                    'Still on the printed password',
                    style: t.secondary.copyWith(fontSize: 13, color: p.accent),
                  ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Set a password for ${account.username}',
            onTap: () => _setPassword(context),
            excludeSemantics: true,
            child: IconButton(
              onPressed: () => _setPassword(context),
              tooltip: 'Set a password',
              icon: Icon(Icons.key_rounded, size: 20, color: p.accent),
            ),
          ),
          // Removing your own login would sign you out of the screen you are
          // standing on, and leave a board with no owner if you were the last.
          if (!isMe)
            Semantics(
              button: true,
              label: 'Remove ${account.username}',
              onTap: () => _remove(context),
              excludeSemantics: true,
              child: IconButton(
                onPressed: () => _remove(context),
                tooltip: 'Remove',
                icon: Icon(
                  Icons.person_remove_rounded,
                  size: 20,
                  color: p.secondaryLabel,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddLogin extends StatefulWidget {
  const _AddLogin({required this.app});

  final AppState app;

  @override
  State<_AddLogin> createState() => _AddLoginState();
}

class _AddLoginState extends State<_AddLogin> {
  final TextEditingController _username = TextEditingController();
  CrewMember? _member;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  /// Everybody on the roster who has no login yet.
  List<CrewMember> get _available => widget.app.crew
      .where((c) => !widget.app.hasLogin(c.id))
      .where((c) => widget.app.hirableRoles.contains(c.role))
      .toList();

  Future<void> _add() async {
    final member = _member;
    if (member == null) return;

    final password = await _askForPassword(
      context,
      title: 'Password for ${_username.text.trim()}',
    );
    if (password == null || !mounted) return;

    final ok = await widget.app.setLogin(
      member: member,
      username: _username.text,
      password: password,
    );
    if (ok && mounted) {
      setState(() {
        _username.clear();
        _member = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final available = _available;

    if (!widget.app.canManageServer) {
      return Text(
        'Only an owner can hand out logins.',
        style: t.secondary.copyWith(fontSize: 13),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Give somebody a login',
            style: t.bodyStrong.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'A login is tied to somebody already on the roster, so their jobs '
            'and hours are theirs the moment they sign in. The level comes '
            'from the roster too — change it there, not here.',
            style: t.secondary.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (available.isEmpty)
            Text(
              'Everybody you can hand a login to already has one.',
              style: t.secondary.copyWith(fontSize: 13),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final member in available)
                  Semantics(
                    button: true,
                    selected: _member?.id == member.id,
                    label: 'Give ${member.name} a login',
                    onTap: () => setState(() => _member = member),
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => setState(() => _member = member),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _member?.id == member.id ? p.accent : p.fill,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${member.name} · ${member.role.label}',
                          style: t.eventTitle.copyWith(
                            fontSize: 12,
                            color: _member?.id == member.id
                                ? p.onAccent
                                : p.label,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              style: t.body.copyWith(fontSize: 15),
              decoration: InputDecoration(
                labelText: 'Username',
                labelStyle: t.secondary,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: 'Add this login',
              onTap: _add,
              excludeSemantics: true,
              child: FilledButton(
                onPressed: _member == null || _username.text.trim().isEmpty
                    ? null
                    : _add,
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(
                  'Add login',
                  style: t.bodyStrong.copyWith(fontSize: 15, color: p.onAccent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks for a password twice, and refuses anything too short to be one.
Future<String?> _askForPassword(
  BuildContext context, {
  required String title,
}) => showDialog<String>(
  context: context,
  builder: (context) => _PasswordDialog(title: title),
);

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.title});

  /// Names whose password is being set, so an owner working down a list of
  /// crew knows which one this box belongs to.
  final String title;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _again = TextEditingController();
  String? _problem;

  /// Short enough to be typed with cold hands, long enough to be worth typing.
  static const int _minimum = 6;

  @override
  void dispose() {
    _first.dispose();
    _again.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _first.text;
    if (password.length < _minimum) {
      setState(() => _problem = 'At least $_minimum characters.');
      return;
    }
    if (password != _again.text) {
      setState(() => _problem = 'Those two do not match.');
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _first,
            obscureText: true,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          TextField(
            controller: _again,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Again'),
          ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _problem!,
                  style: TextStyle(color: CalPalette.of(context).accent),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Set it')),
      ],
    );
  }
}
