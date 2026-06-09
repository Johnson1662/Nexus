import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { StorageService, PrefsKeys, loadWorkspaces, loadHosts, loadModelCache } from '../services/StorageService';
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

    AppStorage.setOrCreate<string>('serverUrl', 'ws://192.168.137.1:12138');
    AppStorage.setOrCreate<string>('lastAgent', '');
    AppStorage.setOrCreate<boolean>('isConnected', false);

    StorageService.getInstance().init(this.context).then(() => {
      let storage = StorageService.getInstance();
      loadHosts().then(() => {
          storage.getString(PrefsKeys.SERVER_URL, 'ws://192.168.137.1:12138').then((url) => {
          AppStorage.setOrCreate<string>('serverUrl', url);
          // Load workspaces after host groups so all IPs for one device share a list.
          loadWorkspaces(url);
        });
      });
      storage.getString(PrefsKeys.LAST_AGENT, '').then((agent) => {
        AppStorage.setOrCreate<string>('lastAgent', agent);
        // Load cached model list for last used agent so UI shows models instantly
        if (agent.length > 0) {
          loadModelCache(agent).then((cached) => {
            if (cached !== null) {
              ChatStore.models = cached.models;
              ChatStore.modes = cached.modes;
            }
          });
        }
      });
      storage.getString(PrefsKeys.LAST_MODEL_ID, '').then((id) => {
        ChatStore.lastModelId = id;
        if (id.length > 0 && ChatStore.models.length > 0) {
          for (let i = 0; i < ChatStore.models.length; i++) {
            if (ChatStore.models[i].modelId === id) {
              ChatStore.modelIndex = i;
              break;
            }
          }
        }
      });
      storage.getString(PrefsKeys.LAST_MESSAGE_ID, '').then((mid) => {
        // Restore cursor position for session recovery after process crash
        ChatStore.lastMessageId = mid;
      });
      storage.getString(PrefsKeys.HOST_ID, '').then((hostId) => {
        AppStorage.setOrCreate<string>('hostId', hostId);
      });
      storage.getString(PrefsKeys.SERVER_HOST_PUBLIC_KEY, '').then((key) => {
        AppStorage.setOrCreate<string>('serverHostPublicKey', key);
      });
      storage.getString(PrefsKeys.HOST_ED25519_PUBLIC_KEY, '').then((key) => {
        AppStorage.setOrCreate<string>('hostEd25519PublicKey', key);
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
