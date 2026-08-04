import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/haul_theme.dart';

/// Which meaning a [Pill] carries. Resolved to colours at build time rather
/// than baked into the constructor, because the two palettes do not agree on
/// what "alert" looks like.
enum PillTone { neutral, go, alert, violet, brand }

/// Small status chip. Purely decorative next to text that already says the same
/// thing, so it is hidden from screen readers unless [semanticLabel] is given.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.semanticLabel,
    this.tone = PillTone.neutral,
  });

  const Pill.go({super.key, required this.label, this.icon, this.semanticLabel})
    : tone = PillTone.go;

  const Pill.alert({
    super.key,
    required this.label,
    this.icon,
    this.semanticLabel,
  }) : tone = PillTone.alert;

  const Pill.violet({
    super.key,
    required this.label,
    this.icon,
    this.semanticLabel,
  }) : tone = PillTone.violet;

  const Pill.brand({
    super.key,
    required this.label,
    this.icon,
    this.semanticLabel,
  }) : tone = PillTone.brand;

  final String label;
  final IconData? icon;
  final PillTone tone;
  final String? semanticLabel;

  ({Color foreground, Color background}) _colours(HaulPalette hc) =>
      switch (tone) {
        PillTone.neutral => (foreground: hc.inkSoft, background: hc.raised),
        PillTone.go => (foreground: hc.go, background: hc.goWash),
        PillTone.alert => (foreground: hc.alert, background: hc.alertWash),
        PillTone.violet => (foreground: hc.violet, background: hc.violetWash),
        PillTone.brand => (foreground: hc.brand, background: hc.brandWash),
      };

  @override
  Widget build(BuildContext context) {
    final ht = HaulText.of(context);
    final (:foreground, :background) = _colours(HaulColors.of(context));
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel == null,
      container: semanticLabel != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 5),
            ],
            // Pills sit next to flexible content; letting the label shrink
            // keeps a long one from starving the text beside it.
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ht.pill.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Driver initials. Never the only way a person is identified — their name is
/// always adjacent — so it is excluded from the semantics tree.
class CrewAvatar extends StatelessWidget {
  const CrewAvatar({super.key, required this.initials, this.size = 38})
    : muted = false;

  /// For crew who are not the subject of the screen — greyed rather than brand.
  const CrewAvatar.muted({super.key, required this.initials, this.size = 38})
    : muted = true;

  final String initials;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final background = muted ? hc.raised : hc.brand;
    final foreground = muted ? hc.ink : hc.onBrand;

    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Text(
          initials,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: HaulFonts.black,
            fontSize: size * 0.36,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// The surface panel everything sits on.
class HaulBlock extends StatelessWidget {
  const HaulBlock({
    super.key,
    required this.child,
    this.title,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final Widget child;
  final String? title;
  final EdgeInsets padding;
  final Color? borderColor;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border.all(color: borderColor ?? hc.line),
        borderRadius: BorderRadius.circular(HaulSpace.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Semantics(
              header: true,
              child: Text(title!.toUpperCase(), style: ht.blockTitle),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// "WHERE" / "THE LOAD" style label-value row inside a [HaulBlock].
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
    this.divider = true,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: hc.line)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: ht.secondary)),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: valueStyle ?? ht.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section heading with an optional trailing chip. The heading is marked as a
/// semantic header so screen reader users can jump between sections.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.topPadding = 4,
  });

  final String title;
  final Widget? trailing;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final ht = HaulText.of(context);
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: 10, left: 2, right: 2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title.toUpperCase(), style: ht.sectionTitle),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Flexible(child: trailing!),
          ],
        ],
      ),
    );
  }
}

/// Dashed placeholder for a list with nothing in it.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, this.title, required this.message});

  final String? title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        decoration: BoxDecoration(
          border: Border.all(color: hc.line, width: 2),
          borderRadius: BorderRadius.circular(HaulSpace.radius),
        ),
        child: Column(
          children: [
            if (title != null) ...[
              Text(
                title!.toUpperCase(),
                textAlign: TextAlign.center,
                style: ht.sectionTitle,
              ),
              const SizedBox(height: 6),
            ],
            Text(message, textAlign: TextAlign.center, style: ht.secondary),
          ],
        ),
      ),
    );
  }
}

/// A number and its label. [hero] is the one figure on the screen that gets the
/// hi-vis treatment.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.valueColor,
    this.hero = false,
  });

  final String value;
  final String label;
  final Color? valueColor;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    // One flat sentence beats "395 … BILLED TODAY" read as two fragments.
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: hero ? hc.brand : hc.surface,
          border: Border.all(color: hero ? hc.brand : hc.line),
          borderRadius: BorderRadius.circular(HaulSpace.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: HaulFonts.black,
                fontSize: hero ? 34 : 24,
                height: 1.05,
                color: hero ? hc.bg : (valueColor ?? hc.ink),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: ht.eyebrow.copyWith(
                color: hero ? hc.bg.withValues(alpha: 0.72) : hc.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the little grey chips under a job's headline.
class FactChip extends StatelessWidget {
  const FactChip({super.key, required this.label, this.icon, this.bad = false});

  final String label;
  final IconData? icon;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final fg = bad ? hc.alert : hc.inkSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: bad ? hc.alertWash : hc.raised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label, style: ht.small.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

/// Hazard callout. Announced as an alert so it isn't missed.
class HazardNote extends StatelessWidget {
  const HazardNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    return Semantics(
      liveRegion: false,
      label: 'Hazard: $text',
      excludeSemantics: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: hc.alertWash,
          borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 17,
                color: hc.alert,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: ht.small.copyWith(color: hc.alert, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The full-width action bar at the bottom of a card or sheet.
class ActionBar extends StatelessWidget {
  const ActionBar({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon = Icons.chevron_right_rounded,
    this.onPressed,
    this.solid = false,
    this.ghost = false,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  final bool solid;
  final bool ghost;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final enabled = onPressed != null;
    final bg = ghost
        ? Colors.transparent
        : solid
        ? hc.brand
        : hc.raised;
    final fg = !enabled
        ? hc.inkSoft
        : solid
        ? hc.bg
        : ghost
        ? hc.inkSoft
        : hc.ink;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: hc.raised,
            disabledForegroundColor: hc.inkSoft,
            minimumSize: const Size.fromHeight(HaulSpace.tap),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(HaulSpace.radius - 1),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: ht.action.copyWith(color: fg),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 6),
                Icon(trailingIcon, size: 17),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Square icon-only control. Always carries a tooltip, which doubles as its
/// screen reader label.
class HaulIconButton extends StatelessWidget {
  const HaulIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    // The label has to be stated here, on the node that is also the button.
    //
    // Passing `tooltip:` to IconButton and leaving it at that looks like it
    // should be enough — it is the documented way — but the label lands on the
    // Tooltip's own wrapper node, and the tappable node underneath comes out
    // with an empty name. A screen reader then reads these as an unnamed
    // button, which is how the sign-out control went unlabelled. `onTap` is
    // passed explicitly because `excludeSemantics` drops the child's actions
    // along with its nodes, and a named button nobody can activate is no
    // better than an unnamed one.
    return Semantics(
      button: true,
      enabled: true,
      label: tooltip,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 19),
        color: active ? hc.brand : hc.inkSoft,
        constraints: const BoxConstraints(
          minWidth: HaulSpace.tap,
          minHeight: HaulSpace.tap,
        ),
        style: IconButton.styleFrom(
          backgroundColor: hc.raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
            side: BorderSide(color: active ? hc.brand : hc.line),
          ),
        ),
      ),
    );
  }
}

/// A themed text field.
///
/// The label is a real label rather than a placeholder that vanishes the moment
/// you type — somebody filling in twenty job fields with the sun on the screen
/// needs to be able to look away and back without losing their place.
class HaulTextField extends StatelessWidget {
  const HaulTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.keyboardType,
    this.maxLines = 1,
    this.autofocus = false,
    this.validator,
    this.prefix,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool autofocus;
  final String? Function(String?)? validator;
  final String? prefix;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
          borderSide: BorderSide(color: color, width: width),
        );

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      autofocus: autofocus,
      validator: validator,
      inputFormatters: inputFormatters,
      style: ht.body,
      cursorColor: hc.brand,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        prefixText: prefix,
        prefixStyle: ht.body,
        filled: true,
        fillColor: hc.raised,
        labelStyle: ht.secondary,
        floatingLabelStyle: ht.secondary.copyWith(color: hc.brand),
        hintStyle: ht.secondary,
        helperStyle: ht.small,
        helperMaxLines: 3,
        errorStyle: ht.small.copyWith(color: hc.alert),
        errorMaxLines: 3,
        border: border(hc.line),
        enabledBorder: border(hc.line),
        focusedBorder: border(hc.brand, 2),
        errorBorder: border(hc.alert),
        focusedErrorBorder: border(hc.alert, 2),
      ),
    );
  }
}
