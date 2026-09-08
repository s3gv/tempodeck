import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../features/settings/settings_screen.dart';
import 'desktop_panel_layout.dart';

class DesktopSettingsScreen extends StatelessWidget {
  const DesktopSettingsScreen({super.key});

  static const double _maxContentWidth = 700;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(
              DesktopPanelLayout.panelBorderRadius,
            ),
          ),
          child: const SettingsScreen(showScaffold: false),
        ),
      ),
    );
  }
}
