import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';

/// Floating STATUSTEXT message log shown on the Fly View.
///
/// Auto-scrolls to the newest message. Tap to pause auto-scroll.
/// Shows severity via border and text colour: red=critical, amber=warning,
/// white=info.
class MessageLog extends ConsumerStatefulWidget {
  const MessageLog({super.key});

  @override
  ConsumerState<MessageLog> createState() => _MessageLogState();
}

class _MessageLogState extends ConsumerState<MessageLog> {
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll || !_scroll.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(alertHistoryProvider);
    final hc = context.hc;

    // Auto-scroll when new messages arrive
    if (alerts.isNotEmpty) _scrollToBottom();

    return Container(
      width: 280,
      height: 160,
      decoration: BoxDecoration(
        color: hc.surfaceDim.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: hc.border.withValues(alpha: 0.5)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.message_outlined, size: 11, color: hc.textTertiary),
                const SizedBox(width: 4),
                Text(
                  'MESSAGES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: hc.textTertiary,
                    letterSpacing: 1.0,
                  ),
                ),
                const Spacer(),
                if (!_autoScroll)
                  GestureDetector(
                    onTap: () {
                      setState(() => _autoScroll = true);
                      _scrollToBottom();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: hc.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '↓ resume',
                        style: TextStyle(
                            fontSize: 9, color: hc.accent),
                      ),
                    ),
                  ),
                if (alerts.isNotEmpty)
                  GestureDetector(
                    onTap: () =>
                        ref.read(alertHistoryProvider.notifier).clear(),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.clear_all,
                          size: 13, color: hc.textTertiary),
                    ),
                  ),
              ],
            ),
          ),
          // Message list
          Expanded(
            child: alerts.isEmpty
                ? Center(
                    child: Text(
                      'No messages',
                      style: TextStyle(
                          fontSize: 11, color: hc.textTertiary),
                    ),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is UserScrollNotification) {
                        setState(() => _autoScroll = false);
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      itemCount: alerts.length,
                      itemBuilder: (_, i) =>
                          _MessageRow(entry: alerts[i], hc: hc),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.entry, required this.hc});
  final AlertEntry entry;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.severity) {
      AlertSeverity.critical => hc.danger,
      AlertSeverity.warning => hc.warning,
      AlertSeverity.info => hc.textSecondary,
    };

    final hh = entry.timestamp.hour.toString().padLeft(2, '0');
    final mm = entry.timestamp.minute.toString().padLeft(2, '0');
    final ss = entry.timestamp.second.toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$hh:$mm:$ss',
            style: TextStyle(
              fontSize: 9,
              color: hc.textTertiary,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
