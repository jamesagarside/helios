import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/params/param_meta.dart';
import 'package:helios_gcs/core/params/param_meta_service.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  // ── ParamMeta model ─────────────────────────────────────────────────────────

  group('ParamMeta', () {
    test('fromJson / toJson round-trip — full fields', () {
      final original = ParamMeta(
        name: 'ARMING_CHECK',
        displayName: 'Arm Checks to Perform',
        description: 'Checks prior to arming motor',
        group: 'Arming',
        units: 'm/s',
        rangeMin: -10.0,
        rangeMax: 100.0,
        increment: 0.5,
        values: {0: 'Disabled', 1: 'Enabled'},
        bitmaskBits: {0: 'All', 1: 'Barometer'},
        userLevel: 'Standard',
      );

      final json = original.toJson();
      final restored = ParamMeta.fromJson(json);

      expect(restored.name, equals('ARMING_CHECK'));
      expect(restored.displayName, equals('Arm Checks to Perform'));
      expect(restored.description, equals('Checks prior to arming motor'));
      expect(restored.group, equals('Arming'));
      expect(restored.units, equals('m/s'));
      expect(restored.rangeMin, equals(-10.0));
      expect(restored.rangeMax, equals(100.0));
      expect(restored.increment, equals(0.5));
      expect(restored.values, equals({0: 'Disabled', 1: 'Enabled'}));
      expect(restored.bitmaskBits, equals({0: 'All', 1: 'Barometer'}));
      expect(restored.userLevel, equals('Standard'));
    });

    test('fromJson / toJson round-trip — minimal fields', () {
      final original = const ParamMeta(name: 'RC1_MIN');
      final restored = ParamMeta.fromJson(original.toJson());

      expect(restored.name, equals('RC1_MIN'));
      expect(restored.displayName, isEmpty);
      expect(restored.description, isEmpty);
      expect(restored.group, isEmpty);
      expect(restored.units, isEmpty);
      expect(restored.rangeMin, isNull);
      expect(restored.rangeMax, isNull);
      expect(restored.increment, isNull);
      expect(restored.values, isEmpty);
      expect(restored.bitmaskBits, isEmpty);
      expect(restored.userLevel, equals('Advanced'));
    });

    test('hasEnumValues is true when values non-empty', () {
      final meta = ParamMeta(
        name: 'FRAME_CLASS',
        values: {0: 'Undefined', 1: 'Quad'},
      );
      expect(meta.hasEnumValues, isTrue);
    });

    test('hasEnumValues is false when values empty', () {
      const meta = ParamMeta(name: 'RC1_MIN');
      expect(meta.hasEnumValues, isFalse);
    });

    test('isBitmask is true when bitmaskBits non-empty', () {
      final meta = ParamMeta(
        name: 'ARMING_CHECK',
        bitmaskBits: {0: 'All', 1: 'Barometer'},
      );
      expect(meta.isBitmask, isTrue);
    });

    test('isBitmask is false when bitmaskBits empty', () {
      const meta = ParamMeta(name: 'RC1_MIN');
      expect(meta.isBitmask, isFalse);
    });

    test('isStandard is true when userLevel equals Standard', () {
      const meta = ParamMeta(name: 'ARMING_CHECK', userLevel: 'Standard');
      expect(meta.isStandard, isTrue);
    });

    test('isStandard is false when userLevel is Advanced', () {
      const meta = ParamMeta(name: 'FRAME_CLASS', userLevel: 'Advanced');
      expect(meta.isStandard, isFalse);
    });

    test('isStandard is false for default userLevel', () {
      const meta = ParamMeta(name: 'RC1_MIN');
      expect(meta.isStandard, isFalse);
    });
  });

  // ── ParamMetaService.vehicleKey ─────────────────────────────────────────────

  group('ParamMetaService.vehicleKey', () {
    test('quadrotor maps to ArduCopter', () {
      expect(ParamMetaService.vehicleKey(VehicleType.quadrotor),
          equals('ArduCopter'));
    });

    test('helicopter maps to ArduCopter', () {
      expect(ParamMetaService.vehicleKey(VehicleType.helicopter),
          equals('ArduCopter'));
    });

    test('fixedWing maps to ArduPlane', () {
      expect(ParamMetaService.vehicleKey(VehicleType.fixedWing),
          equals('ArduPlane'));
    });

    test('vtol maps to ArduPlane', () {
      expect(
          ParamMetaService.vehicleKey(VehicleType.vtol), equals('ArduPlane'));
    });

    test('rover maps to APMrover2', () {
      expect(
          ParamMetaService.vehicleKey(VehicleType.rover), equals('APMrover2'));
    });

    test('boat maps to APMrover2', () {
      expect(
          ParamMetaService.vehicleKey(VehicleType.boat), equals('APMrover2'));
    });

    test('unknown maps to ArduCopter (default)', () {
      expect(ParamMetaService.vehicleKey(VehicleType.unknown),
          equals('ArduCopter'));
    });
  });

  // ── ParamMetaService.parseXml ───────────────────────────────────────────────

  group('ParamMetaService.parseXml', () {
    final service = ParamMetaService();

    // Minimal XML fragment with one param.
    const minimalXml = '''
<paramfile>
  <vehicles>
    <vehicle name="ArduCopter">
      <parameters>
        <param name="ACRO_BAL_PITCH"
               humanName="Acro Balance Pitch"
               documentation="rate at which pitch angle recovers in acro mode"
               user="Standard">
          <field name="Range">0 3</field>
          <field name="Increment">0.1</field>
          <field name="Units">s</field>
        </param>
      </parameters>
    </vehicle>
  </vehicles>
</paramfile>
''';

    test('parses param name', () {
      final meta = service.parseXml(minimalXml);
      expect(meta.containsKey('ACRO_BAL_PITCH'), isTrue);
    });

    test('parses humanName as displayName', () {
      final meta = service.parseXml(minimalXml);
      expect(meta['ACRO_BAL_PITCH']!.displayName, equals('Acro Balance Pitch'));
    });

    test('parses documentation as description', () {
      final meta = service.parseXml(minimalXml);
      expect(meta['ACRO_BAL_PITCH']!.description,
          equals('rate at which pitch angle recovers in acro mode'));
    });

    test('parses <field name="Units">', () {
      final meta = service.parseXml(minimalXml);
      expect(meta['ACRO_BAL_PITCH']!.units, equals('s'));
    });

    test('parses <field name="Range"> into rangeMin and rangeMax', () {
      final meta = service.parseXml(minimalXml);
      expect(meta['ACRO_BAL_PITCH']!.rangeMin, equals(0.0));
      expect(meta['ACRO_BAL_PITCH']!.rangeMax, equals(3.0));
    });

    test('parses <field name="Increment">', () {
      final meta = service.parseXml(minimalXml);
      expect(meta['ACRO_BAL_PITCH']!.increment, equals(0.1));
    });

    test('parses userLevel Standard', () {
      final meta = service.parseXml(minimalXml);
      expect(meta['ACRO_BAL_PITCH']!.userLevel, equals('Standard'));
      expect(meta['ACRO_BAL_PITCH']!.isStandard, isTrue);
    });

    test('parses <values> block into enum map', () {
      const xml = '''
<paramfile><vehicles><vehicle name="ArduCopter"><parameters>
  <param name="FRAME_CLASS"
         humanName="Frame Class"
         documentation="Controls major frame class"
         user="Standard">
    <values>
      <value code="0">Undefined</value>
      <value code="1">Quad</value>
      <value code="2">Hexa</value>
    </values>
  </param>
</parameters></vehicle></vehicles></paramfile>
''';
      final meta = service.parseXml(xml);
      final m = meta['FRAME_CLASS']!;
      expect(m.hasEnumValues, isTrue);
      expect(m.values[0], equals('Undefined'));
      expect(m.values[1], equals('Quad'));
      expect(m.values[2], equals('Hexa'));
    });

    test('parses <field name="Bitmask"> into bitmaskBits map', () {
      const xml = '''
<paramfile><vehicles><vehicle name="ArduCopter"><parameters>
  <param name="ARMING_CHECK"
         humanName="Arm Checks to Perform"
         documentation="Checks prior to arming motor"
         user="Standard">
    <field name="Bitmask">0:All,1:Barometer,2:Compass,3:GPS lock</field>
  </param>
</parameters></vehicle></vehicles></paramfile>
''';
      final meta = service.parseXml(xml);
      final m = meta['ARMING_CHECK']!;
      expect(m.isBitmask, isTrue);
      expect(m.bitmaskBits[0], equals('All'));
      expect(m.bitmaskBits[1], equals('Barometer'));
      expect(m.bitmaskBits[2], equals('Compass'));
      expect(m.bitmaskBits[3], equals('GPS lock'));
    });

    test('groups by humanName prefix before colon', () {
      const xml = '''
<paramfile><vehicles><vehicle name="ArduCopter"><parameters>
  <param name="ARMING_CHECK"
         humanName="Arming: Require GPS Config"
         documentation="doc"
         user="Standard">
    <field name="Range">0 1</field>
  </param>
</parameters></vehicle></vehicles></paramfile>
''';
      final meta = service.parseXml(xml);
      expect(meta['ARMING_CHECK']!.group, equals('Arming'));
    });

    test('groups by param name prefix when no colon in humanName', () {
      const xml = '''
<paramfile><vehicles><vehicle name="ArduCopter"><parameters>
  <param name="RC1_MIN"
         humanName="RC1 Min"
         documentation="doc"
         user="Advanced">
    <field name="Range">800 2200</field>
  </param>
</parameters></vehicle></vehicles></paramfile>
''';
      final meta = service.parseXml(xml);
      expect(meta['RC1_MIN']!.group, equals('RC1'));
    });

    test('returns empty map for empty XML', () {
      final meta = service.parseXml('');
      expect(meta, isEmpty);
    });

    test('returns empty map for whitespace-only XML', () {
      final meta = service.parseXml('   \n\t  ');
      expect(meta, isEmpty);
    });

    test('returns empty map for malformed XML without throwing', () {
      final meta = service.parseXml('<garbage not xml at all');
      expect(meta, isEmpty);
    });

    test('parses negative range values correctly', () {
      const xml = '''
<paramfile><vehicles><vehicle name="ArduCopter"><parameters>
  <param name="TEST_PARAM" humanName="Test" documentation="doc" user="Advanced">
    <field name="Range">-100 100</field>
  </param>
</parameters></vehicle></vehicles></paramfile>
''';
      final meta = service.parseXml(xml);
      expect(meta['TEST_PARAM']!.rangeMin, equals(-100.0));
      expect(meta['TEST_PARAM']!.rangeMax, equals(100.0));
    });

    test('parses multiple params in one document', () {
      const xml = '''
<paramfile><vehicles><vehicle name="ArduCopter"><parameters>
  <param name="PARAM_A" humanName="A" documentation="desc a" user="Standard">
    <field name="Range">0 1</field>
  </param>
  <param name="PARAM_B" humanName="B: Something" documentation="desc b" user="Advanced">
    <values>
      <value code="0">Off</value>
      <value code="1">On</value>
    </values>
  </param>
</parameters></vehicle></vehicles></paramfile>
''';
      final meta = service.parseXml(xml);
      expect(meta.length, equals(2));
      expect(meta.containsKey('PARAM_A'), isTrue);
      expect(meta.containsKey('PARAM_B'), isTrue);
      expect(meta['PARAM_B']!.group, equals('B'));
    });
  });
}
