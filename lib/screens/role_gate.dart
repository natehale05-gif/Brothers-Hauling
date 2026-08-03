import 'package:flutter/material.dart';

import '../models/role.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/primitives.dart';
import '../widgets/theme_toggle.dart';

/// Sign-in. Pick an access level; everything downstream keys off it.
class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  /// Takes the palette rather than reading it, so it stays a pure function and
  /// callers that already have one don't pay for a second lookup.
  ///
  /// [tone] is the same distinction expressed for a [Pill], which is how the
  /// top bar's role chip stays the same colour as the role's card here without
  /// the two agreeing by coincidence.
  static ({Color background, Color foreground, IconData icon, PillTone tone})
  styleFor(Role role, HaulPalette hc) => switch (role) {
    Role.admin => (
      background: hc.violetWash,
      foreground: hc.violet,
      icon: Icons.shield_outlined,
      tone: PillTone.violet,
    ),
    Role.manager => (
      background: hc.brandWash,
      foreground: hc.brand,
      icon: Icons.assignment_outlined,
      tone: PillTone.brand,
    ),
    Role.employee => (
      background: hc.goWash,
      foreground: hc.go,
      icon: Icons.local_shipping_outlined,
      tone: PillTone.go,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    return Scaffold(
      backgroundColor: hc.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: HaulSpace.maxContentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The parent Column stretches its children; the lockup keeps
                  // its own width.
                  Row(
                    children: [
                      const Expanded(child: BrandMark()),
                      // Reachable before signing in: someone squinting at a
                      // white screen in a yard should not have to pick a role
                      // first to be able to turn it down.
                      const ThemeToggle(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Pick an access level to sign in.', style: ht.secondary),
                  const SizedBox(height: 20),
                  for (final role in Role.values) ...[
                    _RoleCard(role: role, onPick: () => state.enter(role)),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Location is shared with dispatch only while the app is '
                    'open. Close it and reporting stops.',
                    style: ht.small,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.onPick});

  final Role role;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final s = RoleGate.styleFor(role, hc);

    return Semantics(
      button: true,
      label: 'Sign in as ${role.label}',
      hint: role.blurb,
      excludeSemantics: true,
      child: Material(
        color: hc.surface,
        borderRadius: BorderRadius.circular(HaulSpace.radius),
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(HaulSpace.radius),
          focusColor: hc.brand.withValues(alpha: 0.16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: hc.line),
              borderRadius: BorderRadius.circular(HaulSpace.radius),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: s.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(s.icon, size: 23, color: s.foreground),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(role.label.toUpperCase(), style: ht.heading),
                      const SizedBox(height: 4),
                      Text(role.blurb, style: ht.small),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: hc.inkSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
