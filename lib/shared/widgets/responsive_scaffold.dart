import 'package:flutter/material.dart';
import '../theme/helios_colors.dart';
import 'helios_logo.dart';

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
    label: 'Video',
    icon: Icons.videocam_outlined,
    selectedIcon: Icons.videocam,
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
          if (extended)
            _ExtendedSidebar(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
            )
          else
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              minWidth: 56,
              backgroundColor: HeliosColors.surface,
              useIndicator: true,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: HeliosLogo(size: 28),
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

/// Custom extended sidebar with full-width selection highlight.
class _ExtendedSidebar extends StatelessWidget {
  const _ExtendedSidebar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      color: HeliosColors.surface,
      child: Column(
        children: [
          // Logo + title
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Row(
              children: [
                HeliosLogo(size: 32),
                SizedBox(width: 10),
                Text(
                  'Helios',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: HeliosColors.accent,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Destinations
          ..._destinations.asMap().entries.map((entry) {
            final i = entry.key;
            final d = entry.value;
            final selected = i == selectedIndex;
            return _SidebarItem(
              icon: selected ? d.selectedIcon : d.icon,
              label: d.label,
              selected: selected,
              onTap: () => onDestinationSelected(i),
            );
          }),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? HeliosColors.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: HeliosColors.accent.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? HeliosColors.accent : HeliosColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? HeliosColors.accent : HeliosColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
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
