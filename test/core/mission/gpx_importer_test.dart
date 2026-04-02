import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mission/gpx_importer.dart';
import 'package:helios_gcs/shared/models/mission_item.dart';

void main() {
  late GpxImporter importer;

  setUp(() => importer = GpxImporter());

  group('GpxImporter', () {
    test('parses <wpt> elements into waypoints', () {
      const gpx = '''<?xml version="1.0"?>
<gpx version="1.1">
  <wpt lat="-35.3632" lon="149.1652">
    <ele>100</ele>
    <name>Home</name>
  </wpt>
  <wpt lat="-35.3640" lon="149.1660">
    <ele>80</ele>
  </wpt>
</gpx>''';

      final items = importer.parseGpx(gpx);
      expect(items.length, 2);
      expect(items[0].latitude, closeTo(-35.3632, 1e-5));
      expect(items[0].longitude, closeTo(149.1652, 1e-5));
      expect(items[0].altitude, closeTo(100.0, 1e-3));
      expect(items[0].command, MavCmd.navTakeoff);
      expect(items[0].seq, 0);
      expect(items[1].command, MavCmd.navWaypoint);
      expect(items[1].seq, 1);
    });

    test('parses <trkpt> inside <trkseg> into waypoints', () {
      const gpx = '''<?xml version="1.0"?>
<gpx version="1.1">
  <trk>
    <trkseg>
      <trkpt lat="-35.3632" lon="149.1652">
        <ele>50</ele>
      </trkpt>
      <trkpt lat="-35.3640" lon="149.1660">
        <ele>55</ele>
      </trkpt>
      <trkpt lat="-35.3648" lon="149.1668">
        <ele>60</ele>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      final items = importer.parseGpx(gpx);
      expect(items.length, 3);
      expect(items[0].command, MavCmd.navTakeoff);
      expect(items[1].altitude, closeTo(55.0, 1e-3));
      expect(items[2].altitude, closeTo(60.0, 1e-3));
    });

    test('reads <ele> for altitude correctly', () {
      const gpx = '''<?xml version="1.0"?>
<gpx>
  <wpt lat="-35.0" lon="149.0">
    <ele>123.5</ele>
  </wpt>
</gpx>''';

      final items = importer.parseGpx(gpx);
      expect(items.length, 1);
      expect(items[0].altitude, closeTo(123.5, 1e-3));
    });

    test('uses defaultAltM when <ele> is absent', () {
      const gpx = '''<?xml version="1.0"?>
<gpx>
  <wpt lat="-35.0" lon="149.0"></wpt>
</gpx>''';

      final items = importer.parseGpx(gpx, defaultAltM: 75.0);
      expect(items.length, 1);
      expect(items[0].altitude, closeTo(75.0, 1e-3));
    });

    test('parses both <wpt> and <trkpt> in same file', () {
      const gpx = '''<?xml version="1.0"?>
<gpx>
  <wpt lat="-35.1" lon="149.1">
    <ele>30</ele>
  </wpt>
  <trk>
    <trkseg>
      <trkpt lat="-35.2" lon="149.2">
        <ele>40</ele>
      </trkpt>
      <trkpt lat="-35.3" lon="149.3">
        <ele>50</ele>
      </trkpt>
    </trkseg>
  </trk>
</gpx>''';

      final items = importer.parseGpx(gpx);
      expect(items.length, 3);
      expect(items[0].latitude, closeTo(-35.1, 1e-5));
      expect(items[1].latitude, closeTo(-35.2, 1e-5));
      expect(items[2].latitude, closeTo(-35.3, 1e-5));
    });

    test('parses <rtept> route points', () {
      const gpx = '''<?xml version="1.0"?>
<gpx>
  <rte>
    <rtept lat="-35.1" lon="149.1">
      <ele>30</ele>
    </rtept>
    <rtept lat="-35.2" lon="149.2">
      <ele>40</ele>
    </rtept>
  </rte>
</gpx>''';

      final items = importer.parseGpx(gpx);
      expect(items.length, 2);
      expect(items[0].command, MavCmd.navTakeoff);
      expect(items[1].command, MavCmd.navWaypoint);
    });

    test('returns empty list for malformed XML', () {
      const gpx = '<gpx><wpt lat="bad" lon="also bad"></gpx>';
      // No throw, gracefully returns empty or items without crashing
      final items = importer.parseGpx(gpx);
      expect(items, isA<List<MissionItem>>());
    });

    test('returns empty list for empty string', () {
      final items = importer.parseGpx('');
      expect(items, isEmpty);
    });

    test('assigns sequential seq numbers', () {
      const gpx = '''<?xml version="1.0"?>
<gpx>
  <trk><trkseg>
    <trkpt lat="-35.1" lon="149.1"><ele>10</ele></trkpt>
    <trkpt lat="-35.2" lon="149.2"><ele>20</ele></trkpt>
    <trkpt lat="-35.3" lon="149.3"><ele>30</ele></trkpt>
  </trkseg></trk>
</gpx>''';

      final items = importer.parseGpx(gpx);
      for (var i = 0; i < items.length; i++) {
        expect(items[i].seq, i);
      }
    });
  });
}
