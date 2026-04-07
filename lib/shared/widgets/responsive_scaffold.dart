import 'package:flutter/foundation.dart' show kIsWeb;
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

final List<HeliosDestination> _destinations = [
  const HeliosDestination(
    label: 'Fly',
    icon: Icons.flight_outlined,
    selectedIcon: Icons.flight,
  ),
  const HeliosDestination(
    label: 'Plan',
    icon: Icons.map_outlined,
    selectedIcon: Icons.map,
  ),
  const HeliosDestination(
    label: 'Data',
    icon: Icons.analytics_outlined,
    selectedIcon: Icons.analytics,
  ),
  // Video tab hidden on web — media_kit requires native platform.
  if (!kIsWeb)
    const HeliosDestination(
      label: 'Video',
      icon: Icons.videocam_outlined,
      selectedIcon: Icons.videocam,
    ),
  const HeliosDestination(
    label: 'Config',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
  ),
  const HeliosDestination(
    label: 'Inspect',
    icon: Icons.bug_report_outlined,
    selectedIcon: Icons.bug_report,
  ),
  const HeliosDestination(
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
    this.header,
    this.footer,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  /// Optional widget pinned to the top of the content area (not the sidebar).
  final Widget? header;

  /// Optional widget pinned to the bottom of the content area (not the sidebar).
  /// Rendered via [Scaffold.bottomNavigationBar] so nested Scaffolds in [body]
  /// automatically respect the reserved space.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width < HeliosBreakpoints.tablet) {
      return _MobileLayout(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        body: body,
        header: header,
        footer: footer,
      );
    }

    return _DesktopLayout(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      body: body,
      header: header,
      footer: footer,
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
    this.header,
    this.footer,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final bool extended;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
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
              backgroundColor: hc.surface,
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
          VerticalDivider(
            thickness: 1,
            width: 1,
            color: hc.border,
          ),
          Expanded(
            child: Column(
              children: [
                ?header,
                // ClipRect prevents nested Scaffolds (e.g. SetupView,
                // FcConfigView) from painting their sub-sidebars into
                // the footer area.
                Expanded(child: ClipRect(child: body)),
                ?footer,
              ],
            ),
          ),
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
    final hc = context.hc;
    return Container(
      width: 180,
      color: hc.surface,
      child: Column(
        children: [
          // Logo + title
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Row(
              children: [
                const HeliosLogo(size: 32),
                const SizedBox(width: 10),
                Text(
                  'Helios',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: hc.accent,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Main destinations (all except last)
          ...List.generate(_destinations.length - 1, (i) {
            final d = _destinations[i];
            final selected = i == selectedIndex;
            return _SidebarItem(
              icon: selected ? d.selectedIcon : d.icon,
              label: d.label,
              selected: selected,
              onTap: () => onDestinationSelected(i),
            );
          }),
          const Spacer(),
          Divider(height: 1, thickness: 1, color: hc.border),
          // Settings pinned at bottom
          Builder(builder: (context) {
            final i = _destinations.length - 1;
            final d = _destinations[i];
            final selected = i == selectedIndex;
            return _SidebarItem(
              icon: selected ? d.selectedIcon : d.icon,
              label: d.label,
              selected: selected,
              onTap: () => onDestinationSelected(i),
            );
          }),
          const SizedBox(height: 4),
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
    final hc = context.hc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? hc.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: hc.accent.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? hc.accent : hc.textSecondary,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? hc.accent : hc.textSecondary,
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
    this.header,
    this.footer,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Scaffold(
      body: Column(
        children: [
          ?header,
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?footer,
          BottomNavigationBar(
            currentIndex: selectedIndex,
            onTap: onDestinationSelected,
            type: BottomNavigationBarType.fixed,
            backgroundColor: hc.surface,
            selectedFontSize: 10,
            unselectedFontSize: 10,
            iconSize: 22,
            selectedItemColor: hc.accent,
            unselectedItemColor: hc.textTertiary,
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
        ],
      ),
    );
  }
}
