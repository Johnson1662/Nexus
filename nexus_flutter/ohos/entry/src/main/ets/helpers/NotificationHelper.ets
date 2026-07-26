import { MethodChannel, MethodCall, MethodResult, FlutterEngine } from '@ohos/flutter_ohos';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'NotificationHelper';
const CHANNEL_NAME = 'com.anywhere.app/notification';

interface NotificationBasicContent {
  title: string;
  text: string;
}

interface NotificationContentDetails {
  notificationContentType: notificationManager.ContentType;
  normal: NotificationBasicContent;
}

interface NotificationRequestConfig {
  id: number;
  content: NotificationContentDetails;
}

export class NotificationHelper {
  private channel: MethodChannel;

  constructor(flutterEngine: FlutterEngine) {
    this.channel = new MethodChannel(flutterEngine.dartExecutor.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'showPermissionNotification') {
          this.showPermissionNotification(call, result);
        } else if (call.method === 'cancelNotification') {
          this.cancelNotification(call, result);
        } else {
          result.notImplemented();
        }
      }
    });
  }

  private async showPermissionNotification(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Record<string, Object>;
      const toolName = (args['toolName'] as string) ?? 'Tool';
      const command = (args['command'] as string) ?? '';

      const basicText: NotificationBasicContent = {
        title: `Nexus 权限请求: ${toolName}`,
        text: command.length > 150 ? command.substring(0, 150) + '...' : command
      };

      const contentDetails: NotificationContentDetails = {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: basicText
      };

      const reqConfig: NotificationRequestConfig = {
        id: 1001,
        content: contentDetails
      };

      await notificationManager.publish(reqConfig as Object as notificationManager.NotificationRequest);
      result.success(true);
    } catch (e) {
      console.error(TAG, `showPermissionNotification failed: ${(e as BusinessError).message}`);
      result.success(false);
    }
  }

  private async cancelNotification(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      await notificationManager.cancel(1001);
      result.success(true);
    } catch (e) {
      console.error(TAG, `cancelNotification failed: ${(e as BusinessError).message}`);
      result.success(false);
    }
  }
}
