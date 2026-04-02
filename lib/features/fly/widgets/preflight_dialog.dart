import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Shows the preflight checklist dialog and returns true if "All Clear"
/// was pressed, false if dismissed.
Future<bool> showPreflightDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PreflightDialogContent(),
  );
  return result ?? false;
}

class _PreflightDialogContent extends ConsumerStatefulWidget {
  const _PreflightDialogContent();

  @override
  ConsumerState<_PreflightDialogContent> createState() =>
      _PreflightDialogContentState();
}

class _PreflightDialogContentState
    extends ConsumerState<_PreflightDialogContent> {
  final Set<int> _manualChecks = {};
  late final Stopwatch _timer;
  late final Timer _tickTimer;
  String _elapsed = '00:00';

  static const _manualItems = [
    'Props secured and balanced',
    'Payload attached and secured',
    'Area clear of people',
    'Weather conditions acceptable',
    'Batteries fully charged',
    'SD card inserted (if recording)',
    'Flight plan reviewed',
    'Airspace authorization obtained',
  ];

  @override
  void initState() {
    super.initState();
    _timer = Stopwatch()..start();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final secs = _timer.elapsed.inSeconds;
        setState(() {
          _elapsed =
              '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.stop();
    _tickTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final autoChecks = _buildAutoChecks(vehicle);
    final allAutoPassed = autoChecks.every((c) => c.status != _CheckStatus.fail);
    final allManualDone = _manualChecks.length == _manualItems.length;
    final allClear = allAutoPassed && allManualDone;

    return Dialog(
      backgroundColor: hc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: hc.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(hc),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _sectionHeader('System Checks (Automated)', hc),
                  ...autoChecks.map((c) => _autoCheckTile(c, hc)),
                  const SizedBox(height: 12),
                  _sectionHeader('Manual Checks', hc),
                  for (var i = 0; i < _manualItems.length; i++)
                    _manualCheckTile(i, hc),
                ],
              ),
            ),
            _buildFooter(hc, allClear),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(HeliosColors hc) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(Icons.checklist_rounded, color: hc.accent, size: 20),
          const SizedBox(width: 8),
          Text(
            'Preflight Checklist',
            style: HeliosTypography.heading2.copyWith(color: hc.textPrimary),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: hc.surfaceLight,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _elapsed,
              style: HeliosTypography.small
                  .copyWith(color: hc.textTertiary, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, HeliosColors hc) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: HeliosTypography.caption.copyWith(
          color: hc.textTertiary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _autoCheckTile(_AutoCheck check, HeliosColors hc) {
    final Color iconColor;
    final IconData icon;
    switch (check.status) {
      case _CheckStatus.pass:
        iconColor = hc.success;
        icon = Icons.check_circle;
      case _CheckStatus.warn:
        iconColor = hc.warning;
        icon = Icons.warning_amber_rounded;
      case _CheckStatus.fail:
        iconColor = hc.danger;
        icon = Icons.cancel;
      case _CheckStatus.info:
        iconColor = hc.textTertiary;
        icon = Icons.info_outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              check.label,
              style: HeliosTypography.body.copyWith(color: hc.textPrimary),
            ),
          ),
          if (check.detail != null)
            Text(
              check.detail!,
              style: HeliosTypography.small.copyWith(color: hc.textTertiary),
            ),
        ],
      ),
    );
  }

  Widget _manualCheckTile(int index, HeliosColors hc) {
    final checked = _manualChecks.contains(index);
    return InkWell(
      onTap: () {
        setState(() {
          if (checked) {
            _manualChecks.remove(index);
          } else {
            _manualChecks.add(index);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: checked,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _manualChecks.add(index);
                    } else {
                      _manualChecks.remove(index);
                    }
                  });
                },
                activeColor: hc.success,
                side: BorderSide(color: hc.border),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _manualItems[index],
                style: HeliosTypography.body.copyWith(
                  color: checked ? hc.textTertiary : hc.textPrimary,
                  decoration: checked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(HeliosColors hc, bool allClear) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: hc.border)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _exportToClipboard,
            icon: Icon(Icons.copy, size: 16, color: hc.textTertiary),
            label: Text(
              'Copy',
              style: HeliosTypography.caption.copyWith(color: hc.textTertiary),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Dismiss',
              style: TextStyle(color: hc.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: allClear ? () => Navigator.of(context).pop(true) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: allClear ? hc.successDim : hc.surfaceLight,
              foregroundColor: allClear ? hc.textPrimary : hc.textTertiary,
              disabledBackgroundColor: hc.surfaceLight,
              disabledForegroundColor: hc.textTertiary,
            ),
            child: const Text('All Clear'),
          ),
        ],
      ),
    );
  }

  void _exportToClipboard() {
    final vehicle = ref.read(vehicleStateProvider);
    final autoChecks = _buildAutoChecks(vehicle);
    final buf = StringBuffer();
    buf.writeln('=== Helios Preflight Checklist ===');
    buf.writeln('Time: $_elapsed');
    buf.writeln();
    buf.writeln('--- System Checks ---');
    for (final c in autoChecks) {
      final status = switch (c.status) {
        _CheckStatus.pass => 'PASS',
        _CheckStatus.warn => 'WARN',
        _CheckStatus.fail => 'FAIL',
        _CheckStatus.info => 'INFO',
      };
      buf.writeln('[$status] ${c.label}${c.detail != null ? ' (${c.detail})' : ''}');
    }
    buf.writeln();
    buf.writeln('--- Manual Checks ---');
    for (var i = 0; i < _manualItems.length; i++) {
      final done = _manualChecks.contains(i) ? 'X' : ' ';
      buf.writeln('[$done] ${_manualItems[i]}');
    }

    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checklist copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  List<_AutoCheck> _buildAutoChecks(VehicleState vehicle) {
    return [
      // GPS fix quality
      _AutoCheck(
        label: 'GPS fix quality',
        status: switch (vehicle.gpsFix) {
          GpsFix.fix3d ||
          GpsFix.dgps ||
          GpsFix.rtkFloat ||
          GpsFix.rtkFixed =>
            _CheckStatus.pass,
          GpsFix.fix2d => _CheckStatus.warn,
          _ => _CheckStatus.fail,
        },
        detail: '${_gpsFixLabel(vehicle.gpsFix)} / ${vehicle.satellites} sats',
      ),

      // Battery level
      _AutoCheck(
        label: 'Battery level',
        status: vehicle.batteryRemaining < 0
            ? _CheckStatus.warn
            : vehicle.batteryRemaining >= 80
                ? _CheckStatus.pass
                : vehicle.batteryRemaining >= 50
                    ? _CheckStatus.warn
                    : _CheckStatus.fail,
        detail: vehicle.batteryRemaining < 0
            ? 'N/A'
            : '${vehicle.batteryRemaining}%',
      ),

      // EKF status
      _AutoCheck(
        label: 'EKF status',
        status: vehicle.ekfOk
            ? _CheckStatus.pass
            : vehicle.ekfHealth == 1
                ? _CheckStatus.warn
                : _CheckStatus.fail,
        detail: switch (vehicle.ekfHealth) {
          0 => 'Good',
          1 => 'Warning',
          _ => 'Bad',
        },
      ),

      // Compass health
      _AutoCheck(
        label: 'Compass calibrated',
        status: vehicle.sensorHealth == 0
            ? _CheckStatus.warn
            : vehicle.isSensorHealthy(0x04) // MavSensorBit.mag3d
                ? _CheckStatus.pass
                : _CheckStatus.fail,
        detail: vehicle.sensorHealth == 0
            ? 'No data'
            : vehicle.isSensorHealthy(0x04)
                ? 'Healthy'
                : 'Unhealthy',
      ),

      // RC connected
      _AutoCheck(
        label: 'RC connected',
        status: vehicle.rcChannelCount > 0
            ? _CheckStatus.pass
            : _CheckStatus.fail,
        detail: vehicle.rcChannelCount > 0
            ? '${vehicle.rcChannelCount} channels'
            : 'No RC',
      ),

      // Home position
      _AutoCheck(
        label: 'Home position set',
        status: vehicle.hasHome ? _CheckStatus.pass : _CheckStatus.fail,
        detail: vehicle.hasHome
            ? '${vehicle.homeLatitude.toStringAsFixed(5)}, ${vehicle.homeLongitude.toStringAsFixed(5)}'
            : 'Not set',
      ),

      // Flight mode
      _AutoCheck(
        label: 'Flight mode valid',
        status: vehicle.flightMode.name != 'UNKNOWN'
            ? _CheckStatus.pass
            : _CheckStatus.fail,
        detail: vehicle.flightMode.name,
      ),

      // Geofence (informational)
      const _AutoCheck(
        label: 'Geofence configured',
        status: _CheckStatus.info,
        detail: 'Check manually',
      ),

      // Airspace
      const _AutoCheck(
        label: 'Airspace clear',
        status: _CheckStatus.info,
        detail: 'Check manually',
      ),
    ];
  }

  String _gpsFixLabel(GpsFix fix) => switch (fix) {
        GpsFix.none => 'None',
        GpsFix.noFix => 'No Fix',
        GpsFix.fix2d => '2D',
        GpsFix.fix3d => '3D',
        GpsFix.dgps => 'DGPS',
        GpsFix.rtkFloat => 'RTK Float',
        GpsFix.rtkFixed => 'RTK Fixed',
      };
}

enum _CheckStatus { pass, warn, fail, info }

class _AutoCheck {
  const _AutoCheck({
    required this.label,
    required this.status,
    this.detail,
  });

  final String label;
  final _CheckStatus status;
  final String? detail;
}
