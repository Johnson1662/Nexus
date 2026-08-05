import { MethodChannel, MethodCall, MethodResult, FlutterEngine } from '@ohos/flutter_ohos';
import { liveViewManager } from '@kit.LiveViewKit';
import { WantAgent, wantAgent, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';

const TAG = 'LiveViewHelper';
const CHANNEL_NAME = 'com.nexus.remoteai/live_view';
const LIVE_VIEW_ID = 100;
const LIVE_VIEW_EVENT = 'PROGRESS';
const ERROR_LIVE_VIEW_NOT_FOUND = 1003500009;
const ERROR_LIVE_VIEW_ENDED = 1003500010;
const ERROR_LIVE_VIEW_SEQUENCE = 1003500011;

class LiveViewOperationError extends Error {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

export class LiveViewHelper {
  private channel: MethodChannel;
  private wantAgentInfo: wantAgent.WantAgentInfo;
  private sequenceCounter: number = 0;
  private isLiveViewActive: boolean = false;
  private disposed: boolean = false;
  private operationTail: Promise<void> = Promise.resolve();
  private nodeIconCache: image.PixelMap | null = null;

  constructor(flutterEngine: FlutterEngine) {
    this.wantAgentInfo = {
      wants: [{
        bundleName: 'com.nexus.remoteai',
        abilityName: 'EntryAbility'
      }],
      actionType: wantAgent.OperationType.START_ABILITIES,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    this.channel = new MethodChannel(flutterEngine.dartExecutor.getBinaryMessenger(), CHANNEL_NAME);
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.enqueue(call, result);
      }
    });
  }

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.channel.setMethodCallHandler(null);
    if (this.nodeIconCache) {
      try {
        this.nodeIconCache.release();
      } catch { /* ignore */ }
      this.nodeIconCache = null;
    }
    this.resetState();
  }

  private enqueue(call: MethodCall, result: MethodResult): void {
    const operation = this.operationTail.then(
      (): Promise<void> => this.dispatch(call, result),
      (): Promise<void> => this.dispatch(call, result)
    );
    this.operationTail = operation.catch((error: Object): void => {
      console.error(TAG, `channel operation failed: ${this.errorMessage(error)}`);
      result.success(false);
    });
  }

  private async dispatch(call: MethodCall, result: MethodResult): Promise<void> {
    if (this.disposed) {
      result.success(false);
      return;
    }
    if (call.method === 'updateLiveView') {
      await this.updateLiveView(call, result);
    } else if (call.method === 'stopLiveView') {
      await this.stopLiveView(call, result);
    } else {
      result.notImplemented();
    }
  }

  private async buildWantAgent(): Promise<WantAgent> {
    return await wantAgent.getWantAgent(this.wantAgentInfo);
  }

  /** 懒加载并缓存应用图标 PixelMap（每次更新都重新解码很浪费）。 */
  private async loadNodeIcons(): Promise<Array<string | image.PixelMap>> {
    if (this.nodeIconCache) {
      return [this.nodeIconCache];
    }
    try {
      // nodeIcons 仅接受 string | PixelMap，需把媒体资源转成 PixelMap
      const context = getContext() as common.UIAbilityContext;
      const data: Uint8Array = await context.resourceManager.getMediaContent($r('app.media.app_icon'));
      const source: image.ImageSource = image.createImageSource(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
      this.nodeIconCache = await source.createPixelMap();
      return [this.nodeIconCache];
    } catch (err) {
      console.error(TAG, `load node icon failed: ${this.errorMessage(err)}`);
      return [];
    }
  }

  private async buildConfig(
    progress: number,
    statusText: string,
    title: string,
    sequence: number
  ): Promise<liveViewManager.LiveView> {
    const boundedProgress = Math.max(0, Math.min(1, progress));
    const percentage = Math.round(boundedProgress * 100);
    const nodeIcons = await this.loadNodeIcons();
    return {
      id: LIVE_VIEW_ID,
      event: LIVE_VIEW_EVENT,
      sequence: sequence,
      isMute: true,
      liveViewData: {
        primary: {
          title: title,
          content: [{ text: `[${percentage}%] ${statusText}` }],
          keepTime: 0,
          clickAction: await this.buildWantAgent(),
          layoutData: {
            layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PROGRESS,
            progress: percentage,
            nodeIcons: nodeIcons
          }
        }
      }
    };
  }

  private async expectSuccess(operation: Promise<liveViewManager.LiveViewResult>): Promise<void> {
    const response = await operation;
    if (response.resultCode !== 0) {
      throw new LiveViewOperationError(response.resultCode, String(response.message));
    }
  }

  private async start(config: liveViewManager.LiveView): Promise<void> {
    await this.expectSuccess(liveViewManager.startLiveView(config));
  }

  private async update(config: liveViewManager.LiveView): Promise<void> {
    await this.expectSuccess(liveViewManager.updateLiveView(config));
  }

  private async stop(config: liveViewManager.LiveView): Promise<void> {
    await this.expectSuccess(liveViewManager.stopLiveView(config));
  }

  private async updateLiveView(call: MethodCall, result: MethodResult): Promise<void> {
    let recoveryAttempted = false;
    try {
      const args = call.args as Record<string, Object>;
      const progress = (args['progress'] as number) ?? 0;
      const statusText = (args['statusText'] as string) ?? '';
      const title = (args['title'] as string) ?? 'Nexus AI';
      const sequence = this.isLiveViewActive ? this.sequenceCounter + 1 : 1;
      const config = await this.buildConfig(progress, statusText, title, sequence);

      if (!this.isLiveViewActive) {
        await this.start(config);
        if (this.disposed) {
          result.success(false);
          return;
        }
        this.isLiveViewActive = true;
        this.sequenceCounter = sequence;
      } else {
        try {
          await this.update(config);
          if (this.disposed) {
            result.success(false);
            return;
          }
          this.sequenceCounter = sequence;
        } catch (e) {
          if (!this.isStateError(e)) {
            throw new Error(this.errorMessage(e));
          }
          // The service may end a view while the app is backgrounded. A stale
          // local sequence must not poison the next update.
          recoveryAttempted = true;
          this.resetState();
          const restartConfig = await this.buildConfig(progress, statusText, title, 1);
          await this.start(restartConfig);
          if (this.disposed) {
            result.success(false);
            return;
          }
          this.isLiveViewActive = true;
          this.sequenceCounter = 1;
        }
      }
      result.success(true);
    } catch (e) {
      if (recoveryAttempted || this.isStateError(e)) {
        this.resetState();
      }
      console.error(TAG, `updateLiveView failed: ${this.errorMessage(e)}`);
      result.success(false);
    }
  }

  private async stopLiveView(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const sequence = this.isLiveViewActive ? this.sequenceCounter + 1 : 1;
      const config = await this.buildConfig(1, '完成', 'Nexus AI', sequence);
      try {
        await this.stop(config);
      } catch (e) {
        if (!this.isStateError(e)) {
          throw new Error(this.errorMessage(e));
        }
        // Already ended/not found is an idempotent successful stop.
      }
      this.resetState();
      result.success(true);
    } catch (e) {
      console.error(TAG, `stopLiveView failed: ${this.errorMessage(e)}`);
      result.success(false);
    }
  }

  private resetState(): void {
    this.isLiveViewActive = false;
    this.sequenceCounter = 0;
  }

  private isStateError(error: Object): boolean {
    const code = (error as BusinessError).code;
    return code === ERROR_LIVE_VIEW_NOT_FOUND
      || code === ERROR_LIVE_VIEW_ENDED
      || code === ERROR_LIVE_VIEW_SEQUENCE;
  }

  private errorMessage(error: Object): string {
    const businessError = error as BusinessError;
    return `${businessError.code} ${businessError.message}`;
  }
}
