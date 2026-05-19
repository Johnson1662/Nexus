import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { StorageService, PrefsKeys } from '../services/StorageService';
import { ChatStore } from '../common/model/ChatState';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set color mode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'Ability onCreate');

    AppStorage.setOrCreate<string>('serverUrl', 'ws://100.111.77.50:12138');
    AppStorage.setOrCreate<string>('lastAgent', '');
    AppStorage.setOrCreate<boolean>('isConnected', false);

    StorageService.getInstance().init(this.context).then(() => {
      let storage = StorageService.getInstance();
      storage.getString(PrefsKeys.SERVER_URL, 'ws://100.111.77.50:12138').then((url) => {
        AppStorage.setOrCreate<string>('serverUrl', url);
      });
      storage.getString(PrefsKeys.LAST_AGENT, '').then((agent) => {
        AppStorage.setOrCreate<string>('lastAgent', agent);
      });
      storage.getString(PrefsKeys.LAST_MODEL_ID, '').then((id) => {
        ChatStore.lastModelId = id;
        // If models are already loaded, try to match persisted model
        if (id.length > 0 && ChatStore.models.length > 0) {
          for (let i = 0; i < ChatStore.models.length; i++) {
            if (ChatStore.models[i].modelId === id) {
              ChatStore.modelIndex = i;
              break;
            }
          }
        }
      });
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');

    windowStage.getMainWindow().then((windowClass) => {
      windowClass.setWindowSystemBarProperties({
        statusBarContentColor: '#000000'
      });
    }).catch(() => {
      hilog.error(DOMAIN, TAG, 'Failed to obtain main window.');
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
