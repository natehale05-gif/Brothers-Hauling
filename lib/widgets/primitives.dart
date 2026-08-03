import 'package:flutter/material.dart';

import '../theme/haul_theme.dart';

/// Small status chip. Purely decorative next to text that already says the same
/// thing, so it is hidden from screen readers unless [semanticLabel] is given.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.foreground = HaulColors.grey,
    this.background = HaulColors.raised,
    this.semanticLabel,
  });

  const Pill.go({super.key, required this.label, this.icon, this.semanticLabel})
    : foreground = HaulColors.go,
      background = HaulColors.goWash;

  const Pill.alert({
    super.key,
    required this.label,
    this.icon,
    this.semanticLabel,
  }) : foreground = HaulColors.alert,
       background = HaulColors.alertWash;

  const Pill.violet({
    super.key,
    required this.label,
    this.icon,
    this.semanticLabel,
  }) : foreground = HaulColors.violet,
       background = HaulColors.violetWash;

  const Pill.brand({
    super.key,
    required this.label,
    this.icon,
    this.semanticLabel,
  }) : foreground = HaulColors.brand,
       background = HaulColors.brandWash;

  final String label;
  final IconData? icon;
  final Color foreground;
  final Color background;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
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
                style: HaulText.pill.copyWith(color: foreground),
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
  const CrewAvatar({
    super.key,
    required this.initials,
    this.size = 38,
    this.background = HaulColors.brand,
    this.foreground = HaulColors.asphalt,
  });

  const CrewAvatar.muted({super.key, required this.initials, this.size = 38})
    : background = HaulColors.raised,
      foreground = HaulColors.white;

  final String initials;
  final double size;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
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
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: HaulColors.surface,
        border: Border.all(color: borderColor ?? HaulColors.line),
        borderRadius: BorderRadius.circular(HaulSpace.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Semantics(
              header: true,
              child: Text(title!.toUpperCase(), style: HaulText.blockTitle),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: divider
          ? const BoxDecoration(
              border: Border(bottom: BorderSide(color: HaulColors.line)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: HaulText.secondary)),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: valueStyle ?? HaulText.bodyStrong,
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
    return Padding(
      padding: EdgeInsets.only(top: topPadding, bottom: 10, left: 2, right: 2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title.toUpperCase(), style: HaulText.sectionTitle),
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
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        decoration: BoxDecoration(
          border: Border.all(color: HaulColors.line, width: 2),
          borderRadius: BorderRadius.circular(HaulSpace.radius),
        ),
        child: Column(
          children: [
            if (title != null) ...[
              Text(
                title!.toUpperCase(),
                textAlign: TextAlign.center,
                style: HaulText.sectionTitle,
              ),
              const SizedBox(height: 6),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: HaulText.secondary,
            ),
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
    // One flat sentence beats "395 … BILLED TODAY" read as two fragments.
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: hero ? HaulColors.brand : HaulColors.surface,
          border: Border.all(color: hero ? HaulColors.brand : HaulColors.line),
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
                color: hero
                    ? HaulColors.asphalt
                    : (valueColor ?? HaulColors.white),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: HaulText.eyebrow.copyWith(
                color: hero
                    ? HaulColors.asphalt.withValues(alpha: 0.72)
                    : HaulColors.grey,
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
    final fg = bad ? HaulColors.alert : HaulColors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: bad ? HaulColors.alertWash : HaulColors.raised,
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
            child: Text(label, style: HaulText.small.copyWith(color: fg)),
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
    return Semantics(
      liveRegion: false,
      label: 'Hazard: $text',
      excludeSemantics: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
        decoration: BoxDecoration(
          color: HaulColors.alertWash,
          borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 17,
                color: HaulColors.alert,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: HaulText.small.copyWith(
                  color: HaulColors.alert,
                  fontSize: 13,
                ),
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
    final enabled = onPressed != null;
    final bg = ghost
        ? Colors.transparent
        : solid
        ? HaulColors.brand
        : HaulColors.raised;
    final fg = !enabled
        ? HaulColors.grey
        : solid
        ? HaulColors.asphalt
        : ghost
        ? HaulColors.grey
        : HaulColors.white;

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
            disabledBackgroundColor: HaulColors.raised,
            disabledForegroundColor: HaulColors.grey,
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
                  style: HaulText.action.copyWith(color: fg),
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
    // IconButton's own `tooltip` both shows the hover text and names the
    // button. Wrapping in a Tooltip instead would hang the label on a parent
    // node and leave the tappable node itself unnamed.
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 19),
      color: active ? HaulColors.brand : HaulColors.grey,
      constraints: const BoxConstraints(
        minWidth: HaulSpace.tap,
        minHeight: HaulSpace.tap,
      ),
      style: IconButton.styleFrom(
        backgroundColor: HaulColors.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
          side: BorderSide(color: active ? HaulColors.brand : HaulColors.line),
        ),
      ),
    );
  }
}
