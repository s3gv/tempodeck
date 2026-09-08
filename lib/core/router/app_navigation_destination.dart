import 'package:flutter/material.dart';

import 'routes.dart';

class AppNavigationDestination {
  const AppNavigationDestination({
    required this.route,
    required this.icon,
    required this.label,
  });

  final String route;
  final IconData icon;
  final String label;
}

const appNavigationDestinations = [
  AppNavigationDestination(
    route: Routes.metronome,
    icon: Icons.music_note,
    label: 'Metronome',
  ),
  AppNavigationDestination(
    route: Routes.songs,
    icon: Icons.library_music,
    label: 'Songs',
  ),
  AppNavigationDestination(
    route: Routes.setlists,
    icon: Icons.queue_music,
    label: 'Setlists',
  ),
  AppNavigationDestination(
    route: Routes.settings,
    icon: Icons.settings,
    label: 'Settings',
  ),
];
