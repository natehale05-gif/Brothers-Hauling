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

/// A form row that opens a menu of choices.
///
/// Every one of these used to be a row of chips: the whole list showing at all
/// times to say which one of it is on. Six rules, seven reminders and five
/// kinds of work came to nine lines of a form that already scrolls, and none
/// of them earned the space — a choice is read far more often than it is
/// changed. Shut, the row says what is chosen; open, it offers the rest.
class ChoiceRow<T> extends StatefulWidget {
  const ChoiceRow({
    super.key,
    required this.label,
    required this.shown,
    required this.ticked,
    required this.choices,
    required this.onChanged,
    this.valueColour,
    this.dotOf,
    this.trailing,
    this.spokenLabel,
  });

  final String label;

  /// What a screen reader hears in place of [label], where the row needs to
  /// say who or what it belongs to. Several people on a roster each have a
  /// level, and "Level, employee" three times over says nothing about which.
  final String? spokenLabel;

  /// What the row reads when the menu is shut.
  final String shown;

  /// Which choices carry a tick. A predicate rather than one value, because
  /// the rigs a job needs are a list and every one of them is in force.
  final bool Function(T) ticked;

  final List<(T, String)> choices;
  final ValueChanged<T> onChanged;

  /// The kind of work is written in its own colour, the way the calendar
  /// draws it.
  final Color? valueColour;

  /// A colour dot beside each choice, where the choice has one.
  final Color? Function(T)? dotOf;

  /// Shown at the end of the row — the bell that says a reminder is set.
  final Widget? trailing;

  @override
  State<ChoiceRow<T>> createState() => ChoiceRowState<T>();
}

class ChoiceRowState<T> extends State<ChoiceRow<T>> {
  /// Held so the row's own semantics action can open the menu.
  ///
  /// The label belongs to the whole row — "Alert, 15 min before" — and a
  /// screen reader has to be able to open it from there, not only by finding
  /// the chevron on the end of it.
  final GlobalKey<PopupMenuButtonState<T>> _menu = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Semantics(
      button: true,
      label:
          '${widget.spokenLabel ?? widget.label}, '
          '${widget.shown.toLowerCase()}',
      onTap: () => _menu.currentState?.showButtonMenu(),
      excludeSemantics: true,
      child: PopupMenuButton<T>(
        key: _menu,
        tooltip: widget.label,
        // Deliberately no initialValue: it makes the menu open with the chosen
        // item over the button rather than under the row, which on the last
        // choice in a long list puts the first ones off the top of the screen.
        // The tick says which is in force.
        onSelected: widget.onChanged,
        position: PopupMenuPosition.under,
        color: p.card,
        itemBuilder: (context) => [
          for (final (value, label) in widget.choices)
            PopupMenuItem<T>(
              value: value,
              child: Row(
                children: [
                  // The tick, and a gap the same width where there is none, so
                  // the labels line up down the menu.
                  SizedBox(
                    width: 26,
                    child: widget.ticked(value)
                        ? Icon(Icons.check_rounded, size: 18, color: p.accent)
                        : null,
                  ),
                  if (widget.dotOf?.call(value) case final dot?) ...[
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: t.body.copyWith(
                        fontSize: 15,
                        color: widget.ticked(value) ? p.accent : p.label,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(widget.label, style: t.secondary),
              ),
              Expanded(
                child: Text(
                  widget.shown,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.body.copyWith(
                    fontSize: 15,
                    color: widget.valueColour ?? p.label,
                  ),
                ),
              ),
              if (widget.trailing case final extra?) ...[
                extra,
                const SizedBox(width: 6),
              ],
              Icon(Icons.unfold_more_rounded, size: 18, color: p.tertiaryLabel),
            ],
          ),
        ),
      ),
    );
  }
}
