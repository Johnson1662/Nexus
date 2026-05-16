import { Colors, FontSize, Spacing, Radius } from '../constants/DesignTokens';
import { ChatStore } from '../common/model/ChatState';
import { WorkspaceStore } from '../common/model/WorkspaceInfo';
import { WorkspaceInfo } from '../common/model/WorkspaceInfo';
import { ChatPage } from '../feature/chat/ChatPage';
import { WorkspaceDrawer } from '../feature/workspace/WorkspaceDrawer';

@Component
export struct ChatView {
  @State showDrawer: boolean = false;
  @State showPathInput: boolean = false;
  @State newPath: string = '';
  @State showPicker: boolean = false;
  @State pickerTitle: string = '';
  @State pickerItems: string[] = [];
  @State pickerMode: number = -1;
  onSendMessage?: (text: string) => void;
  onSwitchModel?: (index: number) => void;
  onSwitchMode?: (index: number) => void;
  onNewSession?: () => void;
  onSelectSession?: (i: number) => void;
  onWorkspaceSelect?: (index: number) => void;

  getSessionTitle(): string {
    let targetId = ChatStore.loadedSessionId || ChatStore.sessionId;
    for (let i = 0; i < ChatStore.sessions.length; i++) {
      if (ChatStore.sessions[i].sessionId === targetId) {
        return ChatStore.sessions[i].title || ChatStore.sessions[i].sessionId.substring(0, 8);
      }
    }
    return 'Session';
  }

  getModelName(): string {
    if (ChatStore.modelIndex >= 0 && ChatStore.modelIndex < ChatStore.models.length) {
      return ChatStore.models[ChatStore.modelIndex].name;
    }
    return '';
  }

  openPicker(mode: number): void {
    if (mode === 0) {
      this.pickerTitle = 'Sessions';
      this.pickerItems = [];
      for (let j = 0; j < ChatStore.sessions.length; j++) {
        let title = ChatStore.sessions[j].title || ChatStore.sessions[j].sessionId.substring(0, 8);
        if (title.length > 30) title = title.substring(0, 30) + '\u2026';
        this.pickerItems.push(title);
      }
    } else if (mode === 1) {
      this.pickerTitle = 'Models';
      this.pickerItems = ChatStore.models.map(m => m.name);
    } else if (mode === 2) {
      this.pickerTitle = 'Modes';
      this.pickerItems = ChatStore.modes.map(m => m.name);
    }
    this.pickerMode = mode;
    this.showPicker = true;
  }

  doPickerSelect(index: number): void {
    this.showPicker = false;
    if (this.pickerMode === 0 && this.onSelectSession) {
      this.onSelectSession(index + 1);
    } else if (this.pickerMode === 1 && this.onSwitchModel) {
      this.onSwitchModel(index + 1);
    } else if (this.pickerMode === 2 && this.onSwitchMode) {
      this.onSwitchMode(index + 1);
    }
  }

  showMenu(): void {
    this.pickerTitle = 'Menu';
    this.pickerItems = ['Switch Session', 'Switch Model', 'Switch Agent Mode'];
    this.pickerMode = -1;
    this.showPicker = true;
  }

  onMenuSelect(index: number): void {
    if (index === 0) this.openPicker(0);
    else if (index === 1) this.openPicker(1);
    else if (index === 2) this.openPicker(2);
  }

  build() {
    NavDestination() {
      Stack() {
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
            if (this.showPathInput) {
              Row() {
                TextInput({ placeholder: '/path/to/project', text: this.newPath })
                  .layoutWeight(1).height(36)
                  .backgroundColor(Colors.surface1).borderRadius(Radius.sm)
                  .padding({ left: Spacing.md, right: Spacing.md })
                  .fontSize(FontSize.xs)
                  .onChange((v: string) => { this.newPath = v })
                Button('Add').height(36).backgroundColor(Colors.accent).fontColor(Color.White)
                  .borderRadius(Radius.sm).fontSize(FontSize.xs)
                  .onClick(() => {
                    let p = this.newPath.trim();
                    if (p.length > 0) {
                      let ws = new WorkspaceInfo();
                      ws.id = Date.now().toString();
                      ws.name = p.split('\\').pop() || p.split('/').pop() || 'Project';
                      ws.path = p;
                      WorkspaceStore.workspaces.push(ws);
                      WorkspaceStore.currentIndex = WorkspaceStore.workspaces.length - 1;
                      this.newPath = '';
                      this.showPathInput = false;
                      if (this.onWorkspaceSelect) this.onWorkspaceSelect(WorkspaceStore.workspaces.length - 1);
                    }
                  })
              }
              .width('100%').padding({ left: Spacing.md, right: Spacing.md, top: Spacing.xs, bottom: Spacing.xs })
              .backgroundColor(Colors.surfaceElevated)
              .transition(TransitionEffect.OPACITY)
            }

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

        if (this.showPicker) {
          Column() {
            Column() {
              Text(this.pickerTitle)
                .fontSize(FontSize.xl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
                .margin({ top: Spacing.xl, bottom: Spacing.lg })
                .alignSelf(ItemAlign.Start)

              List() {
                ForEach(this.pickerItems, (item: string, index: number) => {
                  ListItem() {
                    Text(item)
                      .fontSize(FontSize.base).fontColor(Colors.foreground)
                      .padding({ top: Spacing.md, bottom: Spacing.md, left: Spacing.md, right: Spacing.md })
                      .width('100%')
                  }
                  .width('100%').borderRadius(Radius.md)
                  .backgroundColor(Colors.surface1)
                  .margin({ bottom: Spacing.xs })
                  .onClick(() => {
                    if (this.pickerMode === -1) {
                      this.onMenuSelect(index);
                    } else {
                      this.doPickerSelect(index);
                    }
                  })
                }, (item: string) => item)
              }
              .width('100%').layoutWeight(1)

              Button('Cancel')
                .width('100%').height(44)
                .backgroundColor(Colors.surface2).fontColor(Colors.foreground)
                .borderRadius(Radius.md).fontSize(FontSize.base)
                .margin({ top: Spacing.md, bottom: Spacing.xs })
                .onClick(() => { this.showPicker = false })
            }
            .constraintSize({ maxHeight: '80%' })
            .width('75%').padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xl })
            .backgroundColor(Colors.surfaceElevated).borderRadius(Radius.xl)
            .shadow({ radius: 32, color: '#00000020', offsetY: 8 })
          }
          .width('100%').height('100%')
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .backgroundColor('#00000040')
          .onClick(() => { this.showPicker = false })
          .transition(TransitionEffect.OPACITY)
          .animation({ duration: 200, curve: Curve.FastOutSlowIn })
        }
      }
      .width('100%').height('100%')
    }
    .title(this.TitleBar)
    .hideBackButton(true)
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }

  @Builder
  TitleBar() {
    Row() {
      SymbolGlyph(this.showDrawer ? $r('sys.symbol.close_sidebar') : $r('sys.symbol.open_sidebar'))
        .fontSize(24)
        .fontColor([Colors.foreground])
        .onClick(() => { this.showDrawer = !this.showDrawer })

      Column() {
        Text(this.getSessionTitle())
          .fontSize(FontSize.base).fontColor(Colors.foreground).fontWeight(FontWeight.Medium)
          .lineHeight(20).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.getModelName())
          .fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
          .lineHeight(16).maxLines(1)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Spacing.sm })

      SymbolGlyph($r('sys.symbol.plus'))
        .fontColor([Colors.foreground]).fontSize(24).margin({ right: Spacing.md })
        .onClick(() => { if (this.onNewSession) this.onNewSession() })

      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontColor([Colors.foreground]).fontSize(24)
        .onClick(() => { this.showMenu() })
    }
    .width('100%').height('100%')
    .padding({ left: Spacing.lg, right: Spacing.lg })
  }
}
