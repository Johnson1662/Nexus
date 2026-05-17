import { Colors, FontSize, Spacing, Radius, Duration } from '../constants/DesignTokens';
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
    } else if (mode === 1) {
      this.pickerTitle = 'Models';
    } else if (mode === 2) {
      this.pickerTitle = 'Modes';
    }
    this.pickerMode = mode;
    this.showPicker = true;
  }

  aboutToAppear(): void {
    if (WorkspaceStore.currentIndex >= 0 && this.onWorkspaceSelect) {
      this.onWorkspaceSelect(WorkspaceStore.currentIndex);
    }
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
              this.getUIContext()?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = false });
              if (this.onWorkspaceSelect) this.onWorkspaceSelect(i);
            },
            onDelete: (i: number) => {
              WorkspaceStore.workspaces.splice(i, 1);
              if (WorkspaceStore.currentIndex >= WorkspaceStore.workspaces.length) {
                WorkspaceStore.currentIndex = WorkspaceStore.workspaces.length - 1;
              }
            },
            onClose: () => { this.getUIContext()?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = false }) },
            onAddWorkspace: (p: string) => {
              let ws = new WorkspaceInfo();
              ws.id = Date.now().toString();
              ws.name = p.split('\\').pop() || p.split('/').pop() || 'Project';
              ws.path = p;
              WorkspaceStore.workspaces.push(ws);
              WorkspaceStore.currentIndex = WorkspaceStore.workspaces.length - 1;
              this.getUIContext()?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = false });
              if (this.onWorkspaceSelect) this.onWorkspaceSelect(WorkspaceStore.workspaces.length - 1);
            }
          })

          Column() {
            this.TitleBar()

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
              onSendMessage: (t: string) => { if (this.onSendMessage) this.onSendMessage(t) }
            }).layoutWeight(1)
          }
          .width('100%').height('100%')
        }
        .showSideBar(this.showDrawer)
        .showControlButton(false)
        .sideBarWidth('100%')
        .maxSideBarWidth('100%')
        .width('100%').height('100%')

        // Picker overlay
        if (this.showPicker) {
          Column() {
            Row().width('100%').layoutWeight(1)
              .onClick(() => { this.showPicker = false })

            PickerSheet({
              pickerMode: this.pickerMode,
              pickerTitle: this.pickerTitle,
              onSelect: (index: number) => { this.doPickerSelect(index) }
            })
            .width('100%')
            .constraintSize({ maxHeight: '70%' })
          }
          .width('100%').height('100%')
          .backgroundColor('#33000000')
          .zIndex(100)
          .transition(TransitionEffect.OPACITY)
        }
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 30 })))
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }

  @Builder
  TitleBar() {
    Row() {
      SymbolGlyph(this.showDrawer ? $r('sys.symbol.close_sidebar') : $r('sys.symbol.open_sidebar'))
        .fontSize(24)
        .fontColor([Colors.foreground])
        .onClick(() => { this.getUIContext()?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = !this.showDrawer }) })

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
        .bindMenu([
          { value: 'Switch Session', action: () => { this.openPicker(0) } },
          { value: 'Switch Model', action: () => { this.openPicker(1) } },
          { value: 'Switch Agent Mode', action: () => { this.openPicker(2) } },
        ])
    }
    .width('100%').height(56) // 固定的标题栏高度
    .padding({ left: Spacing.lg, right: Spacing.lg })
    .backgroundColor(Colors.surfaceElevated) // 给标题栏加个背景色，以防被内容遮挡
  }
}

@Component
struct PickerSheet {
  private pickerMode: number = -1;
  private pickerTitle: string = '';
  private onSelect?: (index: number) => void;

  build() {
    Column() {
      Row() {
        Text(this.pickerTitle)
          .fontSize(FontSize.xl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
      }
      .width('100%')
      .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.xl, bottom: Spacing.lg })

      if (this.getItems().length === 0) {
        Row() {
          LoadingProgress().width(20).height(20).color(Colors.accent)
        }
        .width('100%').height(80)
        .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      } else {
        List() {
          ForEach(this.getItems(), (item: string, index: number) => {
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
              if (this.onSelect) this.onSelect(index);
            })
          }, (item: string) => item)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ bottom: Spacing.xxxl })
    .backgroundColor(Colors.surface0)
    .borderRadius({ topLeft: Radius.xl, topRight: Radius.xl })
  }

  getItems(): string[] {
    if (this.pickerMode === 0) {
      let result: string[] = [];
      for (let j = 0; j < ChatStore.sessions.length; j++) {
        let title = ChatStore.sessions[j].title || ChatStore.sessions[j].sessionId.substring(0, 8);
        if (title.length > 30) title = title.substring(0, 30) + '\u2026';
        result.push(title);
      }
      return result;
    }
    if (this.pickerMode === 1) return ChatStore.models.map(m => m.name);
    if (this.pickerMode === 2) return ChatStore.modes.map(m => m.name);
    return [];
  }
}
