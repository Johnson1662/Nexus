import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter-side service that communicates with the HarmonyOS NotificationHelper
/// via MethodChannel to show permission request notifications.
class NotificationService {
  static const MethodChannel _channel = MethodChannel('com.anywhere.app/notification');

  NotificationService._(); // static only

  /// Show a permission notification with [允许] and [拒绝] action buttons.
  /// Returns true if the notification was published successfully.
  static Future<bool> showPermissionNotification({
    required String requestId,
    required String toolName,
    required String command,
    String path = '',
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('showPermissionNotification', {
        'requestId': requestId,
        'toolName': toolName,
        'command': command,
        'path': path,
      });
      return result?['success'] == true;
    } on MissingPluginException {
      // Non-OHOS platform or test host
      return false;
    } catch (e) {
      debugPrint('[NotificationService] showPermissionNotification error: $e');
      return false;
    }
  }

  /// Cancel the notification with [id] (default 1001).
  static Future<bool> cancel({int id = 1001}) async {
    try {
      final result = await _channel.invokeMethod<Map>('cancelNotification', {
        'id': id,
      });
      return result?['success'] == true;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('[NotificationService] cancel error: $e');
      return false;
    }
  }
}
