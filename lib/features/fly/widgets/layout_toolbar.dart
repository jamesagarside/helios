import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/layout_profile.dart';
import '../../../shared/providers/layout_provider.dart';
import '../../../shared/theme/helios_colors.dart';

/// Compact toolbar for switching layout profiles on the Fly View.
/// Full management (create, delete, reset, duplicate) is in Setup.
class LayoutToolbar extends ConsumerWidget {
  const LayoutToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layoutState = ref.watch(layoutProvider);
    final editMode = layoutState.editMode;
    final activeName = layoutState.activeProfileName;
    final profiles = layoutState.profiles;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: HeliosColors.surfaceDim.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: editMode
              ? HeliosColors.accent.withValues(alpha: 0.5)
              : HeliosColors.border.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Profile dropdown
          _ProfileDropdown(
            profiles: profiles,
            activeName: activeName,
            onChanged: (name) {
              ref.read(layoutProvider.notifier).selectProfile(name);
            },
          ),
          const SizedBox(width: 4),
          // Edit mode toggle (lock/unlock widget dragging)
          _ToolbarButton(
            icon: editMode ? Icons.lock_open : Icons.lock,
            tooltip: editMode ? 'Lock layout' : 'Edit layout',
            active: editMode,
            onTap: () => ref.read(layoutProvider.notifier).toggleEditMode(),
          ),
        ],
      ),
    );
  }
}

class _ProfileDropdown extends StatelessWidget {
  const _ProfileDropdown({
    required this.profiles,
    required this.activeName,
    required this.onChanged,
  });

  final List<LayoutProfile> profiles;
  final String activeName;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: activeName,
        isDense: true,
        dropdownColor: HeliosColors.surface,
        icon: const Icon(Icons.expand_more, size: 12, color: HeliosColors.textSecondary),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: HeliosColors.textPrimary,
        ),
        items: profiles.map((p) {
          return DropdownMenuItem(
            value: p.name,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _vehicleIcon(p.vehicleType),
                  size: 11,
                  color: p.name == activeName
                      ? HeliosColors.accent
                      : HeliosColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(p.name),
              ],
            ),
          );
        }).toList(),
        onChanged: (name) {
          if (name != null) onChanged(name);
        },
      ),
    );
  }

  IconData _vehicleIcon(VehicleType type) {
    return switch (type) {
      VehicleType.multirotor => Icons.toys,
      VehicleType.fixedWing => Icons.flight,
      VehicleType.vtol => Icons.connecting_airports,
    };
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: active
                ? HeliosColors.accent.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(
            icon,
            size: 13,
            color: active ? HeliosColors.accent : HeliosColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
