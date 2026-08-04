import { MethodChannel, MethodCall, MethodResult, FlutterEngine } from '@ohos/flutter_ohos';
import { common, WantAgent, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'NotificationHelper';
const CHANNEL_NAME = 'com.nexus.remoteai/notification';
const SLOT_TYPE = notificationManager.SlotType.SERVICE_INFORMATION;

interface NotificationBasicContent {
  title: string;
  text: string;
}

interface NotificationContentDetails {
  notificationContentType: notificationManager.ContentType;
  normal: NotificationBasicContent;
}

interface NotificationRequestConfig extends notificationManager.NotificationRequest {
  id: number;
  content: NotificationContentDetails;
}

export class NotificationHelper {
  private channel: MethodChannel;
  private slotCreated: boolean = false;
  private disposed: boolean = false;
  private context: common.UIAbilityContext;

  constructor(flutterEngine: FlutterEngine, context: common.UIAbilityContext) {
    this.context = context;
    this.channel = new MethodChannel(flutterEngine.dartExecutor.getBinaryMessenger(), CHANNEL_NAME);
    // Keep one cold-start action until Flutter registers its handler.
    this.channel.resizeChannelBuffer(1);
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

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.channel.setMethodCallHandler(null);
    this.slotCreated = false;
  }

  private async ensureEnabled(): Promise<void> {
    if (!await notificationManager.isNotificationEnabled()) {
      await notificationManager.requestEnableNotification(this.context);
    }
  }

  private async ensureSlot(): Promise<void> {
    if (this.slotCreated) return;
    await notificationManager.addSlot(SLOT_TYPE);
    this.slotCreated = true;
  }

  private async showPermissionNotification(call: MethodCall, result: MethodResult): Promise<void> {
    if (this.disposed) {
      result.success(false);
      return;
    }
    try {
      await this.ensureEnabled();
      await this.ensureSlot();
      if (this.disposed) {
        result.success(false);
        return;
      }

      const args = call.args as Record<string, Object>;
      const toolName = (args['toolName'] as string) ?? 'Tool';
      const command = (args['command'] as string) ?? '';
      const requestId = (args['requestId'] as string) ?? '';

      const denyWantAgent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: 'com.nexus.remoteai',
          abilityName: 'EntryAbility',
          parameters: { nexus_action: 'permission_response', requestId: requestId, allow: false }
        }],
        actionType: wantAgent.OperationType.START_ABILITIES,
        requestCode: 200,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });

      const allowWantAgent = await wantAgent.getWantAgent({
        wants: [{
          bundleName: 'com.nexus.remoteai',
          abilityName: 'EntryAbility',
          parameters: { nexus_action: 'permission_response', requestId: requestId, allow: true }
        }],
        actionType: wantAgent.OperationType.START_ABILITIES,
        requestCode: 100,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });

      const basicText: NotificationBasicContent = {
        title: `Nexus 权限请求: ${toolName}`,
        text: command.length > 0 ? (command.length > 150 ? command.substring(0, 150) + '...' : command) : '远程Agent请求高危操作执行'
      };

      const contentDetails: NotificationContentDetails = {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: basicText
      };

      const reqConfig: NotificationRequestConfig = {
        id: 1001,
        content: contentDetails,
        actionButtons: [
          { title: '拒绝', wantAgent: denyWantAgent },
          { title: '允许', wantAgent: allowWantAgent }
        ]
      };

      if (this.disposed) {
        result.success(false);
        return;
      }
      await notificationManager.publish(reqConfig);
      result.success(true);
    } catch (e) {
      const error = e as BusinessError;
      console.error(TAG, `showPermissionNotification failed: ${error.code} ${error.message}`);
      result.success(false);
    }
  }

  public sendPermissionAction(requestId: string, allow: boolean): boolean {
    if (this.disposed) return false;
    try {
      this.channel.invokeMethod('onPermissionAction', { requestId, allow });
      return true;
    } catch (_) {
      return false;
    }
  }

  private async cancelNotification(call: MethodCall, result: MethodResult): Promise<void> {
    if (this.disposed) {
      result.success(false);
      return;
    }
    try {
      await notificationManager.cancel(1001);
      result.success(true);
    } catch (e) {
      console.error(TAG, `cancelNotification failed: ${(e as BusinessError).message}`);
      result.success(false);
    }
  }
}
