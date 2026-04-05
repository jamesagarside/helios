import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/simulate/sitl_injector.dart';
import '../../../core/simulate/sitl_launcher.dart';
import '../../../shared/models/connection_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Full Setup tab panel for launching and controlling ArduPilot SITL.
///
/// Platform: macOS, Linux (native binaries downloaded on demand).
/// Shows an informational message on iOS/Android/Windows where SITL is unavailable.
class SimulatePanel extends ConsumerStatefulWidget {
  const SimulatePanel({super.key});

  @override
  ConsumerState<SimulatePanel> createState() => _SimulatePanelState();
}

class _SimulatePanelState extends ConsumerState<SimulatePanel> {
  // ─── SITL state ──────────────────────────────────────────────────────────

  final _launcher = SitlLauncher();
  final _injector = const SitlInjector();
  bool _binaryCached = false;
  bool _launching = false;
  double _downloadProgress = 0;

  // ─── Configuration ───────────────────────────────────────────────────────

  String _vehicle = SitlLauncher.vehicles.first;
  String _frame = SitlLauncher.frames[SitlLauncher.vehicles.first]!.first;
  double _altM = 0;

  SitlLocation _selectedLocation = SitlLauncher.locations.first;
  final _latController =
      TextEditingController(text: SitlLauncher.locations.first.lat.toString());
  final _lonController =
      TextEditingController(text: SitlLauncher.locations.first.lon.toString());
  final _headingController = TextEditingController(
      text: SitlLauncher.locations.first.heading.toString());

  // ─── Simulation controls ─────────────────────────────────────────────────

  int _speedMultiplier = 1;
  double _windSpeed = 0;
  double _windDir = 0;
  bool _gpsFailed = false;
  bool _compassFailed = false;
  double _batteryVoltage = 12.6;

  // ─── Log ─────────────────────────────────────────────────────────────────

  final List<String> _logLines = [];
  final ScrollController _logScrollController = ScrollController();

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _checkCached();
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _headingController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  // ─── Binary cache check ──────────────────────────────────────────────────

  Future<void> _checkCached() async {
    final cached = await SitlLauncher.isCached(_vehicle);
    if (mounted) {
      setState(() => _binaryCached = cached);
    }
  }

  // ─── Log helpers ─────────────────────────────────────────────────────────

  void _addLog(String line) {
    if (!mounted) return;
    setState(() => _logLines.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Launch / stop ───────────────────────────────────────────────────────

  Future<void> _launch() async {
    final lat = double.tryParse(_latController.text) ??
        _selectedLocation.lat;
    final lon = double.tryParse(_lonController.text) ??
        _selectedLocation.lon;
    final heading = double.tryParse(_headingController.text) ??
        _selectedLocation.heading;

    setState(() {
      _launching = true;
      _downloadProgress = 0;
      _logLines.clear();
    });

    try {
      await _launcher.launch(
        vehicle: _vehicle,
        frame: _frame,
        lat: lat,
        lon: lon,
        altM: _altM,
        headingDeg: heading,
        onLog: _addLog,
        onExit: () {
          if (mounted) setState(() {});
        },
        onDownloadProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );

      if (mounted) {
        setState(() => _launching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connecting to SITL on TCP 127.0.0.1:5760...'),
            duration: Duration(seconds: 3),
          ),
        );
        // Auto-connect via TCP
        await ref
            .read(connectionControllerProvider.notifier)
            .connect(const TcpConnectionConfig(host: '127.0.0.1', port: 5760));
      }
    } on SitlLaunchException catch (e) {
      if (mounted) {
        setState(() => _launching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: context.hc.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _launching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to launch SITL: $e'),
            backgroundColor: context.hc.danger,
          ),
        );
      }
    }
  }

  Future<void> _stop() async {
    await _launcher.stop();
    setState(() {});
  }

  // ─── Injection helpers ───────────────────────────────────────────────────

  Future<void> _applyWind() =>
      _injector.setWind(ref, _windSpeed, _windDir);

  Future<void> _applyGps(bool fail) async {
    setState(() => _gpsFailed = fail);
    await _injector.setGpsFailure(ref, fail: fail);
  }

  Future<void> _applyCompass(bool fail) async {
    setState(() => _compassFailed = fail);
    await _injector.setCompassFailure(ref, fail: fail);
  }

  Future<void> _applyBattery() =>
      _injector.setBatteryVoltage(ref, _batteryVoltage);

  Future<void> _applySpeed(int multiplier) async {
    setState(() => _speedMultiplier = multiplier);
    await _injector.setSpeedMultiplier(ref, multiplier);
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // iOS / Android: Docker/SITL is not available.
    if (kIsWeb || Platform.isIOS || Platform.isAndroid) {
      return _PlatformUnavailable();
    }

    final hc = context.hc;
    final isRunning = _launcher.isRunning;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status ──────────────────────────────────────────────────────
          _SectionCard(
            title: 'SITL STATUS',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusRow(
                  label: 'Binary',
                  value: _binaryCached ? 'Cached' : 'Not downloaded',
                  color: _binaryCached ? hc.success : hc.textSecondary,
                ),
                const SizedBox(height: 8),
                _StatusRow(
                  label: 'SITL',
                  value: isRunning ? 'Running' : 'Stopped',
                  color: isRunning ? hc.success : hc.textSecondary,
                ),
                if (_launching && !_binaryCached) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _downloadProgress > 0 ? _downloadProgress : null,
                      backgroundColor: hc.surfaceLight,
                      valueColor: AlwaysStoppedAnimation(hc.accent),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Downloading $_vehicle binary... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                    style: HeliosTypography.small
                        .copyWith(color: hc.textTertiary),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: isRunning
                      ? FilledButton.tonal(
                          onPressed: _stop,
                          style: FilledButton.styleFrom(
                            backgroundColor: hc.dangerDim,
                            foregroundColor: hc.textPrimary,
                          ),
                          child: const Text('Stop SITL'),
                        )
                      : FilledButton(
                          onPressed: _launching ? null : _launch,
                          style: FilledButton.styleFrom(
                            backgroundColor: hc.accentDim,
                            foregroundColor: hc.textPrimary,
                            disabledBackgroundColor:
                                hc.surfaceLight,
                            disabledForegroundColor: hc.textTertiary,
                          ),
                          child: _launching
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Text(_binaryCached
                                  ? 'Launch SITL'
                                  : 'Download & Launch'),
                        ),
                ),
                if (!_binaryCached && !_launching)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'The $_vehicle binary will be downloaded on first launch (~30 MB).',
                      style: HeliosTypography.small
                          .copyWith(color: hc.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Vehicle config (only when stopped) ──────────────────────────
          if (!isRunning) ...[
            _SectionCard(
              title: 'VEHICLE CONFIGURATION',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DropdownRow(
                    label: 'Vehicle',
                    value: _vehicle,
                    items: SitlLauncher.vehicles,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _vehicle = v;
                        _frame =
                            SitlLauncher.frames[v]!.first;
                      });
                      _checkCached();
                    },
                  ),
                  const SizedBox(height: 12),
                  _DropdownRow(
                    label: 'Frame',
                    value: _frame,
                    items: SitlLauncher.frames[_vehicle] ?? [],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _frame = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          'Start Altitude (m)',
                          style: HeliosTypography.caption
                              .copyWith(color: hc.textSecondary),
                        ),
                      ),
                      Expanded(
                        child: TextFormField(
                          initialValue: _altM.toStringAsFixed(0),
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                              fontSize: 13, color: hc.textPrimary),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: hc.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: hc.border),
                            ),
                          ),
                          onChanged: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null) {
                              setState(() => _altM = parsed);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Start location ───────────────────────────────────────────
            _SectionCard(
              title: 'START LOCATION',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DropdownRow(
                    label: 'Location',
                    value: _selectedLocation.name,
                    items: SitlLauncher.locations
                        .map((l) => l.name)
                        .toList(),
                    onChanged: (name) {
                      if (name == null) return;
                      final loc = SitlLauncher.locations
                          .firstWhere((l) => l.name == name);
                      setState(() {
                        _selectedLocation = loc;
                        if (!loc.isCustom) {
                          _latController.text =
                              loc.lat.toStringAsFixed(4);
                          _lonController.text =
                              loc.lon.toStringAsFixed(4);
                          _headingController.text =
                              loc.heading.toStringAsFixed(0);
                        }
                      });
                    },
                  ),
                  if (_selectedLocation.isCustom) ...[
                    const SizedBox(height: 12),
                    _CoordField(
                        label: 'Latitude', controller: _latController),
                    const SizedBox(height: 8),
                    _CoordField(
                        label: 'Longitude', controller: _lonController),
                    const SizedBox(height: 8),
                    _CoordField(
                        label: 'Heading (°)',
                        controller: _headingController),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Log ─────────────────────────────────────────────────────────
          _SectionCard(
            title: 'SITL LOG',
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
              ),
              child: _logLines.isEmpty
                  ? Center(
                      child: Text(
                        'No output yet.',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.green,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: _logLines.length,
                      itemBuilder: (_, i) => Text(
                        _logLines[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.green,
                          height: 1.4,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Simulation controls (only when running) ──────────────────────
          if (isRunning) ...[
            _SectionCard(
              title: 'SIMULATION CONTROLS',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Speed multiplier
                  Text(
                    'Speed',
                    style: HeliosTypography.caption
                        .copyWith(color: hc.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1x')),
                      ButtonSegment(value: 2, label: Text('2x')),
                      ButtonSegment(value: 4, label: Text('4x')),
                      ButtonSegment(value: 8, label: Text('8x')),
                    ],
                    selected: {_speedMultiplier},
                    onSelectionChanged: (s) => _applySpeed(s.first),
                    style: ButtonStyle(
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return hc.accentDim;
                        }
                        return hc.surfaceLight;
                      }),
                      foregroundColor:
                          WidgetStateProperty.all(hc.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Wind speed
                  _SliderRow(
                    label: 'Wind Speed',
                    value: _windSpeed,
                    min: 0,
                    max: 20,
                    divisions: 40,
                    unit: 'm/s',
                    onChanged: (v) => setState(() => _windSpeed = v),
                    onChangeEnd: (_) => _applyWind(),
                  ),
                  const SizedBox(height: 8),

                  // Wind direction
                  _SliderRow(
                    label: 'Wind Direction',
                    value: _windDir,
                    min: 0,
                    max: 360,
                    divisions: 36,
                    unit: '°',
                    onChanged: (v) => setState(() => _windDir = v),
                    onChangeEnd: (_) => _applyWind(),
                  ),
                  const SizedBox(height: 20),

                  // Failures
                  Text(
                    'Failures',
                    style: HeliosTypography.caption
                        .copyWith(color: hc.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  _ToggleRow(
                    label: 'GPS',
                    failed: _gpsFailed,
                    onChanged: _applyGps,
                  ),
                  const SizedBox(height: 8),
                  _ToggleRow(
                    label: 'Compass',
                    failed: _compassFailed,
                    onChanged: _applyCompass,
                  ),
                  const SizedBox(height: 12),

                  // Battery voltage
                  _SliderRow(
                    label: 'Battery Voltage',
                    value: _batteryVoltage,
                    min: 8,
                    max: 16,
                    divisions: 32,
                    unit: 'V',
                    onChanged: (v) =>
                        setState(() => _batteryVoltage = v),
                    onChangeEnd: (_) => _applyBattery(),
                  ),
                  const SizedBox(height: 16),

                  // Info
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: hc.accentDim.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: hc.accent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 14, color: hc.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Helios auto-connects via TCP after launch. No Docker required.',
                            style: HeliosTypography.small
                                .copyWith(color: hc.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

// ─── Platform unavailable ─────────────────────────────────────────────────────

class _PlatformUnavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rocket_launch_outlined,
                size: 48, color: hc.textTertiary),
            const SizedBox(height: 16),
            Text(
              'SITL Not Available',
              style: HeliosTypography.heading2
                  .copyWith(color: hc.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'SITL simulation requires native ArduPilot binaries, '
              'which are only available on macOS and Linux.',
              textAlign: TextAlign.center,
              style: HeliosTypography.body
                  .copyWith(color: hc.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: HeliosTypography.small.copyWith(
              fontWeight: FontWeight.w600,
              color: hc.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hc.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ],
    );
  }
}

// ─── Status row ───────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: HeliosTypography.caption
              .copyWith(color: hc.textSecondary),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: HeliosTypography.caption
              .copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ─── Dropdown row ─────────────────────────────────────────────────────────────

class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: HeliosTypography.caption
                .copyWith(color: hc.textSecondary),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: items.contains(value) ? value : items.firstOrNull,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: hc.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: hc.border),
              ),
            ),
            dropdownColor: hc.surface,
            style: HeliosTypography.caption
                .copyWith(color: hc.textPrimary),
            items: items
                .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ─── Coordinate field ────────────────────────────────────────────────────────

class _CoordField extends StatelessWidget {
  const _CoordField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: HeliosTypography.caption
                .copyWith(color: hc.textSecondary),
          ),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
            style: TextStyle(fontSize: 13, color: hc.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: hc.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: hc.border),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Slider row ───────────────────────────────────────────────────────────────

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
    required this.onChangeEnd,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: HeliosTypography.caption
                .copyWith(color: hc.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: hc.accent,
            inactiveColor: hc.border,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '${value.toStringAsFixed(1)} $unit',
            textAlign: TextAlign.end,
            style: HeliosTypography.caption
                .copyWith(color: hc.textPrimary),
          ),
        ),
      ],
    );
  }
}

// ─── Toggle row (normal / failed) ────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.failed,
    required this.onChanged,
  });

  final String label;
  final bool failed;
  final Future<void> Function(bool fail) onChanged;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: HeliosTypography.caption
                .copyWith(color: hc.textSecondary),
          ),
        ),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text('Normal',
                  style: HeliosTypography.small
                      .copyWith(color: hc.textPrimary)),
            ),
            ButtonSegment(
              value: true,
              label: Text('Failed',
                  style: HeliosTypography.small
                      .copyWith(color: hc.textPrimary)),
            ),
          ],
          selected: {failed},
          onSelectionChanged: (s) => onChanged(s.first),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return failed ? hc.dangerDim : hc.successDim;
              }
              return hc.surfaceLight;
            }),
            foregroundColor:
                WidgetStateProperty.all(hc.textPrimary),
          ),
        ),
      ],
    );
  }
}
