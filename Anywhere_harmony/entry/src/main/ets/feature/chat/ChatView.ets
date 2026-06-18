import { Colors, FontSize, Spacing, Radius, Duration, Layout, Shadow, getLocalizedString } from '../../constants/DesignTokens';
import { ChatStore, PendingPermission, PermissionOption } from '../../common/model/ChatState';
import { CustomIcon } from '../../common/ui/CustomIcon';
import { WorkspaceStore, WorkspaceInfo, HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { HostRuntimeStore } from '../../common/model/HostState';
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
  @State showRename: boolean = false;
  @State renameText: string = '';
  @State showWorkspacePicker: boolean = false;
  @State pickerShowPathInput: boolean = false;
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
  onPrefetchModels?: () => void;
  onRefreshSessions?: () => void;
  onPermissionResponse?: (optionId: string) => void;
  onNavigateToSettings?: () => void;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  aboutToAppear(): void {
    if (WorkspaceStore.currentIndex < 0 && WorkspaceStore.workspaces.length > 0) {
      WorkspaceStore.currentIndex = 0;
    }
    let needPick: boolean = AppStorage.get<boolean>('chatShowWorkspacePicker') || false;
    AppStorage.setOrCreate('chatShowWorkspacePicker', false);
    if (needPick || WorkspaceStore.currentIndex < 0) {
      this.showWorkspacePicker = true;
    }
    if (!this.showWorkspacePicker && WorkspaceStore.currentIndex >= 0 && this.onWorkspaceSelect) {
      this.onWorkspaceSelect(WorkspaceStore.currentIndex);
    }
    if (this.onPrefetchModels) {
      setTimeout(() => { this.onPrefetchModels?.(); }, 1000);
    }
  }

  getSessionTitle(): string {
    if (!ChatStore.bridgeSessionId && !ChatStore.acpSessionId) {
      return this.text($r('app.string.chat_new_session'));
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
    return this.text($r('app.string.chat_session_fallback'));
  }

  getModelName(): string {
    if (ChatStore.modelIndex >= 0 && ChatStore.modelIndex < ChatStore.models.length) {
      return ChatStore.models[ChatStore.modelIndex].name;
    }
    return '';
  }

  getWorkspaceHostLabel(): string {
    let parts: string[] = [];
    if (WorkspaceStore.currentIndex >= 0 && WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length) {
      parts.push(WorkspaceStore.workspaces[WorkspaceStore.currentIndex].name);
    }
    let hostKey: string = HostRuntimeStore.activeHostKey;
    if (hostKey.length > 0 && HostRuntimeStore.isOnline(hostKey)) {
      for (let i: number = 0; i < HostStore.devices.length; i++) {
        let device: DeviceEntry = HostStore.devices[i];
        if (device.hostId === hostKey || device.name === hostKey) {
          parts.push(device.name);
          break;
        }
      }
    }
    if (parts.length === 0) return '';
    return parts.join(' · ');
  }

  selectWorkspace(index: number): void {
    WorkspaceStore.currentIndex = index;
    this.showWorkspacePicker = false;
    this.pickerShowPathInput = false;
    if (this.onWorkspaceSelect) this.onWorkspaceSelect(index);
  }

  /** Create and persist a new workspace in the global store. */
  addWorkspace(path: string): WorkspaceInfo {
    let ws = new WorkspaceInfo();
    ws.id = Date.now().toString();
    ws.name = path.split('\\').pop() || path.split('/').pop() || this.text($r('app.string.workspace_project_fallback'));
    ws.path = path;
    WorkspaceStore.workspaces.push(ws);
    WorkspaceStore.currentIndex = WorkspaceStore.workspaces.length - 1;
    saveWorkspaces(AppStorage.get<string>('serverUrl') || '', ChatStore.currentDeviceId);
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
      this.pickerTitle = this.text($r('app.string.picker_sessions'));
    } else if (mode === 3) {
      this.pickerTitle = this.text($r('app.string.picker_agents'));
    } else if (mode === 1) {
      this.pickerTitle = this.text($r('app.string.picker_models'));
    } else if (mode === 2) {
      this.pickerTitle = this.text($r('app.string.picker_modes'));
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
    (this.getUIContext()).showAlertDialog({
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
          saveWorkspaces(AppStorage.get<string>('serverUrl') || '', ChatStore.currentDeviceId);
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
              (this.getUIContext())?.animateTo({ duration: 150 }, () => { this.showDrawer = false });
              if (this.onWorkspaceSelect) this.onWorkspaceSelect(i);
            },
            onDelete: (i: number) => {
              this.showDeleteConfirmDialog(i);
            },
            onClose: () => { (this.getUIContext())?.animateTo({ duration: 150 }, () => { this.showDrawer = false }) },
            onAddWorkspace: (p: string) => {
              this.addWorkspace(p);
              (this.getUIContext())?.animateTo({ duration: 150 }, () => { this.showDrawer = false });
              if (this.onWorkspaceSelect) this.onWorkspaceSelect(WorkspaceStore.workspaces.length - 1);
            },

          })

          Column() {
            if (this.showPathInput) {
              Row() {
                TextInput({ placeholder: $r('app.string.ws_path_placeholder'), text: this.newPath })
                  .layoutWeight(1).height(36)
                  .backgroundColor(Colors.surface1).borderRadius(Radius.sm)
                  .padding({ left: Spacing.md, right: Spacing.md })
                  .fontSize(FontSize.xs)
                  .onChange((v: string) => { this.newPath = v })
                Button($r('app.string.ws_add')).height(36).backgroundColor(Colors.accent).fontColor(Colors.surface0)
                  .borderRadius(Radius.sm).fontSize(FontSize.xs)
                  .onClick(() => {
                    let p = this.newPath.trim();
                    if (p.length > 0) {
                      this.addWorkspace(p);
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
        .showSideBar(this.showDrawer)
        .showControlButton(false)
        .sideBarWidth('100%')
        .maxSideBarWidth('100%')
        .width('100%').height('100%')

        // Workspace picker overlay — centered card
        Stack({ alignContent: Alignment.Center }) {
          // Tap-to-dismiss backdrop
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.3)')
            .onClick(() => { this.showWorkspacePicker = false; })

          // Card
          Column() {
            if (WorkspaceStore.workspaces.length === 0) {
              Text($r('app.string.ws_empty_prompt'))
                .fontSize(FontSize.sm)
                .fontColor(Colors.foregroundMuted)
                .width('100%')
                .padding(Spacing.lg)
            } else {
              Scroll() {
                Column() {
                  ForEach(WorkspaceStore.workspaces, (workspace: WorkspaceInfo, index: number) => {
                    this.PickerWorkspaceRow(workspace, index)
                  }, (workspace: WorkspaceInfo) => workspace.id)
                }
                .width('100%')
              }
              .scrollBar(BarState.Off)
              .constraintSize({ maxHeight: '40%' })
              .width('100%')
            }

            if (this.pickerShowPathInput) {
              Row() {
                TextInput({ placeholder: $r('app.string.ws_path_placeholder'), text: this.newPath })
                  .layoutWeight(1).height(36)
                  .backgroundColor(Colors.surface1).borderRadius(Radius.sm)
                  .padding({ left: Spacing.md, right: Spacing.md })
                  .fontSize(FontSize.xs)
                  .onChange((v: string) => { this.newPath = v })
                Button($r('app.string.ws_add')).height(36).backgroundColor(Colors.accent).fontColor(Colors.surface0)
                  .borderRadius(Radius.sm).fontSize(FontSize.xs)
                  .onClick(() => {
                    let p = this.newPath.trim();
                    if (p.length > 0) {
                      this.addWorkspace(p);
                      this.newPath = '';
                      this.pickerShowPathInput = false;
                      this.selectWorkspace(WorkspaceStore.workspaces.length - 1);
                    }
                  })
              }
              .width('100%')
              .padding({ top: Spacing.sm, bottom: Spacing.sm, left: Spacing.md, right: Spacing.md })
            } else {
              Row() {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(14)
                  .fontColor([Colors.foregroundMuted])
                  .margin({ right: Spacing.xs })
                Text($r('app.string.ws_add_button'))
                  .fontSize(FontSize.sm)
                  .fontColor(Colors.foregroundMuted)
              }
              .width('100%')
              .padding({ top: Spacing.sm, bottom: Spacing.md, left: Spacing.md, right: Spacing.md })
              .onClick(() => { this.pickerShowPathInput = true })
            }
          }
          .width('85%')
          .constraintSize({ maxHeight: '55%' })
          .backgroundColor(Colors.surface0)
          .borderRadius(Radius.xl)
          .padding({ top: Spacing.sm, bottom: Spacing.sm })
          .shadow(Shadow.md)
        }
        .width('100%')
        .height('100%')
        .visibility(this.showWorkspacePicker ? Visibility.Visible : Visibility.Hidden)
        .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))

      }
      .width('100%').height('100%')
    }
    .title({ main: this.getSessionTitle(), sub: this.getWorkspaceHostLabel() })
    .bindSheet($$this.showPicker, this.PickerSheetBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      backgroundColor: Colors.surface0,
      showClose: false
    })
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
    .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
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
    .stateStyles({
      pressed: {
        .backgroundColor(Colors.surface2)
      },
      normal: {
        .backgroundColor(Colors.surface1)
      }
    })
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onClick(action)
  }

  @Builder
  PickerWorkspaceRow(workspace: WorkspaceInfo, index: number) {
    Row() {
      SymbolGlyph($r('sys.symbol.folder'))
        .fontSize(16)
        .fontColor([Colors.foreground])
        .margin({ right: Spacing.sm })

      Text(workspace.name)
        .fontSize(FontSize.sm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.foreground)
        .maxLines(1)
        .layoutWeight(1)

      if (WorkspaceStore.currentIndex === index) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(18)
          .fontColor([Colors.foreground])
      } else {
        SymbolGlyph($r('sys.symbol.circle'))
          .fontSize(18)
          .fontColor([Colors.border])
      }
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
    .backgroundColor(Colors.transparent)
    .onClick(() => { this.selectWorkspace(index); })
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
  }
}

@Component
struct PermissionSheet {
  @Prop permission: PendingPermission | null = null;
  onSelect?: (optionId: string) => void;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.perm_title'))
          .fontSize(FontSize.xl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
          .accessibilityText($r('app.string.accessibility_permission_request'))
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
            .stateStyles({
              pressed: { .backgroundColor(Colors.surface2) },
              normal: { .backgroundColor(Colors.surface1) }
            })
            .animation({ duration: Duration.fast, curve: Curve.EaseOut })
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
    .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
  }
}

@Component
struct PickerSheet {
  @Prop pickerMode: number = -1;
  @Prop pickerTitle: string = '';
  onSelect?: (index: number) => void;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

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
          Text($r('app.string.empty_no_data'))
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
                    .accessibilityText($r('app.string.accessibility_currently_selected'))
                }
              }
              .width('100%')
              .padding({ top: Spacing.md, bottom: Spacing.md, left: Spacing.md, right: Spacing.md })
            }
            .width('100%').borderRadius(Radius.md)
            .backgroundColor(index === this.getCurrentIndex() ? Colors.accentLight : Colors.surface1)
            .stateStyles({
              pressed: { .backgroundColor(index === this.getCurrentIndex() ? Colors.accentLight : Colors.surface2) },
              normal: { .backgroundColor(index === this.getCurrentIndex() ? Colors.accentLight : Colors.surface1) }
            })
            .animation({ duration: Duration.fast, curve: Curve.EaseOut })
            .margin({ bottom: Spacing.xs })
            .accessibilityText(index === this.getCurrentIndex() ?
              this.text($r('app.string.accessibility_selected_item'), item) : item)
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
    .transition(TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut }))
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
