import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef OnPermissionActionCallback = void Function(String requestId, bool allow);

/// Flutter-side service that communicates with the HarmonyOS NotificationHelper
/// via MethodChannel to show permission request notifications.
class NotificationService {
  static const MethodChannel _channel = MethodChannel('com.nexus.remoteai/notification');

  NotificationService._(); // static only

  static OnPermissionActionCallback? onPermissionAction;
  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    // Set up handler for permission action responses from native side
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPermissionAction') {
        final args = call.arguments as Map<dynamic, dynamic>?;
        if (args != null) {
          final requestId = args['requestId'] as String? ?? '';
          final allow = args['allow'] as bool? ?? false;
          onPermissionAction?.call(requestId, allow);
        }
      }
    });
  }

  /// Show a permission notification with [允许] and [拒绝] action buttons.
  /// Returns true if the notification was published successfully.
  static Future<bool> showPermissionNotification({
    required String requestId,
    required String toolName,
    required String command,
    String path = '',
  }) async {
    await _init();
    try {
      final result = await _channel.invokeMethod<bool>('showPermissionNotification', {
        'requestId': requestId,
        'toolName': toolName,
        'command': command,
        'path': path,
      });
      return result == true;
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
    await _init();
    try {
      final result = await _channel.invokeMethod<bool>('cancelNotification', {
        'id': id,
      });
      return result == true;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('[NotificationService] cancel error: $e');
      return false;
    }
  }
}
