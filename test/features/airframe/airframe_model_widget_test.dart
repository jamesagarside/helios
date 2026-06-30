import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/airframe/airframe_config.dart';
import 'package:helios_gcs/core/airframe/attitude_sample.dart';
import 'package:helios_gcs/core/airframe/attitude_source.dart';
import 'package:helios_gcs/features/airframe/airframe_model_widget.dart';
import 'package:vector_math/vector_math_64.dart';

/// A test double for [AttitudeSource] that lets the test push samples without
/// a live MAVLink link.
class FakeAttitudeSource extends ChangeNotifier implements AttitudeSource {
  AttitudeSample? _latest;
  bool _usingQuaternion = true;

  @override
  AttitudeSample? get latest => _latest;

  @override
  bool get hasAttitude => _latest != null;

  @override
  bool get usingQuaternion => _usingQuaternion;

  void push(Quaternion q) {
    _latest = AttitudeSample(quaternion: q..normalized(), timestamp: DateTime.now());
    notifyListeners();
  }

  @override
  void noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const config = AirframeConfig(
    archetype: AirframeArchetype.multirotor,
    motorCount: 4,
    armLayout: ArmLayout.x,
    fromParams: true,
  );

  testWidgets('shows empty state when no attitude is available', (tester) async {
    final source = FakeAttitudeSource();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AirframeModelWidget(source: source, config: config),
      ),
    ));
    expect(find.text('Waiting for attitude…'), findsOneWidget);
  });

  testWidgets('renders the model once an attitude arrives', (tester) async {
    final source = FakeAttitudeSource();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AirframeModelWidget(source: source, config: config),
      ),
    ));
    source.push(Quaternion.identity());
    await tester.pump();
    expect(find.text('Waiting for attitude…'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('reports Orientation match when within tolerance', (tester) async {
    final source = FakeAttitudeSource();
    final matches = <bool>[];
    final target = Quaternion.axisAngle(Vector3(1, 0, 0), 0.0)..normalize();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AirframeModelWidget(
          source: source,
          config: config,
          targetPose: target,
          toleranceRadians: 0.1,
          onMatchChanged: matches.add,
        ),
      ),
    ));

    // Far from target — no match.
    source.push(Quaternion.axisAngle(Vector3(1, 0, 0), 1.0)..normalize());
    await tester.pump();
    // Pump a few frames so the Ticker slerp runs.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(matches.contains(true), isFalse,
        reason: 'Should not match while far from target.');

    // Move to the target — should converge and report a match.
    source.push(target.clone());
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(matches.last, isTrue,
        reason: 'Should report Orientation match at the target pose.');
  });
}
