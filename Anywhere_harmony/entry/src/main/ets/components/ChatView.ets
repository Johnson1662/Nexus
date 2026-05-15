import { Colors, FontSize, Spacing, Radius } from '../constants/DesignTokens';
import { ChatStore } from '../common/model/ChatState';
import { WorkspaceStore } from '../common/model/WorkspaceInfo';
import { WorkspaceInfo } from '../common/model/WorkspaceInfo';
import { ChatPage } from '../feature/chat/ChatPage';
import { WorkspaceDrawer } from '../feature/workspace/WorkspaceDrawer';

interface SO { value: string }

@Component
export struct ChatView {
  @State showDrawer: boolean = false;
  @State showPathInput: boolean = false;
  @State newPath: string = '';
  onSendMessage?: (text: string) => void;
  onSwitchModel?: (index: number) => void;
  onSwitchMode?: (index: number) => void;
  onClearSession?: () => void;
  onSelectSession?: (i: number) => void;
  onWorkspaceSelect?: (index: number) => void;
  onDisconnect?: () => void;

  getSessionOpts(): SO[] {
    let o: SO[] = [{ value: 'Sessions (' + ChatStore.sessions.length + ')' }];
    for (let i = 0; i < ChatStore.sessions.length; i++) {
      let title = ChatStore.sessions[i].title || ChatStore.sessions[i].sessionId.substring(0, 8);
      if (title.length > 30) title = title.substring(0, 30) + '\u2026';
      o.push({ value: title });
    }
    return o;
  }

  build() {
    NavDestination() {
      SideBarContainer(SideBarContainerType.Overlay) {
        WorkspaceDrawer({
          workspaces: WorkspaceStore.workspaces,
          currentIndex: WorkspaceStore.currentIndex,
          hostName: 'host',
          hostUrl: 'ws://...',
          agentType: ChatStore.agentType,
          onSelect: (i: number) => {
            WorkspaceStore.currentIndex = i;
            this.showDrawer = false;
            if (this.onWorkspaceSelect) this.onWorkspaceSelect(i);
          },
          onClose: () => { this.showDrawer = false; },
          onAddWorkspace: (p: string) => {
            let ws = new WorkspaceInfo();
            ws.id = Date.now().toString();
            ws.name = p.split('\\').pop() || p.split('/').pop() || 'Project';
            ws.path = p;
            WorkspaceStore.workspaces.push(ws);
            WorkspaceStore.currentIndex = WorkspaceStore.workspaces.length - 1;
            this.showDrawer = false;
            if (this.onWorkspaceSelect) this.onWorkspaceSelect(WorkspaceStore.workspaces.length - 1);
          }
        })
        Column() {
          Row() {
            SymbolGlyph(this.showDrawer ? $r('sys.symbol.close_sidebar') : $r('sys.symbol.open_sidebar'))
              .fontSize(20)
              .fontColor([Colors.foreground])
              .onClick(() => { this.showDrawer = true })

            Blank()

            SymbolGlyph($r('sys.symbol.ohos_trash')).fontColor([Colors.foregroundLight]).fontSize(16).margin({ right: Spacing.md })
              .onClick(() => { if (this.onClearSession) this.onClearSession() })
            Text('\u2190').fontSize(16).fontColor(Colors.foregroundLight)
              .onClick(() => { if (this.onDisconnect) this.onDisconnect() })
          }
          .width('100%').height(40)
          .padding({ left: Spacing.lg, right: Spacing.lg })
          .backgroundColor(Colors.surfaceElevated)

          Row() {
            Select(this.getSessionOpts()).selected(0).value('Sessions (' + ChatStore.sessions.length + ')')
              .font({ size: FontSize.sm }).fontColor(Colors.foreground)
              .selectedOptionFont({ size: FontSize.sm })
              .selectedOptionFontColor(Colors.accent)
              .selectedOptionBgColor(Colors.accentLight)
              .layoutWeight(1).backgroundColor('transparent')
              .onSelect((i) => { if (this.onSelectSession) this.onSelectSession(i) })
            SymbolGlyph($r('sys.symbol.chevron_down')).fontColor([Colors.foregroundMuted]).fontSize(14)
          }
          .width('100%').height(36)
          .padding({ left: Spacing.lg, right: Spacing.lg })
          .backgroundColor(Colors.surface0)
          .border({ width: { bottom: 1 }, color: Colors.borderLight })

          ChatPage({
            messages: ChatStore.messages,
            planEntries: ChatStore.planEntries,
            turnActive: ChatStore.turnActive,
            models: ChatStore.models,
            modes: ChatStore.modes,
            onSendMessage: (t: string) => { if (this.onSendMessage) this.onSendMessage(t) },
            onSwitchModel: (i: number) => { if (this.onSwitchModel) this.onSwitchModel(i) },
            onSwitchMode: (i: number) => { if (this.onSwitchMode) this.onSwitchMode(i) }
          }).layoutWeight(1)
        }
        .width('100%').height('100%')
      }
      .showSideBar($$this.showDrawer)
      .showControlButton(false)
      .sideBarWidth(300)
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }
}
