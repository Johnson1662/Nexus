import { Colors } from '../constants/DesignTokens';
import { ChatStore } from '../common/model/ChatState';
import { WorkspaceStore, WorkspaceInfo } from '../common/model/WorkspaceInfo';
import { MessageData } from '../common/model/MessageData';
import { WSClient } from '../common/websocket/WSClient';
import { ClientMessage } from '../common/websocket/WSProtocol';
import { StorageService, PrefsKeys, saveWorkspaces, loadSessionCache } from '../services/StorageService';
import { ChatView } from '../feature/chat/ChatView';
import { OnboardingView } from '../feature/onboarding/OnboardingView';
import { WorkspaceSelectView } from '../feature/workspace/WorkspaceSelectView';

@Entry
@Component
export struct Index {
  private navStack: NavPathStack = new NavPathStack();
  private ws: WSClient = new WSClient();

  @Builder
  PagesMap(name: string) {
    if (name === 'workspace-select') {
      WorkspaceSelectView({
        onSelect: (i: number) => {
          this.navStack.pushPath({ name: 'chat' });
        },
        onAddWorkspace: (p: string) => {
          let ws = new WorkspaceInfo();
          ws.id = Date.now().toString();
          ws.name = p.split('\\').pop() || p.split('/').pop() || 'Project';
          ws.path = p;
          WorkspaceStore.workspaces.push(ws);
          WorkspaceStore.currentIndex = WorkspaceStore.workspaces.length - 1;
          saveWorkspaces(AppStorage.get<string>('serverUrl') || '');
          this.navStack.pushPath({ name: 'chat' });
        }
      })
    } else if (name === 'chat') {
      ChatView({
        onSendMessage: (t: string) => { this.sendMessage(t) },
        onSwitchModel: (i: number) => {
          if (ChatStore.sessionId && i > 0 && i - 1 < ChatStore.models.length) {
            ChatStore.modelIndex = i - 1;
            ChatStore.lastModelId = ChatStore.models[i - 1].modelId;
            StorageService.getInstance().putString(PrefsKeys.LAST_MODEL_ID, ChatStore.lastModelId);
            this.ws.send({ type: 'switch_model', sessionId: ChatStore.sessionId, model: ChatStore.models[i-1].modelId } as ClientMessage)
          }
        },
        onSwitchMode: (i: number) => {
          if (ChatStore.sessionId && i > 0 && i - 1 < ChatStore.modes.length) {
            ChatStore.modeIndex = i - 1;
            this.ws.send({ type: 'set_mode', sessionId: ChatStore.sessionId, modeId: ChatStore.modes[i-1].value } as ClientMessage)
          }
        },
        onSelectSession: (i: number) => {
          if (i > 0 && i - 1 < ChatStore.sessions.length) {
            ChatStore.messages = []; ChatStore.planEntries = []; ChatStore.turnActive = false;
            ChatStore.loadingSession = true;
            ChatStore.sessionReady = false;
            ChatStore.streamingThinking = '';
            let p = WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path;
            // Models already cached from agent selection — no need to re-request
            this.ws.send({ type: 'load_session', sessionId: ChatStore.sessions[i - 1].sessionId, cwd: p } as ClientMessage);
          }
        },
        onNewSession: () => {
          ChatStore.messages = [];
          ChatStore.planEntries = [];
          ChatStore.turnActive = false;
          ChatStore.sessionId = '';
          ChatStore.loadedSessionId = '';
          ChatStore.sessionReady = false;
          ChatStore.streamingThinking = '';
          let cwd = WorkspaceStore.currentIndex >= 0 ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path : '';
          let model = (ChatStore.modelIndex >= 0 && ChatStore.modelIndex < ChatStore.models.length)
            ? ChatStore.models[ChatStore.modelIndex].modelId : undefined;
          this.ws.send({ type: 'start', agent: ChatStore.agentType, cwd: cwd, model: model } as ClientMessage);
          this.ws.send({ type: 'list_sessions', cwd: cwd } as ClientMessage);
        },
        onWorkspaceSelect: (index: number) => {
          ChatStore.sessionId = '';
          ChatStore.loadedSessionId = '';
          ChatStore.messages = [];
          ChatStore.planEntries = [];
          ChatStore.turnActive = false;
          ChatStore.sessionReady = false;
          ChatStore.streamingThinking = '';
          let cwd = WorkspaceStore.workspaces[index].path;
          // Load cached sessions instantly, then refresh from server
          loadSessionCache(ChatStore.agentType, cwd).then((cached) => {
            if (cached !== null) {
              ChatStore.sessions = cached.sessions;
              ChatStore.sessionReady = true;
            }
          });
          // Models already cached from agent selection — only refresh sessions
          this.ws.send({ type: 'list_sessions', cwd: cwd, agent: ChatStore.agentType } as ClientMessage);
        },
        onPermissionResponse: (optionId: string) => {
          this.ws.sendPermissionResponse(optionId);
        },
      })
    }
  }

  sendMessage(text: string): void {
    if (!ChatStore.connected) {
      ChatStore.turnActive = false;
      return;
    }
    // Cancel current turn
    if (text === '__cancel__') {
      if (ChatStore.sessionId) {
        this.ws.send({ type: 'cancel', sessionId: ChatStore.sessionId } as ClientMessage);
      }
      ChatStore.turnActive = false;
      return;
    }
    ChatStore.messages = [...ChatStore.messages, new MessageData('user', text, 'text')];
    ChatStore.turnActive = true;
    if (ChatStore.sessionId) {
      this.ws.send({ type: 'input', sessionId: ChatStore.sessionId, text } as ClientMessage);
    } else {
      let cwd = WorkspaceStore.currentIndex >= 0 ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path : '';
      this.ws.send({ type: 'start', agent: ChatStore.agentType, prompt: text, cwd: cwd } as ClientMessage);
    }
  }

  build() {
    Navigation(this.navStack) {
      OnboardingView({
        ws: this.ws,
        callbacks: {
          onNavigateToWorkspaceSelect: () => { this.navStack.pushPath({ name: 'workspace-select' }) }
        }
      })
    }
    .navDestination(this.PagesMap)
    .hideTitleBar(true)
    .width('100%').height('100%')
    .backgroundColor(Colors.surface1)
    .mode(NavigationMode.Stack)
  }
}
