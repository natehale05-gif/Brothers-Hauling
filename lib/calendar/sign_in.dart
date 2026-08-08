import 'package:flutter/material.dart';

import '../data/accounts.dart';
import '../state/app_state.dart';
import 'calendar_theme.dart';

/// The way in.
///
/// Shown instead of the calendar until somebody signs in, because what the
/// app shows depends entirely on who is looking: an owner sees what a job
/// bills at and can change it, a manager sees the money and not the editing,
/// and a driver sees neither. A calendar that opened first and asked later
/// would have to guess, and guessing means showing somebody a figure that is
/// not theirs to see.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final app = AppScope.read(context);
    await app.signIn(_username.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _password.clear();
    });
  }

  /// Fills the box in for a sample login, so a demo is one tap rather than
  /// two fields of typing on a phone.
  void _use(String username) {
    _username.text = username;
    _password.text = kSamplePassword;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final app = AppScope.of(context);
    final samples = app.sampleAccounts;

    return Scaffold(
      backgroundColor: p.groupedBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Brothers Hauling',
                      textAlign: TextAlign.center,
                      style: t.largeTitle.copyWith(fontSize: 28),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sign in to see the board.',
                    textAlign: TextAlign.center,
                    style: t.secondary,
                  ),
                  const SizedBox(height: 24),
                  _Field(
                    label: 'Username',
                    controller: _username,
                    autofocus: true,
                    onSubmit: _passwordFocus.requestFocus,
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: 'Password',
                    controller: _password,
                    focus: _passwordFocus,
                    obscure: !_showPassword,
                    onSubmit: _submit,
                    trailing: Semantics(
                      button: true,
                      label: _showPassword ? 'Hide password' : 'Show password',
                      onTap: () =>
                          setState(() => _showPassword = !_showPassword),
                      excludeSemantics: true,
                      child: IconButton(
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                          color: p.secondaryLabel,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Semantics(
                    button: true,
                    label: 'Sign in',
                    onTap: _submit,
                    excludeSemantics: true,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(
                        'Sign in',
                        style: t.bodyStrong.copyWith(color: p.onAccent),
                      ),
                    ),
                  ),
                  if (samples.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      'Sample logins',
                      style: t.bodyStrong.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'This device has no real accounts on it yet, so it made '
                      'these. The password is "$kSamplePassword". Replace them '
                      'from Logins before anybody uses this for real.',
                      style: t.secondary.copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    for (final account in samples)
                      _SampleRow(
                        account: account,
                        onTap: () => _use(account.username),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.focus,
    this.obscure = false,
    this.autofocus = false,
    this.trailing,
    this.onSubmit,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode? focus;
  final bool obscure;
  final bool autofocus;
  final Widget? trailing;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return TextField(
      controller: controller,
      focusNode: focus,
      autofocus: autofocus,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: onSubmit == null
          ? TextInputAction.done
          : TextInputAction.next,
      onSubmitted: (_) => onSubmit?.call(),
      style: t.body.copyWith(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: t.secondary,
        filled: true,
        fillColor: p.card,
        suffixIcon: trailing,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.separator),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.separator),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
      ),
    );
  }
}

class _SampleRow extends StatelessWidget {
  const _SampleRow({required this.account, required this.onTap});

  final Account account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: 'Use the ${account.role.label} sample login',
        onTap: onTap,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      Text(
                        account.username,
                        style: t.body.copyWith(fontSize: 15),
                      ),
                      Text(
                        account.role.blurb,
                        style: t.secondary.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  account.role.label,
                  style: t.secondary.copyWith(color: p.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
