import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Whether the helios-relay is reachable at the given address.
enum RelayStatus { unknown, checking, available, unavailable }

class RelayStatusNotifier extends StateNotifier<RelayStatus> {
  RelayStatusNotifier() : super(RelayStatus.unknown);

  Timer? _pollTimer;

  /// Probe the relay and update status.
  Future<void> check({String host = 'localhost', int port = 8765}) async {
    state = RelayStatus.checking;
    try {
      final uri = Uri.parse('ws://$host:$port');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 2));
      await channel.sink.close();
      state = RelayStatus.available;
    } catch (_) {
      state = RelayStatus.unavailable;
    }
  }

  /// Start periodic checking (every 5 seconds).
  void startPolling({String host = 'localhost', int port = 8765}) {
    stopPolling();
    check(host: host, port: port);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => check(host: host, port: port),
    );
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}

final relayStatusProvider =
    StateNotifierProvider<RelayStatusNotifier, RelayStatus>(
  (ref) => RelayStatusNotifier(),
);
