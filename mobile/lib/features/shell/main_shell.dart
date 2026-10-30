import 'package:flutter/material.dart';

import '../games/games_screen.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../measure/measure_screen.dart';
import '../profile/profile_screen.dart';

/// The five primary sections, behind a Material 3 navigation bar.
///
/// An [IndexedStack] keeps each tab alive so scroll positions and in-progress
/// state survive switching tabs.
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  /// Switches the enclosing shell to [index]. Used by screens that link across
  /// tabs, such as "play now" jumping to Games.
  static void goToTab(BuildContext context, int index) {
    context.findAncestorStateOfType<_MainShellState>()?.selectTab(index);
  }

  static const int homeTab = 0;
  static const int measureTab = 1;
  static const int gamesTab = 2;
  static const int historyTab = 3;
  static const int profileTab = 4;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _index = widget.initialIndex;

  void selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  static const List<_Destination> _destinations = [
    _Destination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _Destination(
      label: 'Measure',
      icon: Icons.favorite_outline_rounded,
      selectedIcon: Icons.favorite_rounded,
    ),
    _Destination(
      label: 'Games',
      icon: Icons.sports_esports_outlined,
      selectedIcon: Icons.sports_esports_rounded,
    ),
    _Destination(
      label: 'History',
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights_rounded,
    ),
    _Destination(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          MeasureScreen(),
          GamesScreen(),
          HistoryScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: selectTab,
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
              tooltip: destination.label,
            ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
