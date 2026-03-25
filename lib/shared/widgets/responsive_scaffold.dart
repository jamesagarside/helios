import 'package:flutter/material.dart';
import '../theme/helios_colors.dart';

/// Breakpoints for responsive layout.
abstract final class HeliosBreakpoints {
  static const double desktop = 1200;
  static const double tablet = 768;
}

/// Navigation destination for the app shell.
class HeliosDestination {
  const HeliosDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = [
  HeliosDestination(
    label: 'Fly',
    icon: Icons.flight_outlined,
    selectedIcon: Icons.flight,
  ),
  HeliosDestination(
    label: 'Plan',
    icon: Icons.map_outlined,
    selectedIcon: Icons.map,
  ),
  HeliosDestination(
    label: 'Data',
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics,
  ),
  HeliosDestination(
    label: 'Setup',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];

/// Responsive app shell — NavigationRail on desktop/tablet, BottomNav on mobile.
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width < HeliosBreakpoints.tablet) {
      return _MobileLayout(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        body: body,
      );
    }

    return _DesktopLayout(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      body: body,
      extended: width >= HeliosBreakpoints.desktop,
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    required this.extended,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            extended: extended,
            minWidth: 56,
            minExtendedWidth: 180,
            backgroundColor: HeliosColors.surface,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Icon(
                Icons.sunny,
                color: HeliosColors.accent,
                size: extended ? 32 : 28,
              ),
            ),
            destinations: _destinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(
            thickness: 1,
            width: 1,
            color: HeliosColors.border,
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: body,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: onDestinationSelected,
        type: BottomNavigationBarType.fixed,
        items: _destinations
            .map(
              (d) => BottomNavigationBarItem(
                icon: Icon(d.icon),
                activeIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
            )
            .toList(),
      ),
    );
  }
}
