import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connection_state.dart';
import '../models/vehicle_state.dart';
import '../providers/providers.dart';
import '../providers/connection_settings_provider.dart';
import '../theme/helios_colors.dart';

/// Slim bar at the top of the content area showing FC connection status
/// with a quick connect/disconnect action.
class QuickConnectionBar extends ConsumerWidget {
  const QuickConnectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final connection = ref.watch(connectionStatusProvider);
    final savedConfig = ref.watch(connectionSettingsProvider);

    final linkState = connection.linkState;
    final transportState = connection.transportState;
    final activeConfig = connection.activeConfig;

    final (statusColor, statusLabel, statusIcon) = switch (transportState) {
      TransportState.connected => linkState == LinkState.degraded
          ? (hc.warning, 'Link Degraded', Icons.signal_cellular_alt_1_bar)
          : (hc.success, 'FC Connected', Icons.link),
      TransportState.connecting =>
        (hc.warning, 'Connecting…', Icons.sync),
      TransportState.error =>
        (hc.danger, 'Connection Error', Icons.link_off),
      TransportState.disconnected =>
        (hc.textTertiary, 'Disconnected', Icons.link_off),
    };

    final configLabel = _configLabel(activeConfig ?? savedConfig);

    final isConnected = transportState == TransportState.connected;
    final isConnecting = transportState == TransportState.connecting;
    final canReconnect = !isConnected && !isConnecting && savedConfig != null;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: hc.surfaceDim,
        border: Border(
          bottom: BorderSide(color: hc.border, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Status dot + icon
          _StatusDot(color: statusColor, pulsing: isConnecting),
          const SizedBox(width: 6),
          Icon(statusIcon, size: 13, color: statusColor),
          const SizedBox(width: 5),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
          // Config label
          if (configLabel.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              width: 1,
              height: 14,
              color: hc.border,
            ),
            const SizedBox(width: 8),
            Text(
              configLabel,
              style: TextStyle(
                fontSize: 11,
                color: hc.textTertiary,
                fontFamily: 'monospace',
              ),
            ),
          ],
          const Spacer(),
          // Action button
          if (isConnected)
            _QuickBarButton(
              label: 'Disconnect',
              icon: Icons.power_settings_new,
              color: hc.danger,
              onTap: () => ref
                  .read(connectionControllerProvider.notifier)
                  .disconnect(),
            )
          else if (canReconnect)
            _QuickBarButton(
              label: 'Connect',
              icon: Icons.power_settings_new,
              color: hc.success,
              onTap: () => ref
                  .read(connectionControllerProvider.notifier)
                  .connect(savedConfig),
            )
          else if (isConnecting)
            _QuickBarButton(
              label: 'Cancel',
              icon: Icons.close,
              color: hc.textSecondary,
              onTap: () => ref
                  .read(connectionControllerProvider.notifier)
                  .disconnect(),
            ),
        ],
      ),
    );
  }

  String _configLabel(ConnectionConfig? config) {
    if (config == null) return '';
    return switch (config) {
      UdpConnectionConfig(:final bindAddress, :final port) =>
        'UDP $bindAddress:$port',
      TcpConnectionConfig(:final host, :final port) =>
        'TCP $host:$port',
      SerialConnectionConfig(:final portName, :final baudRate) =>
        '$portName @ ${baudRate ~/ 1000}k',
      WebSocketConnectionConfig(:final host, :final port) =>
        'WS $host:$port',
    };
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _opacity = Tween<double>(begin: 1.0, end: 0.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _QuickBarButton extends StatelessWidget {
  const _QuickBarButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
