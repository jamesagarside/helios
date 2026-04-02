import '../../shared/models/vehicle_state.dart';

/// Metadata for a single telemetry field that can be displayed as a tile.
class TelemetryFieldDef {
  const TelemetryFieldDef({
    required this.id,
    required this.label,
    required this.unit,
    required this.getter,
    this.category = 'General',
    this.formatDecimals = 1,
    this.customFormat,
  });

  /// Unique identifier — stored in LayoutProfile.
  final String id;

  /// Short display label (e.g. 'IAS', 'BATT%').
  final String label;

  /// Unit string appended after value (e.g. 'm/s', 'V', '°').
  final String unit;

  /// Extracts the numeric value from VehicleState.
  final double Function(VehicleState) getter;

  /// Grouping for the picker dialog.
  final String category;

  /// Number of decimal places for display.
  final int formatDecimals;

  /// Optional custom formatter — overrides default decimal formatting.
  final String Function(double)? customFormat;

  /// Format value as a display string.
  String format(double value) {
    if (customFormat != null) return customFormat!(value);
    if (formatDecimals == 0) return value.round().toString();
    return value.toStringAsFixed(formatDecimals);
  }
}

/// Registry of all displayable telemetry fields.
abstract final class TelemetryFieldRegistry {
  static final all = <TelemetryFieldDef>[
    // ── Battery ────────────────────────────────────────────────────────────
    TelemetryFieldDef(
      id: 'bat_v',
      label: 'BATT',
      unit: 'V',
      getter: _battVoltage,
      category: 'Battery',
    ),
    TelemetryFieldDef(
      id: 'bat_pct',
      label: 'BAT%',
      unit: '%',
      getter: _battPct,
      category: 'Battery',
      formatDecimals: 0,
    ),
    TelemetryFieldDef(
      id: 'bat_a',
      label: 'CURR',
      unit: 'A',
      getter: _battCurrent,
      category: 'Battery',
    ),
    TelemetryFieldDef(
      id: 'bat_mah',
      label: 'MAH',
      unit: 'mAh',
      getter: _battConsumed,
      category: 'Battery',
      formatDecimals: 0,
    ),
    // ── GPS ────────────────────────────────────────────────────────────────
    TelemetryFieldDef(
      id: 'gps_sats',
      label: 'SATS',
      unit: '',
      getter: _satellites,
      category: 'GPS',
      formatDecimals: 0,
    ),
    TelemetryFieldDef(
      id: 'gps_hdop',
      label: 'HDOP',
      unit: '',
      getter: _hdop,
      category: 'GPS',
      customFormat: (v) => v < 50 ? v.toStringAsFixed(1) : '--',
    ),
    TelemetryFieldDef(
      id: 'gps_lat',
      label: 'LAT',
      unit: '°',
      getter: _lat,
      category: 'GPS',
      formatDecimals: 6,
    ),
    TelemetryFieldDef(
      id: 'gps_lon',
      label: 'LON',
      unit: '°',
      getter: _lon,
      category: 'GPS',
      formatDecimals: 6,
    ),
    // ── Altitude ──────────────────────────────────────────────────────────
    TelemetryFieldDef(
      id: 'alt_rel',
      label: 'ALT',
      unit: 'm',
      getter: _altRel,
      category: 'Altitude',
    ),
    TelemetryFieldDef(
      id: 'alt_msl',
      label: 'MSL',
      unit: 'm',
      getter: _altMsl,
      category: 'Altitude',
      formatDecimals: 0,
    ),
    // ── Speed ─────────────────────────────────────────────────────────────
    TelemetryFieldDef(
      id: 'spd_ias',
      label: 'IAS',
      unit: 'm/s',
      getter: _airspeed,
      category: 'Speed',
    ),
    TelemetryFieldDef(
      id: 'spd_gs',
      label: 'GS',
      unit: 'm/s',
      getter: _groundspeed,
      category: 'Speed',
    ),
    TelemetryFieldDef(
      id: 'spd_vs',
      label: 'VS',
      unit: 'm/s',
      getter: _climbRate,
      category: 'Speed',
    ),
    // ── Attitude ──────────────────────────────────────────────────────────
    TelemetryFieldDef(
      id: 'att_roll',
      label: 'ROLL',
      unit: '°',
      getter: _rollDeg,
      category: 'Attitude',
    ),
    TelemetryFieldDef(
      id: 'att_pitch',
      label: 'PITCH',
      unit: '°',
      getter: _pitchDeg,
      category: 'Attitude',
    ),
    TelemetryFieldDef(
      id: 'att_hdg',
      label: 'HDG',
      unit: '°',
      getter: _heading,
      category: 'Attitude',
      formatDecimals: 0,
    ),
    // ── Control ──────────────────────────────────────────────────────────
    TelemetryFieldDef(
      id: 'thr',
      label: 'THR',
      unit: '%',
      getter: _throttle,
      category: 'Control',
      formatDecimals: 0,
    ),
    // ── Link ─────────────────────────────────────────────────────────────
    TelemetryFieldDef(
      id: 'rssi',
      label: 'RSSI',
      unit: '',
      getter: _rssi,
      category: 'Link',
      formatDecimals: 0,
    ),
    // ── Wind ─────────────────────────────────────────────────────────────
    TelemetryFieldDef(
      id: 'wind_spd',
      label: 'WIND',
      unit: 'm/s',
      getter: _windSpeed,
      category: 'Wind',
    ),
    TelemetryFieldDef(
      id: 'wind_dir',
      label: 'WDIR',
      unit: '°',
      getter: _windDir,
      category: 'Wind',
      formatDecimals: 0,
    ),
    // ── EKF ──────────────────────────────────────────────────────────────
    TelemetryFieldDef(
      id: 'ekf_vel',
      label: 'EKF-V',
      unit: '',
      getter: _ekfVel,
      category: 'EKF',
    ),
    TelemetryFieldDef(
      id: 'ekf_pos',
      label: 'EKF-P',
      unit: '',
      getter: _ekfPos,
      category: 'EKF',
    ),
  ];

  /// Map for O(1) lookup by id.
  static final Map<String, TelemetryFieldDef> _byId = {
    for (final f in all) f.id: f,
  };

  static TelemetryFieldDef? byId(String id) => _byId[id];

  /// Fields grouped by category.
  static Map<String, List<TelemetryFieldDef>> get byCategory {
    final map = <String, List<TelemetryFieldDef>>{};
    for (final f in all) {
      (map[f.category] ??= []).add(f);
    }
    return map;
  }

  // ── Default tile set ────────────────────────────────────────────────────────

  static const defaultTileIds = <String>[
    'bat_v',
    'bat_pct',
    'gps_sats',
    'gps_hdop',
    'spd_ias',
    'spd_gs',
    'alt_rel',
    'alt_msl',
    'spd_vs',
    'att_hdg',
    'thr',
    'rssi',
  ];
}

// ── Private getters ──────────────────────────────────────────────────────────

double _battVoltage(VehicleState v) => v.batteryVoltage;
double _battPct(VehicleState v) => v.batteryRemaining.toDouble();
double _battCurrent(VehicleState v) => v.batteryCurrent;
double _battConsumed(VehicleState v) => v.batteryConsumed;

double _satellites(VehicleState v) => v.satellites.toDouble();
double _hdop(VehicleState v) => v.hdop;
double _lat(VehicleState v) => v.latitude;
double _lon(VehicleState v) => v.longitude;

double _altRel(VehicleState v) => v.altitudeRel;
double _altMsl(VehicleState v) => v.altitudeMsl;

double _airspeed(VehicleState v) => v.airspeed;
double _groundspeed(VehicleState v) => v.groundspeed;
double _climbRate(VehicleState v) => v.climbRate;

double _rollDeg(VehicleState v) => v.roll * 180 / 3.14159265;
double _pitchDeg(VehicleState v) => v.pitch * 180 / 3.14159265;
double _heading(VehicleState v) => v.heading.toDouble();

double _throttle(VehicleState v) => v.throttle.toDouble();
double _rssi(VehicleState v) => v.rssi.toDouble();

double _windSpeed(VehicleState v) => v.windSpeed;
double _windDir(VehicleState v) => v.windDirection;

double _ekfVel(VehicleState v) => v.ekfVelocityVar;
double _ekfPos(VehicleState v) => v.ekfPosHorizVar;
