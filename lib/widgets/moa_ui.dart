import 'package:flutter/material.dart';

import '../theme/moa_design_tokens.dart';

class MoaGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color color;
  final Color borderColor;
  final List<BoxShadow> boxShadow;
  final VoidCallback? onTap;

  const MoaGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = MoaDesignTokens.radiusMd,
    this.color = MoaDesignTokens.surface,
    this.borderColor = MoaDesignTokens.stroke,
    this.boxShadow = MoaDesignTokens.cardShadow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: boxShadow,
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

class MoaPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final EdgeInsetsGeometry padding;

  const MoaPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: padding,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: enabled
                  ? MoaDesignTokens.primaryGradient
                  : const LinearGradient(
                      colors: <Color>[Color(0xFFEAF2F8), Color(0xFFDDE8F0)],
                    ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: enabled
                    ? Colors.white.withValues(alpha: 0.7)
                    : MoaDesignTokens.stroke,
              ),
              boxShadow: enabled ? MoaDesignTokens.activeGlow : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: MoaDesignTokens.textPrimary),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: enabled
                        ? MoaDesignTokens.textPrimary
                        : MoaDesignTokens.textMuted.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!expanded) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

class MoaSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const MoaSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: MoaDesignTokens.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: MoaDesignTokens.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class MoaStatusChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color backgroundColor;

  const MoaStatusChip({
    super.key,
    required this.label,
    this.icon,
    this.color = MoaDesignTokens.accentStrong,
    this.backgroundColor = MoaDesignTokens.accentSoft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
