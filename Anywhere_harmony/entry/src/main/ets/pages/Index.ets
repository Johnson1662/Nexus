import { Colors } from '../constants/DesignTokens';
import { ChatStore } from '../common/model/ChatState';
import { WorkspaceStore } from '../common/model/WorkspaceInfo';
import { MessageData } from '../common/model/MessageData';
import { WSClient } from '../common/websocket/WSClient';
import { ClientMessage } from '../common/websocket/WSProtocol';
import { ChatView } from '../components/ChatView';
import { OnboardingView } from '../feature/onboarding/OnboardingView';

@Entry
@Component
export struct Index {
  private navStack: NavPathStack = new NavPathStack();
  private ws: WSClient = new WSClient(); // replaced by OnboardingView's connected instance via onWsClientReady

  @Builder
  PagesMap(name: string) {
    if (name === 'chat') {
      ChatView({
        onSendMessage: (t: string) => { this.sendMessage(t) },
        onSwitchModel: (i: number) => {
          if (ChatStore.sessionId && i > 0 && i - 1 < ChatStore.models.length) {
            ChatStore.modelIndex = i - 1;
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
            ChatStore.sessionId = ChatStore.sessions[i - 1].sessionId;
            ChatStore.messages = []; ChatStore.planEntries = []; ChatStore.turnActive = false;
            let p = WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path;
            this.ws.send({ type: 'load_session', sessionId: ChatStore.sessions[i - 1].sessionId, cwd: p } as ClientMessage);
          }
        },
        onNewSession: () => {
          ChatStore.messages = [];
          ChatStore.planEntries = [];
          ChatStore.turnActive = false;
          ChatStore.sessionId = '';
          let cwd = WorkspaceStore.currentIndex >= 0 ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path : '';
          let model = (ChatStore.modelIndex >= 0 && ChatStore.modelIndex < ChatStore.models.length)
            ? ChatStore.models[ChatStore.modelIndex].modelId : undefined;
          this.ws.send({ type: 'start', agent: ChatStore.agentType, cwd: cwd, model: model } as ClientMessage);
        },
        onWorkspaceSelect: (index: number) => {
          this.ws.send({ type: 'list_sessions', cwd: WorkspaceStore.workspaces[index].path } as ClientMessage);
        },
      })
    }
  }

  sendMessage(text: string): void {
    if (!ChatStore.connected) {
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
        callbacks: {
          onNavigateToChat: () => { this.navStack.pushPath({ name: 'chat' }) },
          onWsClientReady: (ws: WSClient) => { this.ws = ws; }
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
