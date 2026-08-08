import 'package:flutter/material.dart';

import 'calendar_theme.dart';

/// An inset grouped table, the way iOS draws one.
///
/// Shared rather than copied: the job editor and the price sheet are the same
/// kind of form, and two versions of a rounded box with hairlines between its
/// rows is two versions that drift apart by a pixel and stay that way.
class FormGroup extends StatelessWidget {
  const FormGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: p.hairline,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A labelled text field, one row of a [FormGroup].
class FormRow extends StatelessWidget {
  const FormRow({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    this.lines = 1,
    this.autofocus = false,
    this.keyboard,
    this.prefix,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final int lines;
  final bool autofocus;
  final TextInputType? keyboard;

  /// Sits inside the field, ahead of what is typed — a dollar sign that is
  /// part of the box rather than part of the number.
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: SizedBox(width: 96, child: Text(label, style: t.secondary)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              maxLines: lines,
              minLines: 1,
              keyboardType: keyboard,
              textCapitalization: TextCapitalization.sentences,
              style: t.body.copyWith(fontSize: 15),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                prefixText: prefix,
                prefixStyle: t.body.copyWith(
                  fontSize: 15,
                  color: p.secondaryLabel,
                ),
                hintStyle: t.body.copyWith(
                  fontSize: 15,
                  color: p.tertiaryLabel,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Whole dollars out of whatever somebody typed.
///
/// Forgiving on purpose: "$1,250", "1250.00" and "1250" are the same number,
/// and a form that rejects the first two is a form that gets sworn at. Cents
/// are dropped rather than rounded — the board deals in whole dollars.
int dollarsFrom(String text) {
  final digits = text.split('.').first.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}
