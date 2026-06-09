import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { StorageService, PrefsKeys, loadWorkspaces, loadHosts, loadModelCache } from '../services/StorageService';
import { ChatStore } from '../common/model/ChatState';
import { AppPreferenceService } from '../services/AppPreferenceService';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  private syncSystemLanguagePreference(): void {
    StorageService.getInstance().getString(PrefsKeys.APP_LANGUAGE, AppPreferenceService.LANGUAGE_SYSTEM)
      .then((language: string) => {
        let normalized: string = AppPreferenceService.normalizeLanguage(language);
        AppPreferenceService.setPreferenceState('pref_app_language', normalized);
        if (normalized === AppPreferenceService.LANGUAGE_SYSTEM) {
          AppPreferenceService.applyLanguage(normalized);
        }
      })
      .catch(() => {});
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');

    AppStorage.setOrCreate<string>('serverUrl', 'ws://192.168.137.1:12138');
    AppStorage.setOrCreate<string>('lastAgent', '');
    AppStorage.setOrCreate<boolean>('isConnected', false);
    AppStorage.setOrCreate<string>('pref_app_language', AppPreferenceService.LANGUAGE_SYSTEM);
    AppStorage.setOrCreate<string>('pref_color_mode', AppPreferenceService.COLOR_SYSTEM);

    StorageService.getInstance().init(this.context).then(() => {
      let storage = StorageService.getInstance();
      storage.getString(PrefsKeys.APP_LANGUAGE, AppPreferenceService.LANGUAGE_SYSTEM).then((language) => {
        let normalized: string = AppPreferenceService.normalizeLanguage(language);
        if (!AppPreferenceService.applyLanguage(normalized)) {
          hilog.error(DOMAIN, TAG, 'Failed to apply language preference');
          return;
        }
        AppPreferenceService.setPreferenceState('pref_app_language', normalized);
      });
      storage.getString(PrefsKeys.COLOR_MODE, AppPreferenceService.COLOR_SYSTEM).then((colorMode) => {
        let normalized: string = AppPreferenceService.normalizeColorMode(colorMode);
        if (!AppPreferenceService.applyColorMode(this.context, normalized)) {
          hilog.error(DOMAIN, TAG, 'Failed to apply color mode preference');
          return;
        }
        AppPreferenceService.setPreferenceState('pref_color_mode', normalized);
      });
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
    this.syncSystemLanguagePreference();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
