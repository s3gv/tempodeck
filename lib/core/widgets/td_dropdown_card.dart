import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../haptics/td_haptics.dart';
import '../theme/app_animations.dart';
import '../theme/app_platform.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_theme.dart';

/// TempoDeck design system dropdown card.
///
/// A dark-themed tappable card that opens a modal bottom sheet for selection.
/// Replaces the inline `_SelectionCard<T>` pattern used throughout the app.
///
/// Exposes button semantics and keyboard activation (Enter / Space) for
/// desktop accessibility. On desktop platforms, shows a hover glow.
class TDDropdownCard<T> extends StatefulWidget {
  const TDDropdownCard({
    required this.label,
    required this.value,
    required this.options,
    required this.itemLabel,
    required this.onChanged,
    super.key,
  });

  /// Input label displayed above the selected value.
  final String label;

  /// Currently selected value.
  final T value;

  /// Available options for selection.
  final List<T> options;

  /// Converts an option value to its display label.
  final String Function(T value) itemLabel;

  /// Called when the user selects a new option.
  final ValueChanged<T> onChanged;

  @override
  State<TDDropdownCard<T>> createState() => _TDDropdownCardState<T>();
}

class _TDDropdownCardState<T> extends State<TDDropdownCard<T>>
    with SingleTickerProviderStateMixin {
  static const _hoverGlowAlpha = 0.15;
  static const _hoverGlowBlur = 12.0;
  static const _sheetMaxHeightFraction = 0.5;
  static const _chevronSize = 20.0;

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
    _scaleController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _scaleController.reverse();
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  void _onTap() {
    TDHaptics.selectionClick();
    _showOptionsSheet(context);
  }

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      TDHaptics.selectionClick();
      _showOptionsSheet(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final showHover = isDesktopPlatform && _isHovered;

    return Semantics(
      button: true,
      label: '${widget.label}: ${widget.itemLabel(widget.value)}',
      child: Focus(
        canRequestFocus: true,
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          onEnter:
              isDesktopPlatform ? (_) => setState(() => _isHovered = true) : null,
          onExit:
              isDesktopPlatform ? (_) => setState(() => _isHovered = false) : null,
          child: GestureDetector(
            onTap: _onTap,
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            behavior: HitTestBehavior.opaque,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: _buildTrigger(showHover),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrigger(bool showHover) {
    return AnimatedContainer(
      duration: AppAnimations.fast,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          if (showHover)
            BoxShadow(
              color: AppColors.primaryGlow.withValues(alpha: _hoverGlowAlpha),
              blurRadius: _hoverGlowBlur,
            ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _buildLabels()),
          const Icon(
            Icons.expand_more,
            color: AppColors.textMuted,
            size: _chevronSize,
          ),
        ],
      ),
    );
  }

  Widget _buildLabels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label, style: AppTextTheme.label),
        const SizedBox(height: AppSpacing.xs),
        Text(
          widget.itemLabel(widget.value),
          style: AppTextTheme.body,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Future<void> _showOptionsSheet(BuildContext context) async {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxSheetHeight = screenHeight * _sheetMaxHeightFraction;

    final selected = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      builder: (_) => _OptionsSheet<T>(
        options: widget.options,
        selectedValue: widget.value,
        itemLabel: widget.itemLabel,
      ),
    );

    if (selected != null) {
      widget.onChanged(selected);
    }
  }
}

/// Bottom sheet listing all dropdown options.
class _OptionsSheet<T> extends StatelessWidget {
  const _OptionsSheet({
    required this.options,
    required this.selectedValue,
    required this.itemLabel,
  });

  final List<T> options;
  final T selectedValue;
  final String Function(T value) itemLabel;

  static const _checkIconSize = 20.0;
  static const _dragHandleWidth = 40.0;
  static const _dragHandleHeight = 4.0;
  static const _dragHandleRadiusFactor = 0.5;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          Flexible(child: _buildOptionsList()),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Container(
        width: _dragHandleWidth,
        height: _dragHandleHeight,
        decoration: BoxDecoration(
          color: AppColors.textMuted,
          borderRadius: BorderRadius.circular(
            _dragHandleHeight * _dragHandleRadiusFactor,
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsList() {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      itemCount: options.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: AppColors.border,
      ),
      itemBuilder: (context, index) => _buildOptionTile(
        context,
        options[index],
      ),
    );
  }

  Widget _buildOptionTile(BuildContext context, T option) {
    final isSelected = option == selectedValue;
    final textStyle = isSelected
        ? AppTextTheme.body.copyWith(color: AppColors.primary)
        : AppTextTheme.body;

    return InkWell(
      onTap: () => Navigator.of(context).pop(option),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(child: Text(itemLabel(option), style: textStyle)),
            if (isSelected)
              const Icon(
                Icons.check,
                color: AppColors.primary,
                size: _checkIconSize,
              ),
          ],
        ),
      ),
    );
  }
}
