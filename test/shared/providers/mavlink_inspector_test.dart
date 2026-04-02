import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/providers/providers.dart';

MavlinkPacketEntry _entry({int msgId = 1, String msgName = 'TEST'}) {
  return MavlinkPacketEntry(
    msgId: msgId,
    msgName: msgName,
    systemId: 1,
    componentId: 1,
    timestamp: DateTime.now(),
    payloadLength: 10,
  );
}

void main() {
  late MavlinkInspectorNotifier notifier;

  setUp(() {
    notifier = MavlinkInspectorNotifier();
  });

  tearDown(() {
    notifier.dispose();
  });

  group('MavlinkInspectorNotifier', () {
    test('initial state is empty', () {
      expect(notifier.state, isEmpty);
    });

    test('new entries are appended — newest last', () {
      final first = _entry(msgId: 1, msgName: 'FIRST');
      final second = _entry(msgId: 2, msgName: 'SECOND');

      notifier.addPacket(first);
      notifier.addPacket(second);
      notifier.flushForTest();

      expect(notifier.state.length, 2);
      expect(notifier.state[0].msgName, 'FIRST');
      expect(notifier.state[1].msgName, 'SECOND');
    });

    test('buffer caps at 10000 entries — adding 10001 keeps only 10000', () {
      for (var i = 0; i < 10001; i++) {
        notifier.addPacket(_entry(msgId: i));
      }
      notifier.flushForTest();

      expect(notifier.state.length, 10000);
      // The most recently added entry (msgId 10000) should be last.
      expect(notifier.state.last.msgId, 10000);
      // The entry with msgId 0 (the oldest) should have been dropped.
      expect(notifier.state.any((e) => e.msgId == 0), isFalse);
    });

    test('adding exactly 10000 entries keeps all of them', () {
      for (var i = 0; i < 10000; i++) {
        notifier.addPacket(_entry(msgId: i));
      }
      notifier.flushForTest();

      expect(notifier.state.length, 10000);
    });

    test('clear() empties the state', () {
      notifier.addPacket(_entry());
      notifier.addPacket(_entry());
      notifier.flushForTest();
      expect(notifier.state.length, 2);

      notifier.clear();

      expect(notifier.state, isEmpty);
    });

    test('isPaused is false by default', () {
      expect(notifier.isPaused, isFalse);
    });

    test('pause() sets isPaused to true', () {
      notifier.pause();
      expect(notifier.isPaused, isTrue);
    });

    test('resume() sets isPaused to false', () {
      notifier.pause();
      notifier.resume();
      expect(notifier.isPaused, isFalse);
    });

    test('when paused, addPacket is a no-op', () {
      notifier.pause();
      notifier.addPacket(_entry(msgId: 99, msgName: 'SHOULD_NOT_APPEAR'));
      notifier.flushForTest();

      expect(notifier.state, isEmpty);
    });

    test('when paused, existing entries are not modified', () {
      notifier.addPacket(_entry(msgId: 1, msgName: 'EXISTING'));
      notifier.flushForTest();
      notifier.pause();
      notifier.addPacket(_entry(msgId: 2, msgName: 'IGNORED'));
      notifier.flushForTest();

      expect(notifier.state.length, 1);
      expect(notifier.state.first.msgName, 'EXISTING');
    });

    test('after resume(), addPacket works again', () {
      notifier.pause();
      notifier.addPacket(_entry(msgId: 1, msgName: 'WHILE_PAUSED'));
      notifier.resume();
      notifier.addPacket(_entry(msgId: 2, msgName: 'AFTER_RESUME'));
      notifier.flushForTest();

      expect(notifier.state.length, 1);
      expect(notifier.state.first.msgName, 'AFTER_RESUME');
    });

    test('isPaused reflects current state through multiple transitions', () {
      expect(notifier.isPaused, isFalse);
      notifier.pause();
      expect(notifier.isPaused, isTrue);
      notifier.resume();
      expect(notifier.isPaused, isFalse);
      notifier.pause();
      expect(notifier.isPaused, isTrue);
    });
  });
}
