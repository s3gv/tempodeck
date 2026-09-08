import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_navigation_destination.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/td_nav_bar.dart';

class MobileShell extends ConsumerWidget {
  const MobileShell({
    super.key,
    required this.shell,
    required this.isLiveRoute,
  });

  final StatefulNavigationShell shell;
  final bool isLiveRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: shell,
      bottomNavigationBar: isLiveRoute
          ? null
          : TDNavBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: shell.goBranch,
              destinations: [
                for (final destination in appNavigationDestinations)
                  TDNavDestination(
                    icon: destination.icon,
                    label: destination.label,
                  ),
              ],
            ),
    );
  }
}
