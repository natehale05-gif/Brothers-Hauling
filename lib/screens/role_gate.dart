import 'package:flutter/material.dart';

import '../models/role.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import '../widgets/brand_mark.dart';

/// Sign-in. Pick an access level; everything downstream keys off it.
class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  static ({Color background, Color foreground, IconData icon}) styleFor(
    Role role,
  ) => switch (role) {
    Role.admin => (
      background: HaulColors.violetWash,
      foreground: HaulColors.violet,
      icon: Icons.shield_outlined,
    ),
    Role.manager => (
      background: HaulColors.brandWash,
      foreground: HaulColors.brand,
      icon: Icons.assignment_outlined,
    ),
    Role.employee => (
      background: HaulColors.goWash,
      foreground: HaulColors.go,
      icon: Icons.local_shipping_outlined,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      backgroundColor: HaulColors.asphalt,
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
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BrandMark(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Pick an access level to sign in.',
                    style: HaulText.secondary,
                  ),
                  const SizedBox(height: 20),
                  for (final role in Role.values) ...[
                    _RoleCard(role: role, onPick: () => state.enter(role)),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Location is shared with dispatch only while the app is '
                    'open. Close it and reporting stops.',
                    style: HaulText.small,
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
    final s = RoleGate.styleFor(role);

    return Semantics(
      button: true,
      label: 'Sign in as ${role.label}',
      hint: role.blurb,
      excludeSemantics: true,
      child: Material(
        color: HaulColors.surface,
        borderRadius: BorderRadius.circular(HaulSpace.radius),
        child: InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(HaulSpace.radius),
          focusColor: HaulColors.brand.withValues(alpha: 0.16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: HaulColors.line),
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
                      Text(role.label.toUpperCase(), style: HaulText.heading),
                      const SizedBox(height: 4),
                      Text(role.blurb, style: HaulText.small),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: HaulColors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
