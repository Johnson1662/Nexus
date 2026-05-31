import { Colors } from '../constants/DesignTokens';
import { ChatStore, trimMessages } from '../common/model/ChatState';
import { WorkspaceStore, WorkspaceInfo, HostStore } from '../common/model/WorkspaceInfo';
import { MessageData } from '../common/model/MessageData';
import { WSClient } from '../common/websocket/WSClient';
import { ClientMessage } from '../common/websocket/WSProtocol';
import { StorageService, PrefsKeys, saveWorkspaces, saveHosts, loadSessionCache } from '../services/StorageService';
import { ChatView } from '../feature/chat/ChatView';
import { OnboardingView } from '../feature/onboarding/OnboardingView';
import { SettingsPage } from '../feature/settings/SettingsView';
import { HostManagePage } from '../feature/host/HostManageView';
import { AcpUpdate } from '../common/websocket/WSProtocol';
import { handleAcpUpdate } from '../common/model/MessageHandler';

@Entry
@Component
export struct Index {
  private navStack: NavPathStack = new NavPathStack();
  private ws: WSClient = new WSClient();

  aboutToAppear(): void {
    AppStorage.setOrCreate('pref_thinking_expanded', true);
    AppStorage.setOrCreate('pref_toolcall_expanded', true);
    this.ws.onAcpUpdate((update: AcpUpdate) => { handleAcpUpdate(update); });
  }

  @Builder
  PagesMap(name: string) {
    if (name === 'chat') {
      ChatView({
        onSendMessage: (t: string) => { this.sendMessage(t) },
        onRetry: (id: string, content: string) => { this.retryMessage(id, content) },
        onSwitchModel: (i: number) => {
          if (ChatStore.bridgeSessionId && i > 0 && i - 1 < ChatStore.models.length) {
            ChatStore.modelIndex = i - 1;
            ChatStore.lastModelId = ChatStore.models[i - 1].modelId;
            StorageService.getInstance().putString(PrefsKeys.LAST_MODEL_ID, ChatStore.lastModelId);
            this.ws.send({ type: 'switch_model', sessionId: ChatStore.bridgeSessionId, model: ChatStore.models[i-1].modelId } as ClientMessage)
          }
        },
        onSwitchMode: (i: number) => {
          if (ChatStore.bridgeSessionId && i > 0 && i - 1 < ChatStore.modes.length) {
            ChatStore.modeIndex = i - 1;
            this.ws.send({ type: 'set_mode', sessionId: ChatStore.bridgeSessionId, modeId: ChatStore.modes[i-1].value } as ClientMessage)
          }
        },
        onSelectSession: (i: number) => {
          if (i > 0 && i - 1 < ChatStore.sessions.length) {
            if (ChatStore.bridgeSessionId) {
              this.ws.send({ type: 'close_session', sessionId: ChatStore.bridgeSessionId } as ClientMessage);
            }
            ChatStore.loadingSession = true;
            let p = WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path;
            this.ws.send({ type: 'resume_session', sessionId: ChatStore.sessions[i - 1].sessionId, cwd: p, agent: ChatStore.agentType } as ClientMessage);
          }
        },
        onNewSession: () => {
          if (ChatStore.bridgeSessionId) {
            this.ws.send({ type: 'close_session', sessionId: ChatStore.bridgeSessionId } as ClientMessage);
          }
          ChatStore.messages = [];
          ChatStore.planEntries = [];
          ChatStore.turnActive = false;
          ChatStore.bridgeSessionId = '';
          ChatStore.acpSessionId = '';
          ChatStore.streamingThinking = '';
        },
        onWorkspaceSelect: (index: number) => {
          if (ChatStore.bridgeSessionId) {
            this.ws.send({ type: 'close_session', sessionId: ChatStore.bridgeSessionId } as ClientMessage);
          }
          ChatStore.bridgeSessionId = '';
          ChatStore.acpSessionId = '';
          ChatStore.messages = [];
          ChatStore.planEntries = [];
          ChatStore.turnActive = false;
          ChatStore.streamingThinking = '';
          let cwd = WorkspaceStore.workspaces[index].path;
          loadSessionCache(ChatStore.agentType, cwd).then((cached) => {
            if (cached !== null) {
              ChatStore.sessions = cached.sessions;
            }
          });
          this.ws.send({ type: 'list_sessions', cwd: cwd, agent: ChatStore.agentType } as ClientMessage);
        },
        onPermissionResponse: (optionId: string) => {
          this.ws.sendPermissionResponse(optionId);
        },
        onNavigateToOnboarding: () => {
          this.navStack.pop();
        },
        onNavigateToSettings: () => {
          this.navStack.pushPath({ name: 'settings' });
        },
        onNavigateToHostManage: () => {
          this.navStack.pushPath({ name: 'host-manage' });
        },
      })
    } else if (name === 'settings') {
      SettingsPage()
    } else if (name === 'host-manage') {
      HostManagePage({
        onConnect: (url: string) => {
          AppStorage.setOrCreate('serverUrl', url);
          this.ws.disconnect();
          this.ws.connect(url);
          this.navStack.pop();
        },
        onDeleteHost: (index: number) => {
          HostStore.removeDevice(index);
          saveHosts();
        }
      })
    }
  }

  sendMessage(text: string, retryId?: string): void {
    if (text === '__cancel__') {
      if (ChatStore.bridgeSessionId) {
        this.ws.send({ type: 'cancel', sessionId: ChatStore.bridgeSessionId } as ClientMessage);
      }
      ChatStore.turnActive = false;
      return;
    }
    if (!ChatStore.connected) {
      ChatStore.turnActive = false;
      let m = new MessageData('user', text, 'text');
      m.sendStatus = 'failed';
      if (retryId) {
        ChatStore.messages = ChatStore.messages.filter((msg: MessageData) => msg.id !== retryId);
      }
      ChatStore.messages = [...ChatStore.messages, m];
      return;
    }
    if (retryId) {
      ChatStore.messages = ChatStore.messages.filter((msg: MessageData) => msg.id !== retryId);
    }
    ChatStore.messages = [...ChatStore.messages, new MessageData('user', text, 'text')];
    trimMessages();
    ChatStore.turnActive = true;
    if (ChatStore.bridgeSessionId) {
      this.ws.send({ type: 'input', sessionId: ChatStore.bridgeSessionId, text } as ClientMessage);
    } else {
      let cwd = WorkspaceStore.currentIndex >= 0 ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path : '';
      if (!cwd) {
        ChatStore.turnActive = false;
        ChatStore.messages.pop();
        this.getUIContext().getPromptAction().showToast({ message: '请先选择工作目录' });
        return;
      }
      ChatStore.loadingSession = true;
      this.ws.send({ type: 'start', agent: ChatStore.agentType, prompt: text, cwd: cwd } as ClientMessage);
    }
  }

  retryMessage(id: string, content: string): void {
    this.sendMessage(content, id);
  }

  build() {
    Navigation(this.navStack) {
      OnboardingView({
        ws: this.ws,
        callbacks: {
          onNavigateToChat: () => {
            this.navStack.pushPath({ name: 'chat' });
          }
        }
      })
    }
    .navDestination(this.PagesMap)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface1)
    .mode(NavigationMode.Stack)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
