import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_theme.dart';

/// TempoDeck design system bottom navigation bar.
///
/// Custom bottom nav with icon glow effect on the active tab.
/// Each destination has an icon and a short label.
///
/// Supports keyboard navigation (Tab + Space/Enter),
/// focus indicators, and proper semantics for screen readers.
class TDNavBar extends StatelessWidget {
  const TDNavBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    super.key,
  });

  final List<TDNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < destinations.length; i++)
            Expanded(
              child: _NavItem(
                destination: destinations[i],
                isSelected: i == selectedIndex,
                onTap: () => onDestinationSelected(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single destination in a [TDNavBar].
class TDNavDestination {
  const TDNavDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;
  final String label;
  final IconData? selectedIcon;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final TDNavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = isSelected
        ? (destination.selectedIcon ?? destination.icon)
        : destination.icon;
    final color = isSelected ? AppColors.primary : AppColors.textMuted;

    return Semantics(
      label: destination.label,
      selected: isSelected,
      button: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: Builder(
          builder: (context) {
            final isFocused = Focus.of(context).hasPrimaryFocus;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        if (isSelected)
                          const BoxShadow(
                            color: AppColors.primaryGlow,
                            blurRadius: 12,
                            spreadRadius: -4,
                          ),
                      ],
                      border: isFocused
                          ? Border.all(
                              color: AppColors.primaryLight,
                              width: 2,
                            )
                          : null,
                      borderRadius: isFocused
                          ? BorderRadius.circular(6)
                          : null,
                    ),
                    padding: isFocused
                        ? const EdgeInsets.all(2)
                        : EdgeInsets.zero,
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    destination.label,
                    style: AppTextTheme.labelSmall.copyWith(color: color),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
