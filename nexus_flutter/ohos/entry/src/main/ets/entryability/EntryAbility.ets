
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { Want, AbilityConstant } from '@kit.AbilityKit';
import { LiveViewHelper } from '../helpers/LiveViewHelper';
import { NotificationHelper } from '../helpers/NotificationHelper';

interface PermissionAction {
  requestId: string;
  allow: boolean;
}

export default class EntryAbility extends FlutterAbility {
  private liveViewHelper?: LiveViewHelper;
  private notificationHelper?: NotificationHelper;
  private pendingPermissionAction?: PermissionAction;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // Parse before Flutter starts so a notification tap is retained while the
    // engine and its method channels are being created.
    this.handleWant(want);
    super.onCreate(want, launchParam);
    this.flushPendingPermissionAction();
  }

  configureFlutterEngine(flutterEngine: FlutterEngine): void {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);

    console.info('Nexus', 'configureFlutterEngine start');

    this.liveViewHelper?.dispose();
    this.notificationHelper?.dispose();

    try {
      this.liveViewHelper = new LiveViewHelper(flutterEngine);
      console.info('Nexus', 'LiveViewHelper registered OK');
    } catch (e) {
      console.error('Nexus', `LiveViewHelper failed: ${(e as Error).message}`);
    }

    try {
      this.notificationHelper = new NotificationHelper(flutterEngine, this.context);
      console.info('Nexus', 'NotificationHelper registered OK');
      this.flushPendingPermissionAction();
    } catch (e) {
      console.error('Nexus', `NotificationHelper failed: ${(e as Error).message}`);
    }
  }

  cleanUpFlutterEngine(flutterEngine: FlutterEngine): void {
    this.liveViewHelper?.dispose();
    this.notificationHelper?.dispose();
    this.liveViewHelper = undefined;
    this.notificationHelper = undefined;
    this.pendingPermissionAction = undefined;
    super.cleanUpFlutterEngine(flutterEngine);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    super.onNewWant(want, launchParam);
    this.handleWant(want);
  }

  private handleWant(want: Want): void {
    const params = want.parameters;
    if ((params?.['nexus_action'] as string | undefined) !== 'permission_response') {
      return;
    }

    const requestId = params?.['requestId'] as string | undefined;
    if (requestId === undefined || requestId.length === 0) {
      return;
    }
    const action: PermissionAction = {
      requestId: requestId,
      allow: (params?.['allow'] as boolean | undefined) === true
    };

    if (this.notificationHelper?.sendPermissionAction(action.requestId, action.allow) !== true) {
      this.pendingPermissionAction = action;
    }
  }

  private flushPendingPermissionAction(): void {
    const action = this.pendingPermissionAction;
    if (action === undefined || this.notificationHelper === undefined) {
      return;
    }
    if (this.notificationHelper.sendPermissionAction(action.requestId, action.allow)) {
      this.pendingPermissionAction = undefined;
    }
  }
}
