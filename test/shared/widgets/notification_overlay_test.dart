import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helios_gcs/shared/widgets/notification_overlay.dart';

void main() {
  group('NotificationNotifier', () {
    late NotificationNotifier notifier;
    setUp(() => notifier = NotificationNotifier());
    tearDown(() => notifier.dispose());

    test('starts empty', () => expect(notifier.state, isEmpty));

    test('adds a notification', () {
      notifier.add('Hello', NotificationSeverity.info);
      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.message, 'Hello');
    });

    test('respects max visible limit of 3', () {
      for (final s in [NotificationSeverity.info, NotificationSeverity.success, NotificationSeverity.warning, NotificationSeverity.error]) {
        notifier.add(s.name, s);
      }
      expect(notifier.state, hasLength(3));
    });

    test('dismissing promotes queued entry', () {
      for (final s in [NotificationSeverity.info, NotificationSeverity.success, NotificationSeverity.warning, NotificationSeverity.error]) {
        notifier.add(s.name, s);
      }
      notifier.dismiss(notifier.state.first.id);
      expect(notifier.state, hasLength(3));
      expect(notifier.state.last.message, 'error');
    });

    test('default duration is 5 seconds', () {
      notifier.add('Default', NotificationSeverity.info);
      expect(notifier.state.first.duration, const Duration(seconds: 5));
    });
  });

  group('notificationProvider', () {
    test('is accessible from a ProviderContainer', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(notificationProvider), isEmpty);
      container.read(notificationProvider.notifier).add('Test', NotificationSeverity.success);
      expect(container.read(notificationProvider), hasLength(1));
    });
  });
}
