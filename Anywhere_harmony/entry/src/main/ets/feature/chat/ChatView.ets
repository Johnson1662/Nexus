import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
import { ChatStore, PendingPermission, PermissionOption } from '../../common/model/ChatState';
import { WorkspaceStore } from '../../common/model/WorkspaceInfo';
import { WorkspaceInfo } from '../../common/model/WorkspaceInfo';
import { StorageService, saveWorkspaces } from '../../services/StorageService';
import { ChatPage } from './ChatPage';
import { WorkspaceDrawer } from '../workspace/WorkspaceDrawer';

@Component
export struct ChatView {
  @State showDrawer: boolean = false;
  @State showPathInput: boolean = false;
  @State newPath: string = '';
  @State showPicker: boolean = false;
  @State pickerTitle: string = '';
  @State pickerMode: number = -1;
  @State titleBarOpacity: number = 0;
  @State showRename: boolean = false;
  @State renameText: string = '';
  onSendMessage?: (text: string) => void;
  onRetry?: (id: string, content: string) => void;
  onSwitchModel?: (index: number) => void;
  onSwitchMode?: (index: number) => void;
  onNewSession?: () => void;
  onSelectSession?: (i: number) => void;
  onWorkspaceSelect?: (index: number) => void;
  onPermissionResponse?: (optionId: string) => void;
  onNavigateToOnboarding?: () => void;
  onNavigateToSettings?: () => void;
  onNavigateToHostManage?: () => void;

  aboutToAppear(): void {
    if (WorkspaceStore.currentIndex < 0) {
      setTimeout(() => { this.showDrawer = true; }, 200);
    }
    if (WorkspaceStore.currentIndex >= 0 && this.onWorkspaceSelect) {
      this.onWorkspaceSelect(WorkspaceStore.currentIndex);
    }
    setTimeout(() => {
      this.titleBarOpacity = 1;
    }, 50);
  }

  getSessionTitle(): string {
    if (!ChatStore.bridgeSessionId && !ChatStore.acpSessionId) {
      return 'New Session';
    }
    // Prefer the live sessionTitle from server updates
    if (ChatStore.sessionTitle.length > 0) {
      return ChatStore.sessionTitle;
    }
    let targetId = ChatStore.acpSessionId || ChatStore.bridgeSessionId;
    for (let i = 0; i < ChatStore.sessions.length; i++) {
      if (ChatStore.sessions[i].sessionId === targetId) {
        return ChatStore.sessions[i].title || ChatStore.sessions[i].sessionId.substring(0, 8);
      }
    }
    if (targetId.length > 0) {
      return targetId.substring(0, 8);
    }
    return 'Session';
  }

  getModelName(): string {
    if (ChatStore.modelIndex >= 0 && ChatStore.modelIndex < ChatStore.models.length) {
      return ChatStore.models[ChatStore.modelIndex].name;
    }
    return '';
  }



  /** Create and persist a new workspace in the global store. */
  static addWorkspace(path: string): WorkspaceInfo {
    let ws = new WorkspaceInfo();
    ws.id = Date.now().toString();
    ws.name = path.split('\\').pop() || path.split('/').pop() || 'Project';
    ws.path = path;
    WorkspaceStore.workspaces.push(ws);
    WorkspaceStore.currentIndex = WorkspaceStore.workspaces.length - 1;
    saveWorkspaces(AppStorage.get<string>('serverUrl') || '');
    return ws;
  }

  doRename(): void {
    this.showRename = false;
    let newTitle = this.renameText.trim();
    if (newTitle.length === 0) return;
    ChatStore.sessionTitle = newTitle;
    // Update local sessions array
    let targetId = ChatStore.acpSessionId || ChatStore.bridgeSessionId;
    for (let i = 0; i < ChatStore.sessions.length; i++) {
      if (ChatStore.sessions[i].sessionId === targetId) {
        ChatStore.sessions[i].title = newTitle;
        break;
      }
    }
  }
  openPicker(mode: number): void {
    if (mode === 0) {
      this.pickerTitle = getContext().resourceManager.getStringSync($r('app.string.picker_sessions'));
    } else if (mode === 1) {
      this.pickerTitle = getContext().resourceManager.getStringSync($r('app.string.picker_models'));
    } else if (mode === 2) {
      this.pickerTitle = getContext().resourceManager.getStringSync($r('app.string.picker_modes'));
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

  showDeleteConfirmDialog(index: number) {
    let wsName = WorkspaceStore.workspaces[index]?.name || '';
    this.getUIContext().showAlertDialog({
      title: getContext().resourceManager.getStringSync($r('app.string.ws_delete_confirm_title')),
      message: wsName,
      primaryButton: {
        value: getContext().resourceManager.getStringSync($r('app.string.ws_cancel')),
        action: () => {}
      },
      secondaryButton: {
        value: getContext().resourceManager.getStringSync($r('app.string.ws_delete_confirm_ok')),
        fontColor: Colors.error,
        action: () => {
          WorkspaceStore.workspaces.splice(index, 1);
          if (WorkspaceStore.currentIndex >= WorkspaceStore.workspaces.length) {
            WorkspaceStore.currentIndex = WorkspaceStore.workspaces.length - 1;
          }
          saveWorkspaces(AppStorage.get<string>('serverUrl') || '');
        }
      }
    });
  }

  @Builder
  PickerSheetBuilder() {
    PickerSheet({
      pickerMode: this.pickerMode,
      pickerTitle: this.pickerTitle,
      onSelect: (index: number) => { this.doPickerSelect(index) }
    })
  }

  @Builder
  PermissionSheetBuilder() {
    PermissionSheet({
      permission: ChatStore.pendingPermission,
      onSelect: (optionId: string) => {
        if (this.onPermissionResponse) this.onPermissionResponse(optionId);
      }
    })
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
              this.showDeleteConfirmDialog(i);
            },
            onClose: () => { this.getUIContext()?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = false }) },
            onAddWorkspace: (p: string) => {
              ChatView.addWorkspace(p);
              this.getUIContext()?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = false });
              if (this.onWorkspaceSelect) this.onWorkspaceSelect(WorkspaceStore.workspaces.length - 1);
            },
            onSwitchHost: () => { if (this.onNavigateToOnboarding) this.onNavigateToOnboarding() },
            onSettings: () => { if (this.onNavigateToSettings) this.onNavigateToSettings() },
            onHostManage: () => { if (this.onNavigateToHostManage) this.onNavigateToHostManage() }
          })

          Column() {
            Column() {
              this.TitleBar()
            }
            .opacity(this.titleBarOpacity)
            .animation({ duration: Duration.slow, curve: Curve.EaseOut })

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
                      ChatView.addWorkspace(p);
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
              streamingThinking: ChatStore.streamingThinking,
              onSendMessage: (t: string) => { if (this.onSendMessage) this.onSendMessage(t) },
              onRetry: (id: string, content: string) => { if (this.onRetry) this.onRetry(id, content) }
            }).layoutWeight(1)
          }
          .width('100%').height('100%')
        }
          .bindSheet($$this.showPicker, this.PickerSheetBuilder(), {
            height: SheetSize.MEDIUM,
            dragBar: true,
            backgroundColor: Colors.surface0,
            showClose: false
          })
        .showSideBar(this.showDrawer)
        .showControlButton(false)
        .sideBarWidth('100%')
        .maxSideBarWidth('100%')
        .width('100%').height('100%')

        // Overlay elements are now handled natively via system dialogs and bindSheet.
      }
      .width('100%').height('100%')
    }
    .hideTitleBar(true)
    .bindSheet(ChatStore.pendingPermission !== null, this.PermissionSheetBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      backgroundColor: Colors.surface0,
      showClose: false,
      onDisappear: () => {
        if (ChatStore.pendingPermission !== null && this.onPermissionResponse) {
          this.onPermissionResponse('reject_once');
        }
      }
    })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }
  @Builder
  TitleBar() {
    Row() {
      SymbolGlyph(this.showDrawer ? $r('sys.symbol.close_sidebar') : $r('sys.symbol.open_sidebar'))
        .fontSize(24)
        .fontColor([Colors.foreground])
        .accessibilityText(this.showDrawer ? 'Close workspace drawer' : 'Open workspace drawer')
        .onClick(() => { this.getUIContext()?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = !this.showDrawer }) })

      Column() {
        if (this.showRename) {
          Row() {
            TextInput({ text: this.renameText, placeholder: 'Session name' })
              .layoutWeight(1).height(36)
              .backgroundColor(Colors.surface1).borderRadius(Radius.sm)
              .padding({ left: Spacing.md, right: Spacing.md })
              .fontSize(FontSize.base).fontColor(Colors.foreground).fontWeight(FontWeight.Medium)
              .onChange((v: string) => { this.renameText = v })
              .onSubmit(() => { this.doRename() })

            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(16).fontColor([Colors.foregroundMuted])
              .margin({ left: Spacing.xs })
              .onClick(() => { this.showRename = false })
          }
          .width('100%')
        } else {
          Row() {
            Text(this.getSessionTitle())
              .fontSize(FontSize.base).fontColor(Colors.foreground).fontWeight(FontWeight.Medium)
              .lineHeight(20).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })


          }
          .width('100%')
          .onClick(() => {
            if (ChatStore.bridgeSessionId || ChatStore.acpSessionId) {
              this.renameText = this.getSessionTitle();
              this.showRename = true;
            }
          })
        }

        if (!ChatStore.bridgeSessionId && !ChatStore.acpSessionId) {
          Text($r('app.string.chat_no_session'))
            .fontSize(FontSize.xs).fontColor(Colors.foregroundLight)
            .lineHeight(16).maxLines(1)
            .width('100%')
            .accessibilityText('No active session')
        } else if (ChatStore.models.length > 0) {
          Text(this.getModelName())
            .fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
            .lineHeight(16).maxLines(1)
            .width('100%')
            .accessibilityText('Current model: ' + this.getModelName())
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Spacing.sm })

      SymbolGlyph($r('sys.symbol.plus'))
        .fontColor([Colors.foreground]).fontSize(24).margin({ right: Spacing.md })
        .accessibilityText('New chat')
        .onClick(() => { if (this.onNewSession) this.onNewSession() })

      SymbolGlyph($r('sys.symbol.dot_grid_2x2'))
        .fontColor([Colors.foreground]).fontSize(24)
        .accessibilityText('More options')
        .bindMenu([
          { value: $r('app.string.menu_switch_session'), action: () => { this.openPicker(0) } },
          { value: 'Rename Session', action: () => {
              if (ChatStore.bridgeSessionId || ChatStore.acpSessionId) {
                this.renameText = this.getSessionTitle();
                this.showRename = true;
              }
            }
          },
          { value: $r('app.string.menu_switch_model'), action: () => { this.openPicker(1) } },
          { value: $r('app.string.menu_switch_mode'), action: () => { this.openPicker(2) } },
        ])
    }
    .width('100%').height(56)
    .padding({ left: Spacing.lg, right: Spacing.lg })
    .backgroundColor(Colors.surfaceElevated)
    .shadow({ radius: 2, color: '#0000000A', offsetY: 1 })
  }
}

@Component
struct PermissionSheet {
  @Prop permission: PendingPermission | null = null;
  onSelect?: (optionId: string) => void;

  build() {
    Column() {
      Row() {
        Text($r('app.string.perm_title'))
          .fontSize(FontSize.xl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
          .accessibilityText('Permission request')
      }
      .width('100%')
      .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.xl, bottom: Spacing.md })

      if (this.permission) {
        Text(this.permission.toolCall.title)
          .fontSize(FontSize.base).fontColor(Colors.foregroundMuted)
          .width('100%')
          .padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.lg })

        List() {
          ForEach(this.permission.options, (opt: PermissionOption) => {
            ListItem() {
              Row() {
                Text(opt.name)
                  .fontSize(FontSize.base).fontColor(Colors.foreground)
                  .padding({ top: Spacing.md, bottom: Spacing.md, left: Spacing.md, right: Spacing.md })
              }
              .width('100%')
            }
            .width('100%').borderRadius(Radius.md)
            .backgroundColor(Colors.surface1)
            .margin({ bottom: Spacing.xs, left: Spacing.md, right: Spacing.md })
            .onClick(() => {
              if (this.onSelect) this.onSelect(opt.optionId);
            })
          }, (opt: PermissionOption) => opt.optionId)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ bottom: Spacing.xxxl })
    .backgroundColor(Colors.surface0)
    .borderRadius({ topLeft: Radius.xl, topRight: Radius.xl })
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
  }
}

@Component
struct PickerSheet {
  @Prop pickerMode: number = -1;
  @Prop pickerTitle: string = '';
  onSelect?: (index: number) => void;

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
          Text('暂无数据')
            .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
        }
        .width('100%').height(80).justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.getItems(), (item: string, index: number) => {
            ListItem() {
              Row() {
                Text(item)
                  .fontSize(FontSize.base)
                  .fontColor(index === this.getCurrentIndex() ? Colors.accent : Colors.foreground)
                  .fontWeight(index === this.getCurrentIndex() ? FontWeight.Medium : FontWeight.Normal)
                  .layoutWeight(1)
                if (index === this.getCurrentIndex()) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(16).fontColor([Colors.accent])
                    .margin({ left: Spacing.sm })
                    .accessibilityText('Currently selected')
                }
              }
              .width('100%')
              .padding({ top: Spacing.md, bottom: Spacing.md, left: Spacing.md, right: Spacing.md })
            }
            .width('100%').borderRadius(Radius.md)
            .backgroundColor(index === this.getCurrentIndex() ? Colors.accentLight : Colors.surface1)
            .margin({ bottom: Spacing.xs })
            .accessibilityText(item + (index === this.getCurrentIndex() ? ', selected' : ''))
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
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
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

  getCurrentIndex(): number {
    if (this.pickerMode === 0) {
      let targetId = ChatStore.acpSessionId || ChatStore.bridgeSessionId;
      for (let j = 0; j < ChatStore.sessions.length; j++) {
        if (ChatStore.sessions[j].sessionId === targetId) return j;
      }
      return -1;
    }
    if (this.pickerMode === 1) return ChatStore.modelIndex;
    if (this.pickerMode === 2) return ChatStore.modeIndex;
    return -1;
  }
}