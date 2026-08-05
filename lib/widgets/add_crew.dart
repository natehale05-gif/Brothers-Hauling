import 'package:flutter/material.dart';

import '../models/role.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';
import 'primitives.dart';

/// Opens the hiring form. Only rendered when the signed-in role can hire.
class AddCrewButton extends StatelessWidget {
  const AddCrewButton({super.key});

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    // A manager staffs their own crew; an owner can also make managers and
    // owners. Saying which up front beats a form that rejects you afterwards.
    final what = state.hirableRoles.length == 1
        ? 'Add an employee'
        : 'Add crew';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: what,
        onTap: () => showAddCrewSheet(context),
        excludeSemantics: true,
        child: OutlinedButton.icon(
          onPressed: () => showAddCrewSheet(context),
          icon: Icon(
            Icons.person_add_alt_1_outlined,
            size: 18,
            color: hc.brand,
          ),
          label: Text(
            what.toUpperCase(),
            style: ht.action.copyWith(fontSize: 12, color: hc.brand),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, HaulSpace.tap),
            side: BorderSide(color: hc.brand),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showAddCrewSheet(BuildContext context) {
  final state = AppScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => AppScope(state: state, child: const _AddCrewDialog()),
  );
}

/// A selectable row, hand-rolled rather than a [RadioListTile]/[CheckboxListTile].
///
/// Those two carry Material's own selection plumbing, which is both deprecated
/// in this Flutter and hard to give a 48pt target and a single merged
/// announcement. This states its own selected state, which is what a screen
/// reader reads out.
class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.selected,
    required this.exclusive,
    required this.title,
    required this.semanticLabel,
    required this.onTap,
    this.subtitle,
  });

  final bool selected;

  /// True for "one of these", false for "any of these" — which changes both
  /// the mark drawn and how a screen reader groups it.
  final bool exclusive;
  final String title;
  final String? subtitle;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: exclusive,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
        child: Container(
          constraints: const BoxConstraints(minHeight: HaulSpace.tap),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected
                      ? (exclusive
                            ? Icons.radio_button_checked
                            : Icons.check_box_outlined)
                      : (exclusive
                            ? Icons.radio_button_unchecked
                            : Icons.check_box_outline_blank),
                  size: 20,
                  color: selected ? hc.brand : hc.inkSoft,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: ht.bodyStrong.copyWith(
                        color: selected ? hc.brand : hc.ink,
                      ),
                    ),
                    if (subtitle != null) Text(subtitle!, style: ht.small),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddCrewDialog extends StatefulWidget {
  const _AddCrewDialog();

  @override
  State<_AddCrewDialog> createState() => _AddCrewDialogState();
}

class _AddCrewDialogState extends State<_AddCrewDialog> {
  final _name = TextEditingController();
  final _unit = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// Resolved in build against what this user may hand out, rather than in a
  /// field initialiser — the inherited state is not readable that early.
  Role? _role;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _submit(Role role) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final state = AppScope.of(context);
    final ok = await state.hire(name: _name.text, role: role, unit: _unit.text);
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);
    final roles = state.hirableRoles;
    final role = _role ?? roles.first;

    return AlertDialog(
      backgroundColor: hc.surface,
      title: Text('Add crew', style: ht.heading),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HaulTextField(
                controller: _name,
                label: 'Name',
                hint: 'Dale Whitlow',
                autofocus: true,
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'A name is the one thing this needs.'
                    : null,
              ),
              const SizedBox(height: 14),
              HaulTextField(controller: _unit, label: 'Unit', hint: 'Truck 12'),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text('ACCESS LEVEL', style: ht.blockTitle),
              ),
              const SizedBox(height: 8),
              // Only the levels this person is allowed to hand out are offered
              // — and the state refuses anything else regardless, so the form
              // is a convenience rather than the check.
              for (var i = 0; i < roles.length; i++)
                _PickRow(
                  selected: roles[i] == role,
                  exclusive: true,
                  title: roles[i].label,
                  subtitle: roles[i].blurb,
                  semanticLabel:
                      '${roles[i].label}, access level '
                      '${i + 1} of ${roles.length}. ${roles[i].blurb}',
                  onTap: () => setState(() => _role = roles[i]),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: ht.action.copyWith(fontSize: 13, color: hc.inkSoft),
          ),
        ),
        FilledButton(
          onPressed: () => _submit(role),
          style: FilledButton.styleFrom(
            backgroundColor: hc.brand,
            foregroundColor: hc.onBrand,
            minimumSize: const Size(0, HaulSpace.tap),
          ),
          child: Text(
            'ADD TO CREW',
            style: ht.action.copyWith(fontSize: 12, color: hc.onBrand),
          ),
        ),
      ],
    );
  }
}
