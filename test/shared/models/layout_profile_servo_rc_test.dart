import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/layout_profile.dart';

void main() {
  group('LayoutProfile — servo and RC panel fields', () {
    test('showServoPanel defaults to false', () {
      const profile = LayoutProfile(name: 'Test');
      expect(profile.showServoPanel, isFalse);
    });

    test('showRcPanel defaults to false', () {
      const profile = LayoutProfile(name: 'Test');
      expect(profile.showRcPanel, isFalse);
    });

    test('copyWith toggles showServoPanel to true', () {
      const profile = LayoutProfile(name: 'Test');
      final updated = profile.copyWith(showServoPanel: true);

      expect(updated.showServoPanel, isTrue);
      expect(updated.showRcPanel, isFalse); // unchanged
    });

    test('copyWith toggles showRcPanel to true', () {
      const profile = LayoutProfile(name: 'Test');
      final updated = profile.copyWith(showRcPanel: true);

      expect(updated.showRcPanel, isTrue);
      expect(updated.showServoPanel, isFalse); // unchanged
    });

    test('copyWith preserves other fields when toggling showServoPanel', () {
      const profile = LayoutProfile(
        name: 'Test',
        showActionPanel: true,
        showMessageLog: true,
      );
      final updated = profile.copyWith(showServoPanel: true);

      expect(updated.showServoPanel, isTrue);
      expect(updated.showActionPanel, isTrue);
      expect(updated.showMessageLog, isTrue);
      expect(updated.name, 'Test');
    });

    test('round-trip JSON preserves showServoPanel=true', () {
      const profile = LayoutProfile(name: 'Test', showServoPanel: true);
      final json = profile.toJson();
      final decoded = LayoutProfile.fromJson(json);

      expect(decoded.showServoPanel, isTrue);
      expect(decoded.showRcPanel, isFalse);
    });

    test('round-trip JSON preserves showRcPanel=true', () {
      const profile = LayoutProfile(name: 'Test', showRcPanel: true);
      final json = profile.toJson();
      final decoded = LayoutProfile.fromJson(json);

      expect(decoded.showRcPanel, isTrue);
      expect(decoded.showServoPanel, isFalse);
    });

    test('round-trip JSON preserves both panel flags true', () {
      const profile = LayoutProfile(
        name: 'Diagnostic',
        showServoPanel: true,
        showRcPanel: true,
      );
      final json = profile.toJson();
      final decoded = LayoutProfile.fromJson(json);

      expect(decoded.showServoPanel, isTrue);
      expect(decoded.showRcPanel, isTrue);
    });

    test('fromJson defaults to false when panel fields are absent (old profiles)', () {
      final json = <String, dynamic>{
        'name': 'Legacy',
        'vehicleType': 'multirotor',
        'charts': <String, dynamic>{},
        'isDefault': false,
        'showMessageLog': false,
        'showActionPanel': true,
        // showServoPanel and showRcPanel intentionally absent
      };
      final profile = LayoutProfile.fromJson(json);

      expect(profile.showServoPanel, isFalse);
      expect(profile.showRcPanel, isFalse);
    });

    test('toJson includes showServoPanel and showRcPanel keys', () {
      const profile = LayoutProfile(
        name: 'Test',
        showServoPanel: true,
        showRcPanel: false,
      );
      final json = profile.toJson();

      expect(json.containsKey('showServoPanel'), isTrue);
      expect(json.containsKey('showRcPanel'), isTrue);
      expect(json['showServoPanel'], isTrue);
      expect(json['showRcPanel'], isFalse);
    });
  });
}
