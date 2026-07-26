import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Flutter-side service that communicates with the HarmonyOS LiveViewHelper
/// via MethodChannel to display/update a LiveView (实况窗) during tool execution.
class LiveViewService {
  static const MethodChannel _channel = MethodChannel('com.anywhere.app/live_view');

  LiveViewService._(); // static only

  /// Update the live view with current tool progress.
  /// [progress] is 0.0–1.0, [statusText] describes the current step,
  /// [title] is the tool or session name.
  static Future<bool> updateProgress({
    required double progress,
    required String statusText,
    required String title,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>('updateLiveView', {
        'progress': progress.clamp(0.0, 1.0),
        'statusText': statusText,
        'title': title,
      });
      return result?['success'] == true;
    } on MissingPluginException {
      // MethodChannel not registered — non-OHOS platforms / test host
      return false;
    } catch (e) {
      debugPrint('[LiveViewService] updateProgress error: $e');
      return false;
    }
  }

  /// Remove the live view from the notification bar.
  static Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod<Map>('stopLiveView');
      return result?['success'] == true;
    } on MissingPluginException {
      return false;
    } catch (e) {
      debugPrint('[LiveViewService] stop error: $e');
      return false;
    }
  }
}
