import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../haptics/td_haptics.dart';
import '../theme/app_animations.dart';
import '../theme/app_platform.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// TempoDeck design system list tile.
///
/// Dark-themed tile with optional selected highlight and trailing widget.
/// Replaces stock [ListTile] + [Card] patterns used for song and setlist
/// items throughout the app.
///
/// Exposes button semantics and keyboard focus/activation for desktop
/// accessibility. On desktop platforms, shows a hover glow when [onTap]
/// is not null.
class TDListTile extends StatefulWidget {
  const TDListTile({
    required this.title,
    super.key,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    this.isSelected = false,
  });

  /// Primary text displayed in the tile.
  final String title;

  /// Optional secondary text below the title.
  final String? subtitle;

  /// Widget displayed at the trailing edge (e.g. a [PopupMenuButton]).
  final Widget? trailing;

  /// Widget displayed at the leading edge (e.g. an icon or avatar).
  final Widget? leading;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  /// Whether this tile is in the selected/highlighted state.
  /// Shows a primary-color left accent border and elevated surface.
  final bool isSelected;

  @override
  State<TDListTile> createState() => _TDListTileState();
}

class _TDListTileState extends State<TDListTile>
    with SingleTickerProviderStateMixin {
  static const _selectedBorderWidth = 3.0;
  static const _hoverGlowAlpha = 0.15;
  static const _hoverGlowBlur = 12.0;

  bool _isHovered = false;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: AppAnimations.fast,
    );
    _scaleAnimation = Tween<double>(
      begin: 1,
      end: AppAnimations.buttonPressedScale,
    ).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: AppAnimations.snap,
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null) {
      _scaleController.forward();
    }
  }

  void _onTapUp(TapUpDetails _) {
    _scaleController.reverse();
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  void _onTap() {
    if (widget.onTap != null) {
      TDHaptics.selectionClick();
      widget.onTap!();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || widget.onTap == null) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      TDHaptics.selectionClick();
      widget.onTap!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final showHover = isDesktopPlatform && _isHovered && widget.onTap != null;

    return Semantics(
      button: widget.onTap != null,
      selected: widget.isSelected,
      label: widget.title,
      child: Focus(
        canRequestFocus: widget.onTap != null,
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          onEnter:
              isDesktopPlatform && widget.onTap != null
                  ? (_) => setState(() => _isHovered = true)
                  : null,
          onExit:
              isDesktopPlatform && widget.onTap != null
                  ? (_) => setState(() => _isHovered = false)
                  : null,
          child: GestureDetector(
            onTap: widget.onTap != null ? _onTap : null,
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            behavior: HitTestBehavior.opaque,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: _buildContainer(showHover),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContainer(bool showHover) {
    return AnimatedContainer(
      duration: AppAnimations.fast,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: widget.isSelected
            ? AppColors.surface
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(
          color: widget.isSelected ? AppColors.primary : AppColors.border,
        ),
        boxShadow: [
          if (showHover)
            BoxShadow(
              color: AppColors.primaryGlow.withValues(alpha: _hoverGlowAlpha),
              blurRadius: _hoverGlowBlur,
            ),
        ],
      ),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    return Row(
      children: [
        if (widget.isSelected) _buildSelectedAccent(),
        if (widget.leading != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: widget.leading,
          ),
        Expanded(child: _buildTextColumn()),
        if (widget.trailing != null) widget.trailing!,
      ],
    );
  }

  Widget _buildSelectedAccent() {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Container(
        width: _selectedBorderWidth,
        height: AppSpacing.xl,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(_selectedBorderWidth),
        ),
      ),
    );
  }

  Widget _buildTextColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.title,
          style: AppTextTheme.body,
          overflow: TextOverflow.ellipsis,
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.subtitle!,
            style: AppTextTheme.bodySecondary,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
