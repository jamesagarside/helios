import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mission/mission_validator.dart';
import 'package:helios_gcs/shared/models/mission_item.dart';

void main() {
  const validator = MissionValidator();

  MissionItem wp(
    int seq, {
    int command = MavCmd.navWaypoint,
    int frame = MavFrame.globalRelativeAlt,
    double lat = -35.0,
    double lon = 149.0,
    double alt = 50.0,
    double param1 = 0.0,
  }) =>
      MissionItem(
        seq: seq,
        command: command,
        frame: frame,
        latitude: lat,
        longitude: lon,
        altitude: alt,
        param1: param1,
      );

  test('empty mission reports an informational issue', () {
    final issues = validator.validate([]);
    expect(issues, hasLength(1));
    expect(issues.first.severity, MissionIssueSeverity.info);
  });

  test('clean mission has no errors or warnings', () {
    final issues = validator.validate([
      wp(0, command: MavCmd.navTakeoff, alt: 20),
      wp(1, lat: -35.0, lon: 149.0, alt: 50),
      wp(2, lat: -35.001, lon: 149.001, alt: 60),
    ]);
    expect(
      issues.where((i) => i.severity != MissionIssueSeverity.info),
      isEmpty,
    );
  });

  test('out-of-range DO_JUMP target is an error', () {
    final issues = validator.validate([
      wp(0),
      wp(1),
      wp(2, command: MavCmd.doJump, param1: 99),
    ]);
    final errors =
        issues.where((i) => i.severity == MissionIssueSeverity.error).toList();
    expect(errors, hasLength(1));
    expect(errors.first.seq, 2);
  });

  test('in-range DO_JUMP target is accepted', () {
    final issues = validator.validate([
      wp(0),
      wp(1),
      wp(2, command: MavCmd.doJump, param1: 1),
    ]);
    expect(
      issues.where((i) => i.severity == MissionIssueSeverity.error),
      isEmpty,
    );
  });

  test('non-positive relative altitude warns', () {
    final issues = validator.validate([
      wp(0, alt: 0),
    ]);
    expect(
      issues.any((i) =>
          i.severity == MissionIssueSeverity.warning && i.seq == 0),
      isTrue,
    );
  });

  test('LAND at zero altitude does not warn', () {
    final issues = validator.validate([
      wp(0, command: MavCmd.navLand, alt: 0),
    ]);
    expect(
      issues.where((i) => i.severity == MissionIssueSeverity.warning),
      isEmpty,
    );
  });

  test('duplicate consecutive waypoints warn', () {
    final issues = validator.validate([
      wp(0, lat: -35.0, lon: 149.0),
      wp(1, lat: -35.0, lon: 149.0),
    ]);
    expect(
      issues.any((i) =>
          i.severity == MissionIssueSeverity.warning && i.seq == 1),
      isTrue,
    );
  });

  test('terrain clearance warning for absolute waypoint below margin', () {
    final issues = validator.validate(
      [
        wp(0, frame: MavFrame.global, alt: 102),
      ],
      terrainElevationBySeq: {0: 100},
    );
    // 102 - 100 = 2 m AGL, below the 5 m default margin.
    expect(
      issues.any((i) => i.severity == MissionIssueSeverity.warning),
      isTrue,
    );
  });

  test('terrain clearance OK for absolute waypoint above margin', () {
    final issues = validator.validate(
      [
        wp(0, frame: MavFrame.global, alt: 150),
      ],
      terrainElevationBySeq: {0: 100},
    );
    expect(
      issues.where((i) => i.severity == MissionIssueSeverity.warning),
      isEmpty,
    );
  });

  test('issues are ordered errors before warnings before info', () {
    final issues = validator.validate([
      wp(0, alt: 0), // warning
      wp(1, command: MavCmd.doJump, param1: 50), // error
    ]);
    expect(issues.first.severity, MissionIssueSeverity.error);
  });
}
