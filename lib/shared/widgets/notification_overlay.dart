import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/helios_colors.dart';
import '../theme/helios_typography.dart';

/// Severity levels for toast notifications.
enum NotificationSeverity { info, success, warning, error }

/// A single notification entry.
class NotificationEntry {
  NotificationEntry({
    required this.message,
    required this.severity,
    Duration? duration,
  })  : id = _nextId++,
        createdAt = DateTime.now(),
        duration = duration ?? const Duration(seconds: 5);

  static int _nextId = 0;

  final int id;
  final String message;
  final NotificationSeverity severity;
  final DateTime createdAt;
  final Duration duration;
}

/// Manages the notification queue and visible toast stack.
class NotificationNotifier extends StateNotifier<List<NotificationEntry>> {
  NotificationNotifier() : super(const []);

  static const _maxVisible = 3;
  final Queue<NotificationEntry> _queue = Queue();
  final Map<int, Timer> _timers = {};

  void add(String message, NotificationSeverity severity,
      {Duration? duration}) {
    final entry = NotificationEntry(
      message: message,
      severity: severity,
      duration: duration,
    );

    if (state.length >= _maxVisible) {
      _queue.add(entry);
    } else {
      _show(entry);
    }
  }

  void _show(NotificationEntry entry) {
    state = [...state, entry];
    _timers[entry.id] = Timer(entry.duration, () => dismiss(entry.id));
  }

  void dismiss(int id) {
    _timers[id]?.cancel();
    _timers.remove(id);
    state = state.where((e) => e.id != id).toList();

    // Promote queued entries.
    if (_queue.isNotEmpty && state.length < _maxVisible) {
      _show(_queue.removeFirst());
    }
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// Global notification provider.
final notificationProvider =
    StateNotifierProvider<NotificationNotifier, List<NotificationEntry>>(
  (ref) => NotificationNotifier(),
);

// ─── Widget ──────────────────────────────────────────────────────────────────

/// Overlay that renders toast notifications at the top-right of the screen.
///
/// Wrap the app body with this widget:
/// ```dart
/// Stack(children: [child, const NotificationOverlay()])
/// ```
class NotificationOverlay extends ConsumerWidget {
  const NotificationOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(notificationProvider);
    if (entries.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 8,
      right: 8,
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries
            .map((e) => _ToastCard(
                  key: ValueKey(e.id),
                  entry: e,
                  onDismiss: () =>
                      ref.read(notificationProvider.notifier).dismiss(e.id),
                ))
            .toList(),
      ),
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    super.key,
    required this.entry,
    required this.onDismiss,
  });

  final NotificationEntry entry;
  final VoidCallback onDismiss;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final (icon, color) = _severityStyle(widget.entry.severity, hc);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onDismiss,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: hc.surfaceDim.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.entry.message,
                        style: HeliosTypography.caption.copyWith(
                          color: hc.textPrimary,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.close, size: 12, color: hc.textTertiary),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (IconData, Color) _severityStyle(
      NotificationSeverity severity, HeliosColors hc) {
    return switch (severity) {
      NotificationSeverity.info => (Icons.info_outline, hc.accent),
      NotificationSeverity.success => (Icons.check_circle_outline, hc.success),
      NotificationSeverity.warning => (Icons.warning_amber, hc.warning),
      NotificationSeverity.error => (Icons.error_outline, hc.danger),
    };
  }
}
