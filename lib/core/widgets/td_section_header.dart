import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_animations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// TempoDeck design system section header.
///
/// Displays an icon + label row with an optional animated chevron for
/// expand/collapse. When [onToggle] is `null`, the chevron is hidden
/// and the header acts as a non-collapsible label.
///
/// When collapsible, exposes button semantics and supports keyboard
/// activation (Enter / Space) for desktop accessibility.
class TDSectionHeader extends StatelessWidget {
  const TDSectionHeader({
    required this.icon,
    required this.label,
    super.key,
    this.isExpanded = true,
    this.onToggle,
  });

  /// Leading section icon.
  final IconData icon;

  /// Section title text.
  final String label;

  /// Whether the section body is currently expanded.
  final bool isExpanded;

  /// Called when the user taps the header. Pass `null` for non-collapsible
  /// sections (the chevron will be hidden).
  final VoidCallback? onToggle;

  static const _iconSize = 20.0;
  static const _chevronSize = 20.0;
  static const _minTouchHeight = 48.0;
  static const _accentLineHeight = 1.0;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minTouchHeight),
          child: Row(
            children: [
              Icon(icon, size: _iconSize, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppTextTheme.sectionLabel,
                ),
              ),
              if (onToggle != null)
                AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: AppAnimations.fast,
                  curve: AppAnimations.snap,
                  child: const Icon(
                    Icons.chevron_right,
                    size: _chevronSize,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        Container(
          height: _accentLineHeight,
          margin: const EdgeInsets.only(top: AppSpacing.xs),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.primaryGlow,
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );

    if (onToggle == null) return content;

    return Semantics(
      button: true,
      label: '${isExpanded ? "Collapse" : "Expand"} $label',
      child: Focus(
        canRequestFocus: true,
        onKeyEvent: (_, event) => _handleKeyEvent(event),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: content,
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      onToggle?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
