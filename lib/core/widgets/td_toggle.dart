import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_animations.dart';
import '../theme/app_platform.dart';
import '../theme/app_colors.dart';

/// TempoDeck design system toggle switch.
///
/// Custom toggle that matches the dark + purple theme.
/// Not iOS-style -- uses the app's own visual language.
///
/// Supports keyboard activation (Space/Enter), focus ring,
/// and exposes proper switch semantics to screen readers.
///
/// On desktop platforms, shows a hover glow around the toggle track.
class TDToggle extends StatefulWidget {
  const TDToggle({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  State<TDToggle> createState() => _TDToggleState();
}

class _TDToggleState extends State<TDToggle> {
  static const _width = 52.0;
  static const _height = 28.0;
  static const _thumbSize = 22.0;
  static const _thumbPadding = 3.0;

  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onChanged != null;

    return MouseRegion(
      onEnter: isDesktopPlatform ? (_) => setState(() => _isHovered = true) : null,
      onExit: isDesktopPlatform ? (_) => setState(() => _isHovered = false) : null,
      child: Semantics(
        toggled: widget.value,
        enabled: isEnabled,
        label: 'Toggle',
        child: FocusableActionDetector(
          enabled: isEnabled,
          mouseCursor:
              isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          },
          actions: {
            ActivateIntent:
                CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    if (isEnabled) widget.onChanged!(!widget.value);
                    return null;
                  },
                ),
          },
          child: Builder(
            builder: (context) {
              final isFocused = Focus.of(context).hasPrimaryFocus;
              final showHover = isDesktopPlatform && _isHovered;

              return GestureDetector(
                onTap: isEnabled
                    ? () => widget.onChanged!(!widget.value)
                    : null,
                child: AnimatedContainer(
                  duration: AppAnimations.fast,
                  curve: AppAnimations.snap,
                  width: _width,
                  height: _height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_height / 2),
                    color: widget.value
                        ? AppColors.primary
                        : AppColors.surfaceElevated,
                    border: isFocused
                        ? Border.all(color: AppColors.primaryLight, width: 2)
                        : null,
                    boxShadow: [
                      if (widget.value)
                        const BoxShadow(
                          color: AppColors.primaryGlow,
                          blurRadius: 12,
                          spreadRadius: -2,
                        ),
                      if (isFocused)
                        const BoxShadow(
                          color: AppColors.primaryGlow,
                          blurRadius: 8,
                        ),
                      if (showHover)
                        BoxShadow(
                          color:
                              AppColors.primaryGlow.withValues(alpha: 0.15),
                          blurRadius: 12,
                        ),
                    ],
                  ),
                  child: AnimatedAlign(
                    duration: AppAnimations.fast,
                    curve: AppAnimations.snap,
                    alignment: widget.value
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(_thumbPadding),
                      child: Container(
                        width: _thumbSize,
                        height: _thumbSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.value
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
