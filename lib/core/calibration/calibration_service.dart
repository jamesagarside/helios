import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import '../mavlink/mavlink_service.dart';

/// Calibration type.
enum CalibrationType { compass, accel, gyro, level }

/// State of a calibration procedure.
enum CalibrationState { idle, running, waitingOrientation, success, failed }

/// Progress update during calibration.
class CalibrationProgress {
  const CalibrationProgress({
    this.state = CalibrationState.idle,
    this.type,
    this.completionPct = 0,
    this.compassId = 0,
    this.message = '',
    this.fitness = 0,
  });

  final CalibrationState state;
  final CalibrationType? type;
  final int completionPct;
  final int compassId;
  final String message;
  final double fitness;
}

/// Service for flight controller sensor calibration.
///
/// Calibration flow:
///   1. Send MAV_CMD_PREFLIGHT_CALIBRATION with appropriate param
///   2. Listen for STATUSTEXT for step instructions
///   3. For compass: listen for MAG_CAL_PROGRESS and MAG_CAL_REPORT
///   4. For accel: listen for STATUSTEXT orientation prompts
///   5. For gyro/level: just wait for completion STATUSTEXT
class CalibrationService {
  CalibrationService(this._mavlink);

  final MavlinkService _mavlink;
  StreamSubscription<MavlinkMessage>? _sub;

  final _progressController = StreamController<CalibrationProgress>.broadcast();
  Stream<CalibrationProgress> get progressStream => _progressController.stream;

  CalibrationProgress _current = const CalibrationProgress();

  /// Start compass calibration (mag cal).
  Future<void> startCompassCal({
    required int targetSystem,
    required int targetComponent,
  }) async {
    _current = const CalibrationProgress(
      state: CalibrationState.running,
      type: CalibrationType.compass,
      message: 'Starting compass calibration...\nRotate vehicle in all orientations.',
    );
    _progressController.add(_current);

    _sub?.cancel();
    _sub = _mavlink.messageStream.listen((msg) {
      if (msg is MagCalProgressMessage) {
        _current = CalibrationProgress(
          state: CalibrationState.running,
          type: CalibrationType.compass,
          completionPct: msg.completionPct,
          compassId: msg.compassId,
          message: 'Compass ${msg.compassId}: ${msg.completionPct}%\nRotate vehicle slowly in all directions.',
        );
        _progressController.add(_current);
      } else if (msg is MagCalReportMessage) {
        _current = CalibrationProgress(
          state: msg.success ? CalibrationState.success : CalibrationState.failed,
          type: CalibrationType.compass,
          completionPct: 100,
          compassId: msg.compassId,
          fitness: msg.fitness,
          message: msg.success
              ? 'Compass ${msg.compassId} calibrated. Fitness: ${msg.fitness.toStringAsFixed(1)} mGauss'
              : 'Compass ${msg.compassId} calibration failed.',
        );
        _progressController.add(_current);
        _sub?.cancel();
        _sub = null;
      } else if (msg is StatusTextMessage) {
        // Forward calibration-related status text
        if (msg.text.contains('Cal') || msg.text.contains('compass') || msg.text.contains('Mag')) {
          _current = CalibrationProgress(
            state: _current.state,
            type: CalibrationType.compass,
            completionPct: _current.completionPct,
            compassId: _current.compassId,
            message: msg.text,
          );
          _progressController.add(_current);
        }
      }
    });

    // MAV_CMD_PREFLIGHT_CALIBRATION: param1=0(gyro), param2=1(mag), param3=0(baro), param4=0, param5=0(accel)
    await _mavlink.sendCommand(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      command: 241, // MAV_CMD_PREFLIGHT_CALIBRATION
      param2: 1, // magnetometer
    );
  }

  /// Start accelerometer calibration.
  Future<void> startAccelCal({
    required int targetSystem,
    required int targetComponent,
  }) async {
    _startSimpleCal(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      type: CalibrationType.accel,
      command: 241,
      param5: 1, // accel cal
      startMessage: 'Starting accelerometer calibration.\nPlace vehicle level and press when ready.',
    );
  }

  /// Start gyroscope calibration.
  Future<void> startGyroCal({
    required int targetSystem,
    required int targetComponent,
  }) async {
    _startSimpleCal(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      type: CalibrationType.gyro,
      command: 241,
      param1: 1, // gyro cal
      startMessage: 'Starting gyro calibration.\nKeep vehicle completely still.',
    );
  }

  /// Start level calibration (trim).
  Future<void> startLevelCal({
    required int targetSystem,
    required int targetComponent,
  }) async {
    _startSimpleCal(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      type: CalibrationType.level,
      command: 241,
      param5: 2, // level cal (simple accel)
      startMessage: 'Starting level calibration.\nPlace vehicle on a flat surface.',
    );
  }

  Future<void> _startSimpleCal({
    required int targetSystem,
    required int targetComponent,
    required CalibrationType type,
    required int command,
    double param1 = 0,
    double param2 = 0,
    double param5 = 0,
    required String startMessage,
  }) async {
    _current = CalibrationProgress(
      state: CalibrationState.running,
      type: type,
      message: startMessage,
    );
    _progressController.add(_current);

    _sub?.cancel();
    _sub = _mavlink.messagesOf<StatusTextMessage>().listen((msg) {
      final text = msg.text;
      final isComplete = text.contains('calibration successful') ||
          text.contains('calibration done') ||
          text.contains('Calibration successful') ||
          text.contains('level done');
      final isFailed = text.contains('calibration failed') ||
          text.contains('FAILED') ||
          text.contains('Cal Failed');

      if (isComplete) {
        _current = CalibrationProgress(
          state: CalibrationState.success,
          type: type,
          completionPct: 100,
          message: text,
        );
        _progressController.add(_current);
        _sub?.cancel();
        _sub = null;
      } else if (isFailed) {
        _current = CalibrationProgress(
          state: CalibrationState.failed,
          type: type,
          message: text,
        );
        _progressController.add(_current);
        _sub?.cancel();
        _sub = null;
      } else if (text.contains('Cal') || text.contains('Place') || text.contains('accel') || text.contains('gyro')) {
        _current = CalibrationProgress(
          state: CalibrationState.running,
          type: type,
          message: text,
        );
        _progressController.add(_current);
      }
    });

    await _mavlink.sendCommand(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      command: command,
      param1: param1,
      param2: param2,
      param5: param5,
    );
  }

  /// Cancel any running calibration.
  Future<void> cancel({
    required int targetSystem,
    required int targetComponent,
  }) async {
    _sub?.cancel();
    _sub = null;
    // Send cancel: all params 0
    await _mavlink.sendCommand(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      command: 241,
    );
    _current = const CalibrationProgress(message: 'Calibration cancelled.');
    _progressController.add(_current);
  }

  void dispose() {
    _sub?.cancel();
    _progressController.close();
  }
}
