import { MethodChannel, MethodCall, MethodResult, FlutterEngine } from '@ohos/flutter_ohos';
import { liveViewManager } from '@kit.LiveViewKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'LiveViewHelper';
const CHANNEL_NAME = 'com.anywhere.app/live_view';

interface LiveViewTextContent {
  text: string;
}

interface LiveViewPrimaryData {
  title: string;
  content: Array<LiveViewTextContent>;
}

interface LiveViewDetailData {
  primary: LiveViewPrimaryData;
}

interface LiveViewConfig {
  id: number;
  event: string;
  liveViewData: LiveViewDetailData;
}

export class LiveViewHelper {
  private channel: MethodChannel;

  constructor(flutterEngine: FlutterEngine) {
    this.channel = new MethodChannel(flutterEngine.dartExecutor.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        if (call.method === 'updateLiveView') {
          this.updateLiveView(call, result);
        } else if (call.method === 'stopLiveView') {
          this.stopLiveView(call, result);
        } else {
          result.notImplemented();
        }
      }
    });
  }

  private async updateLiveView(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const args = call.args as Record<string, Object>;
      const progress = (args['progress'] as number) ?? 0;
      const statusText = (args['statusText'] as string) ?? '';
      const title = (args['title'] as string) ?? 'Nexus AI';

      const textItem: LiveViewTextContent = { text: `[${Math.round(progress * 100)}%] ${statusText}` };
      const textArray: Array<LiveViewTextContent> = [textItem];
      const primaryData: LiveViewPrimaryData = {
        title: title,
        content: textArray
      };
      const detailData: LiveViewDetailData = { primary: primaryData };
      const config: LiveViewConfig = {
        id: 100,
        event: 'SESSION_PROGRESS',
        liveViewData: detailData
      };

      await liveViewManager.startLiveView((config as Object) as liveViewManager.LiveView);
      result.success(true);
    } catch (e) {
      console.error(TAG, `updateLiveView failed: ${(e as BusinessError).message}`);
      result.success(false);
    }
  }

  private async stopLiveView(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const textItem: LiveViewTextContent = { text: '完成' };
      const textArray: Array<LiveViewTextContent> = [textItem];
      const primaryData: LiveViewPrimaryData = {
        title: 'Nexus AI',
        content: textArray
      };
      const detailData: LiveViewDetailData = { primary: primaryData };
      const config: LiveViewConfig = {
        id: 100,
        event: 'SESSION_PROGRESS',
        liveViewData: detailData
      };

      await liveViewManager.stopLiveView((config as Object) as liveViewManager.LiveView);
      result.success(true);
    } catch (e) {
      console.error(TAG, `stopLiveView failed: ${(e as BusinessError).message}`);
      result.success(false);
    }
  }
}
