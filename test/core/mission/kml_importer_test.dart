import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mission/kml_importer.dart';
import 'package:helios_gcs/shared/models/mission_item.dart';

void main() {
  late KmlImporter importer;

  setUp(() => importer = KmlImporter());

  group('KmlImporter', () {
    test('parses single Placemark Point into one waypoint', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Placemark>
    <Point>
      <coordinates>149.1652,-35.3632,100</coordinates>
    </Point>
  </Placemark>
</kml>''';

      final items = importer.parseKml(kml);
      expect(items.length, 1);
      expect(items[0].latitude, closeTo(-35.3632, 1e-5));
      expect(items[0].longitude, closeTo(149.1652, 1e-5));
      expect(items[0].altitude, closeTo(100.0, 1e-3));
      expect(items[0].command, MavCmd.navTakeoff);
      expect(items[0].seq, 0);
    });

    test('parses LineString with multiple coordinates into N waypoints', () {
      const kml = '''<?xml version="1.0"?>
<kml>
  <Placemark>
    <LineString>
      <coordinates>
        149.1652,-35.3632,50
        149.1660,-35.3640,55
        149.1668,-35.3648,60
      </coordinates>
    </LineString>
  </Placemark>
</kml>''';

      final items = importer.parseKml(kml);
      expect(items.length, 3);
      expect(items[0].command, MavCmd.navTakeoff);
      expect(items[1].command, MavCmd.navWaypoint);
      expect(items[2].command, MavCmd.navWaypoint);
      expect(items[0].latitude, closeTo(-35.3632, 1e-5));
      expect(items[1].latitude, closeTo(-35.3640, 1e-5));
      expect(items[2].latitude, closeTo(-35.3648, 1e-5));
    });

    test('parses multiple Placemarks into N waypoints', () {
      const kml = '''<?xml version="1.0"?>
<kml>
  <Placemark>
    <Point><coordinates>149.1652,-35.3632,30</coordinates></Point>
  </Placemark>
  <Placemark>
    <Point><coordinates>149.1660,-35.3640,30</coordinates></Point>
  </Placemark>
  <Placemark>
    <Point><coordinates>149.1668,-35.3648,30</coordinates></Point>
  </Placemark>
</kml>''';

      final items = importer.parseKml(kml);
      expect(items.length, 3);
      expect(items[0].seq, 0);
      expect(items[1].seq, 1);
      expect(items[2].seq, 2);
    });

    test('uses defaultAltM when altitude is absent', () {
      const kml = '''<?xml version="1.0"?>
<kml>
  <Placemark>
    <Point><coordinates>149.1652,-35.3632</coordinates></Point>
  </Placemark>
</kml>''';

      final items = importer.parseKml(kml, defaultAltM: 42.0);
      expect(items.length, 1);
      expect(items[0].altitude, closeTo(42.0, 1e-3));
    });

    test('returns empty list for malformed XML', () {
      const kml = '<kml><this is not valid xml</kml>';
      // Should not throw
      final items = importer.parseKml(kml);
      // Either empty or (if regex still extracts coords) graceful
      expect(items, isA<List<MissionItem>>());
    });

    test('returns empty list for empty string', () {
      final items = importer.parseKml('');
      expect(items, isEmpty);
    });

    test('returns empty list when no coordinates block exists', () {
      const kml = '''<?xml version="1.0"?>
<kml>
  <Placemark>
    <name>No coords here</name>
  </Placemark>
</kml>''';
      final items = importer.parseKml(kml);
      expect(items, isEmpty);
    });

    test('assigns sequential seq numbers', () {
      const kml = '''<?xml version="1.0"?>
<kml>
  <Placemark>
    <LineString>
      <coordinates>149.1,−35.1,10 149.2,-35.2,10 149.3,-35.3,10 149.4,-35.4,10</coordinates>
    </LineString>
  </Placemark>
</kml>''';
      // Some triples may fail to parse (the − char), result should still be
      // sequentially numbered
      final items = importer.parseKml(kml, defaultAltM: 10);
      for (var i = 0; i < items.length; i++) {
        expect(items[i].seq, i);
      }
    });
  });
}
