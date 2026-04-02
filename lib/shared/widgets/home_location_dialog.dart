import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/home_location.dart';
import '../providers/home_location_provider.dart';
import '../providers/providers.dart';
import '../theme/helios_colors.dart';

/// Dialog for managing saved home/launch locations.
///
/// Shows a searchable list with add/edit/delete, set-default, CSV import,
/// and "Go to" map-pan support via the [onGoTo] callback.
class HomeLocationDialog extends ConsumerStatefulWidget {
  const HomeLocationDialog({
    super.key,
    this.onGoTo,
    this.mapCenter,
  });

  /// Called when the user taps "Go to" on a location.
  final void Function(LatLng position)? onGoTo;

  /// Current map centre — used for "Add from Map Centre".
  final LatLng? mapCenter;

  @override
  ConsumerState<HomeLocationDialog> createState() => _HomeLocationDialogState();
}

class _HomeLocationDialogState extends ConsumerState<HomeLocationDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final locations = ref.watch(savedLocationsProvider);
    final filtered = _filter.isEmpty
        ? locations
        : locations
            .where(
              (h) =>
                  h.name.toLowerCase().contains(_filter.toLowerCase()) ||
                  h.notes.toLowerCase().contains(_filter.toLowerCase()),
            )
            .toList();

    return Dialog(
      backgroundColor: hc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: hc.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────
            _Header(
              hc: hc,
              onFilterChanged: (v) => setState(() => _filter = v),
            ),

            const Divider(height: 1),

            // ── List ────────────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _filter.isEmpty
                            ? 'No saved locations'
                            : 'No matching locations',
                        style: TextStyle(color: hc.textTertiary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: hc.border.withValues(alpha: 0.4),
                      ),
                      itemBuilder: (context, index) {
                        final loc = filtered[index];
                        return _LocationTile(
                          location: loc,
                          onSetDefault: () => ref
                              .read(savedLocationsProvider.notifier)
                              .setDefault(loc.name),
                          onDelete: () => ref
                              .read(savedLocationsProvider.notifier)
                              .remove(loc.name),
                          onGoTo: widget.onGoTo != null
                              ? () {
                                  widget.onGoTo!(loc.position);
                                  Navigator.of(context).pop();
                                }
                              : null,
                        );
                      },
                    ),
            ),

            const Divider(height: 1),

            // ── Bottom actions ──────────────────────────────────────
            _BottomBar(
              onAddCurrent: _addFromVehicle,
              onAddManual: () => _showManualDialog(context),
              onAddMapCenter: widget.mapCenter != null
                  ? () => _addMapCenter(context)
                  : null,
              onImportCsv: () => _importCsv(context),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  void _addFromVehicle() {
    final vehicle = ref.read(vehicleStateProvider);
    if (!vehicle.hasPosition) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No GPS fix — cannot read position')),
      );
      return;
    }
    ref.read(savedLocationsProvider.notifier).add(
          HomeLocation(
            name: 'Vehicle ${DateTime.now().toIso8601String().substring(0, 16)}',
            position: LatLng(vehicle.latitude, vehicle.longitude),
            altitude: vehicle.altitudeMsl,
          ),
        );
  }

  void _addMapCenter(BuildContext context) {
    final center = widget.mapCenter;
    if (center == null) return;
    ref.read(savedLocationsProvider.notifier).add(
          HomeLocation(
            name: 'Map ${DateTime.now().toIso8601String().substring(0, 16)}',
            position: center,
          ),
        );
  }

  Future<void> _showManualDialog(BuildContext context) async {
    final result = await showDialog<HomeLocation>(
      context: context,
      builder: (_) => const _ManualEntryDialog(),
    );
    if (result != null && mounted) {
      ref.read(savedLocationsProvider.notifier).add(result);
    }
  }

  Future<void> _importCsv(BuildContext _) async {
    final pickerResult = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (pickerResult == null || pickerResult.files.isEmpty) return;
    final path = pickerResult.files.first.path;
    if (path == null) return;
    final csv = await File(path).readAsString();
    final count =
        ref.read(savedLocationsProvider.notifier).importCsv(csv);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported $count location(s)')),
    );
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.hc, required this.onFilterChanged});

  final HeliosColors hc;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Row(
        children: [
          Icon(Icons.home_work, size: 20, color: hc.accent),
          const SizedBox(width: 8),
          Text(
            'Saved Locations',
            style: TextStyle(
              color: hc.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 180,
            height: 32,
            child: TextField(
              style: TextStyle(color: hc.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: hc.textTertiary, fontSize: 13),
                prefixIcon: Icon(Icons.search, size: 16, color: hc.textTertiary),
                isDense: true,
                filled: true,
                fillColor: hc.surfaceLight,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: hc.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: hc.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: hc.accent),
                ),
              ),
              onChanged: onFilterChanged,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: hc.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 16,
          ),
        ],
      ),
    );
  }
}

// ─── Location tile ──────────────────────────────────────────────────────────

class _LocationTile extends StatelessWidget {
  const _LocationTile({
    required this.location,
    required this.onSetDefault,
    required this.onDelete,
    this.onGoTo,
  });

  final HomeLocation location;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final VoidCallback? onGoTo;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Default star
          GestureDetector(
            onTap: onSetDefault,
            child: Icon(
              location.isDefault ? Icons.star : Icons.star_border,
              size: 18,
              color: location.isDefault ? hc.warning : hc.textTertiary,
            ),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  location.name,
                  style: TextStyle(
                    color: hc.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${location.position.latitude.toStringAsFixed(6)}, '
                  '${location.position.longitude.toStringAsFixed(6)}'
                  '${location.altitude != 0 ? '  alt ${location.altitude.toStringAsFixed(0)} m' : ''}',
                  style: TextStyle(color: hc.textTertiary, fontSize: 11),
                ),
                if (location.notes.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    location.notes,
                    style: TextStyle(color: hc.textTertiary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          // Go to
          if (onGoTo != null)
            IconButton(
              icon: Icon(Icons.my_location, size: 16, color: hc.accent),
              onPressed: onGoTo,
              tooltip: 'Go to location',
              splashRadius: 14,
            ),
          // Delete
          IconButton(
            icon: Icon(Icons.delete_outline, size: 16, color: hc.danger),
            onPressed: onDelete,
            tooltip: 'Delete',
            splashRadius: 14,
          ),
        ],
      ),
    );
  }
}

// ─── Bottom bar ─────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.onAddCurrent,
    required this.onAddManual,
    this.onAddMapCenter,
    required this.onImportCsv,
  });

  final VoidCallback onAddCurrent;
  final VoidCallback onAddManual;
  final VoidCallback? onAddMapCenter;
  final VoidCallback onImportCsv;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          _ActionChip(
            icon: Icons.gps_fixed,
            label: 'Add Vehicle Pos',
            hc: hc,
            onPressed: onAddCurrent,
          ),
          if (onAddMapCenter != null)
            _ActionChip(
              icon: Icons.center_focus_strong,
              label: 'Add Map Centre',
              hc: hc,
              onPressed: onAddMapCenter!,
            ),
          _ActionChip(
            icon: Icons.edit_location_alt,
            label: 'Add Manual',
            hc: hc,
            onPressed: onAddManual,
          ),
          _ActionChip(
            icon: Icons.file_upload_outlined,
            label: 'Import CSV',
            hc: hc,
            onPressed: onImportCsv,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.hc,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final HeliosColors hc;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 14, color: hc.accent),
      label: Text(
        label,
        style: TextStyle(color: hc.textPrimary, fontSize: 12),
      ),
      backgroundColor: hc.surfaceLight,
      side: BorderSide(color: hc.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      onPressed: onPressed,
    );
  }
}

// ─── Manual entry dialog ────────────────────────────────────────────────────

class _ManualEntryDialog extends StatefulWidget {
  const _ManualEntryDialog();

  @override
  State<_ManualEntryDialog> createState() => _ManualEntryDialogState();
}

class _ManualEntryDialogState extends State<_ManualEntryDialog> {
  final _nameCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lonCtrl = TextEditingController();
  final _altCtrl = TextEditingController(text: '0');
  final _notesCtrl = TextEditingController();

  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _altCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final lat = double.tryParse(_latCtrl.text.trim());
    final lon = double.tryParse(_lonCtrl.text.trim());
    final alt = double.tryParse(_altCtrl.text.trim()) ?? 0;

    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    if (lat == null || lat < -90 || lat > 90) {
      setState(() => _error = 'Latitude must be between -90 and 90');
      return;
    }
    if (lon == null || lon < -180 || lon > 180) {
      setState(() => _error = 'Longitude must be between -180 and 180');
      return;
    }

    Navigator.of(context).pop(HomeLocation(
      name: name,
      position: LatLng(lat, lon),
      altitude: alt,
      notes: _notesCtrl.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return AlertDialog(
      backgroundColor: hc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: hc.border),
      ),
      title: Text(
        'Add Location',
        style: TextStyle(color: hc.textPrimary, fontSize: 15),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field('Name', _nameCtrl, hc),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field('Latitude', _latCtrl, hc, numeric: true)),
                const SizedBox(width: 8),
                Expanded(child: _field('Longitude', _lonCtrl, hc, numeric: true)),
              ],
            ),
            const SizedBox(height: 8),
            _field('Altitude (m MSL)', _altCtrl, hc, numeric: true),
            const SizedBox(height: 8),
            _field('Notes (optional)', _notesCtrl, hc),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: hc.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: hc.textSecondary)),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: hc.accent),
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl,
    HeliosColors hc, {
    bool numeric = false,
  }) {
    return TextField(
      controller: ctrl,
      style: TextStyle(color: hc.textPrimary, fontSize: 13),
      keyboardType:
          numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: hc.textTertiary, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: hc.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hc.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: hc.accent),
        ),
      ),
    );
  }
}
