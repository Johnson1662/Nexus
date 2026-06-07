import { Colors, FontSize, Spacing, Radius, Duration, Layout } from '../../constants/DesignTokens';
import { ChatStore, PendingPermission, PermissionOption } from '../../common/model/ChatState';
import { CustomIcon } from '../../common/ui/CustomIcon';
import { WorkspaceStore } from '../../common/model/WorkspaceInfo';
import { WorkspaceInfo } from '../../common/model/WorkspaceInfo';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { StorageService, saveWorkspaces } from '../../services/StorageService';
import { ChatPage } from './ChatPage';
import { ChatInputBar } from './ChatInputBar';
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
  @State showMoreMenu: boolean = false;
  onSendMessage?: (text: string) => void;
  onRetry?: (id: string, content: string) => void;
  onSelectAgent?: (index: number) => void;
  onSwitchModel?: (index: number) => void;
  onSwitchMode?: (index: number) => void;
  onNewSession?: () => void;
  onSelectSession?: (i: number) => void;
  onWorkspaceSelect?: (index: number) => void;
  onRefreshAgents?: () => void;
  onRefreshModels?: () => void;
  onRefreshSessions?: () => void;
  onPermissionResponse?: (optionId: string) => void;
  onBack?: () => void;
  onNavigateToSettings?: () => void;
  onNavigateToHostManage?: () => void;

  aboutToAppear(): void {
    if (WorkspaceStore.currentIndex < 0 && WorkspaceStore.workspaces.length > 0) {
      WorkspaceStore.currentIndex = 0;
    }
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
      this.pickerTitle = getContext(this).resourceManager.getStringSync($r('app.string.picker_sessions').id);
    } else if (mode === 3) {
      this.pickerTitle = 'Agents';
    } else if (mode === 1) {
      this.pickerTitle = getContext(this).resourceManager.getStringSync($r('app.string.picker_models').id);
    } else if (mode === 2) {
      this.pickerTitle = getContext(this).resourceManager.getStringSync($r('app.string.picker_modes').id);
    }
    this.pickerMode = mode;
    this.showPicker = true;
  }

  doPickerSelect(index: number): void {
    this.showPicker = false;
    if (this.pickerMode === 0 && this.onSelectSession) {
      this.onSelectSession(index + 1);
    } else if (this.pickerMode === 3 && this.onSelectAgent) {
      this.onSelectAgent(index + 1);
    } else if (this.pickerMode === 1 && this.onSwitchModel) {
      this.onSwitchModel(index + 1);
    } else if (this.pickerMode === 2 && this.onSwitchMode) {
      this.onSwitchMode(index + 1);
    }
  }

  showDeleteConfirmDialog(index: number) {
    let wsName = WorkspaceStore.workspaces[index]?.name || '';
    (this.getUIContext() as UIContext).showAlertDialog({
      title: getContext(this).resourceManager.getStringSync($r('app.string.ws_delete_confirm_title').id),
      message: wsName,
      primaryButton: {
        value: getContext(this).resourceManager.getStringSync($r('app.string.ws_cancel').id),
        action: () => {}
      },
      secondaryButton: {
        value: getContext(this).resourceManager.getStringSync($r('app.string.ws_delete_confirm_ok').id),
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
            onSelect: (i: number) => {
              WorkspaceStore.currentIndex = i;
              (this.getUIContext() as UIContext)?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = false });
              if (this.onWorkspaceSelect) this.onWorkspaceSelect(i);
            },
            onDelete: (i: number) => {
              this.showDeleteConfirmDialog(i);
            },
            onClose: () => { (this.getUIContext() as UIContext)?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = false }) },
            onAddWorkspace: (p: string) => {
              ChatView.addWorkspace(p);
              (this.getUIContext() as UIContext)?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = false });
              if (this.onWorkspaceSelect) this.onWorkspaceSelect(WorkspaceStore.workspaces.length - 1);
            },
            onSwitchHost: () => { if (this.onNavigateToHostManage) this.onNavigateToHostManage() },
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
              .width(Layout.contentWidth)
              .padding({ top: Spacing.xs, bottom: Spacing.xs })
              .backgroundColor(Colors.surfaceElevated)
              .borderRadius(Radius.md)
              .transition(TransitionEffect.OPACITY)
            }

            ChatPage({
              messages: ChatStore.messages,
              streamingThinking: ChatStore.streamingThinking,
              onSendMessage: (t: string) => { if (this.onSendMessage) this.onSendMessage(t) },
              onRetry: (id: string, content: string) => { if (this.onRetry) this.onRetry(id, content) }
            }).layoutWeight(1)

            ChatInputBar({
              disabled: ChatStore.turnActive || ChatStore.loadingSession || ((ChatStore.selectedAgentName || ChatStore.agentType).length === 0),
              showCancel: ChatStore.turnActive,
              onSend: (text: string) => { if (this.onSendMessage) this.onSendMessage(text); },
              onCancel: () => { if (this.onSendMessage) this.onSendMessage('__cancel__'); },
              onSelectAgent: (i: number) => { if (this.onSelectAgent) this.onSelectAgent(i); },
              onSwitchModel: (i: number) => { if (this.onSwitchModel) this.onSwitchModel(i); },
              onSwitchMode: (i: number) => { if (this.onSwitchMode) this.onSwitchMode(i); },
              onRefreshAgents: () => { if (this.onRefreshAgents) this.onRefreshAgents(); },
              onRefreshModels: () => { if (this.onRefreshModels) this.onRefreshModels(); }
            })
          }
          .width('100%').height('100%')
          .alignItems(HorizontalAlign.Center)
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

        if (this.showMoreMenu) {
          this.MoreOverlay()
        }
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
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(20)
          .fontColor([Colors.foreground])
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.onBack?.(); })

      Blank()

      Button() {
        Row({ space: Spacing.sm }) {
          CustomIcon({ name: 'model', iconSize: 14, color: Colors.foreground })
          Text(WorkspaceStore.currentIndex >= 0 && WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length
            ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].name : 'New chat')
            .fontSize(FontSize.xs)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(11)
            .fontColor([Colors.foregroundMuted])
        }
      }
      .height(34)
      .padding({ left: Spacing.md, right: Spacing.sm })
      .constraintSize({ maxWidth: 178 })
      .backgroundColor(Colors.surface0)
      .border({ width: 1, color: Colors.borderLight })
      .borderRadius(Radius.full)
      .onClick(() => {
        (this.getUIContext() as UIContext)?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = true })
      })

      Blank()

      Button() {
        CustomIcon({ name: 'more', iconSize: 15, color: Colors.foreground })
      }
      .width(36)
      .height(36)
      .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.showMoreMenu = true
        })
    }
    .width('100%').height(56)
    .padding({ left: Spacing.xl, right: Spacing.xl })
    .backgroundColor(Colors.surface0)
  }

  @Builder
  ControlBar() {
    Column() {
      Row({ space: Spacing.xs }) {
        this.ControlChip('Agent', ChatStore.selectedAgentName || '选择 Agent', () => {
          this.openPicker(3);
        })
        this.ControlChip('Model', this.getModelName().length > 0 ? this.getModelName() : '选择 Model', () => {
          if ((ChatStore.selectedAgentName || ChatStore.agentType).length > 0) {
            this.openPicker(1);
          }
        }, (ChatStore.selectedAgentName || ChatStore.agentType).length > 0)
        this.ControlChip('Mode', ChatStore.modeIndex >= 0 && ChatStore.modeIndex < ChatStore.modes.length
          ? ChatStore.modes[ChatStore.modeIndex].name : '选择', () => {
            if (ChatStore.modes.length > 0) {
              this.openPicker(2);
            }
          }, ChatStore.modes.length > 0)
      }
      .width(Layout.contentWidth)
      .padding({ top: Spacing.xs, bottom: Spacing.sm })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Colors.surface0)
  }

  @Builder
  ControlChip(label: string, value: string, action: () => void, enabled: boolean = true) {
    Button() {
      Column() {
        Text(label)
          .fontSize(FontSize.xxs)
          .fontColor(Colors.foregroundMuted)
        Text(value)
          .fontSize(FontSize.xs)
          .fontColor(enabled ? Colors.foreground : Colors.foregroundMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
    }
    .enabled(enabled)
    .layoutWeight(1)
    .height(44)
    .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.xs, bottom: Spacing.xs })
    .backgroundColor(Colors.surface1)
    .borderRadius(Radius.md)
    .onClick(action)
  }

  @Builder
  IconChip(icon: Resource, action: () => void) {
    Button() {
      SymbolGlyph(icon).fontSize(18).fontColor([Colors.foreground])
    }
    .width(40)
    .height(40)
    .backgroundColor(Colors.surface1)
    .borderRadius(Radius.md)
    .onClick(action)
  }

  @Builder
  MoreSheetBuilder() {
    Column() {
      this.MenuAction('Refresh sessions', () => {
        this.showMoreMenu = false;
        this.onRefreshSessions?.();
      })
      this.MenuAction('Refresh agents', () => {
        this.showMoreMenu = false;
        this.onRefreshAgents?.();
      })
      this.MenuAction('Refresh models', () => {
        this.showMoreMenu = false;
        this.onRefreshModels?.();
      })
      this.MenuAction('Add host', () => {
        this.showMoreMenu = false;
        this.onNavigateToHostManage?.();
      })
      this.MenuAction('Settings', () => {
        this.showMoreMenu = false;
        this.onNavigateToSettings?.();
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(Spacing.xs)
    .backgroundColor(Colors.surface0)
    .borderRadius(Radius.xl)
    .shadow({ radius: 14, color: '#1A1D2314', offsetY: 8 })
  }

  @Builder
  MoreOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Colors.transparent)
        .onClick(() => { this.showMoreMenu = false; })
      Column() {
        this.MoreSheetBuilder()
      }
      .width(168)
      .margin({ top: 54, right: Spacing.xl })
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 })))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  MenuAction(label: string, action: () => void) {
    Button(label)
      .width('100%')
      .height(34)
      .fontSize(FontSize.xs)
      .fontColor(Colors.foreground)
      .backgroundColor(Colors.transparent)
      .borderRadius(Radius.sm)
      .onClick(action)
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
      .width(Layout.contentWidth)
      .padding({ top: Spacing.xl, bottom: Spacing.md })

      if (this.permission) {
        Text(this.permission.toolCall.title)
          .fontSize(FontSize.base).fontColor(Colors.foregroundMuted)
          .width(Layout.contentWidth)
          .padding({ bottom: Spacing.lg })

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
            .margin({ bottom: Spacing.xs })
            .onClick(() => {
              if (this.onSelect) this.onSelect(opt.optionId);
            })
          }, (opt: PermissionOption) => opt.optionId)
        }
        .width(Layout.contentWidth)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
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
      .width(Layout.contentWidth)
      .padding({ top: Spacing.xl, bottom: Spacing.lg })

      if (this.getItems().length === 0) {
        Row() {
          Text('暂无数据')
            .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
        }
        .width(Layout.contentWidth).height(80).justifyContent(FlexAlign.Center)
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
        .width(Layout.contentWidth)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
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
    if (this.pickerMode === 3) {
      let hostId: string = ChatStore.currentDeviceId;
      if (hostId.length === 0) {
        return [];
      }
      let agents = DeviceAgentStore.getAgents(hostId);
      let result: string[] = [];
      for (let i: number = 0; i < agents.length; i++) {
        result.push(agents[i].title || agents[i].name);
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
    if (this.pickerMode === 3) {
      let hostId: string = ChatStore.currentDeviceId;
      let agents = DeviceAgentStore.getAgents(hostId);
      for (let j = 0; j < agents.length; j++) {
        if (agents[j].name === (ChatStore.selectedAgentName || ChatStore.agentType)) return j;
      }
      return -1;
    }
    if (this.pickerMode === 1) return ChatStore.modelIndex;
    if (this.pickerMode === 2) return ChatStore.modeIndex;
    return -1;
  }
}
