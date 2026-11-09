import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paperless_mobile/api/models/status_enum.dart';
import 'package:paperless_mobile/api/models/tasks_view.dart';
import 'package:paperless_mobile/features/notifications/services/local_notification_service.dart';

class MockFlutterLocalNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  final List<NotificationDetails?> shownDetails = [];
  final List<int> shownIds = [];
  final List<int> cancelledIds = [];

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    shownIds.add(id);
    shownDetails.add(notificationDetails);
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelledIds.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFlutterLocalNotificationsPlugin mockPlugin;
  late LocalNotificationService service;

  setUp(() {
    mockPlugin = MockFlutterLocalNotificationsPlugin();
    service = LocalNotificationService(plugin: mockPlugin);
  });

  group('LocalNotificationService - Task Notification Lifecycle (#476)', () {
    test(
      'notifyTaskChanged configures autoCancel on task notification',
      () async {
        final task = TasksView(
          id: 476,
          taskId: 'task-uuid-476',
          status: StatusEnum.pending,
          taskFileName: 'test_doc.pdf',
        );

        await service.notifyTaskChanged(task, userId: 'user-1');

        expect(mockPlugin.shownDetails.length, 1);
        final details = mockPlugin.shownDetails.first?.android;
        expect(details?.autoCancel, isTrue);
      },
    );

    test(
      'cancelTaskNotification cancels the matching notification id',
      () async {
        await service.cancelTaskNotification(476);

        expect(mockPlugin.cancelledIds, contains(1476));
      },
    );
  });
}
