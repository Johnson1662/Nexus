import { Colors, FontSize, Spacing, Radius, Duration, Layout, Shadow, getLocalizedString, AnimationPresets } from '../../constants/DesignTokens';
import { ChatStore, PendingPermission, PermissionOption } from '../../common/model/ChatState';
import { WorkspaceStore, WorkspaceInfo, HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { HostRuntimeStore } from '../../common/model/HostState';
import { StorageService, saveWorkspaces } from '../../services/StorageService';
import { ChatPage } from './ChatPage';
import { ChatInputBar } from './ChatInputBar';
@Component
export struct ChatView {
  @State showPathInput: boolean = false;
  @State newPath: string = '';
  @State showPicker: boolean = false;
  @State pickerTitle: string = '';
  @State pickerMode: number = -1;
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
    if (hostKey.length === 0 && ChatStore.currentDeviceId.length > 0) {
      hostKey = ChatStore.currentDeviceId;
    }
    if (hostKey.length > 0) {
      let hostName: string = '';
      for (let i: number = 0; i < HostStore.devices.length; i++) {
        let device: DeviceEntry = HostStore.devices[i];
        if (device.hostId === hostKey || device.name === hostKey) {
          hostName = device.name;
          break;
        }
      }
      if (hostName.length === 0) {
        hostName = hostKey;
      }
      if (parts.length === 0 || parts[parts.length - 1] !== hostName) {
        parts.push(hostName);
      }
    }
    if (parts.length === 0) {
      return '';
    }
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
              .margin({ left: Spacing.xl, right: Spacing.xl })
              .padding({ top: Spacing.xs, bottom: Spacing.xs })
              .backgroundColor(Colors.surfaceElevated)
              .borderRadius(Radius.md)
              .transition(AnimationPresets.fadeIn)
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
            .margin({ bottom: 10 })
          }
          .width('100%').height('100%')
          .alignItems(HorizontalAlign.Center)

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
              Button({ type: ButtonType.Normal }) {
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
              }
              .width('100%')
              .backgroundColor(Color.Transparent)
              .stateStyles({
                pressed: { .backgroundColor(Colors.surface1) },
                normal: { .backgroundColor(Color.Transparent) }
              })
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
        .transition(AnimationPresets.fadeIn)

      }
      .width('100%').height('100%')
    }
    .title(this.ChatTitle())
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
    .transition(AnimationPresets.fadeIn)
    .width('100%').height('100%')
    .backgroundColor(Colors.surface1)
  }

  @Builder
  ChatTitle() {
    Column({ space: 0 }) {
      Text(this.getSessionTitle())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
      
      Row({ space: 4 }) {
        // 在线状态指示器：根据连接状态展示小绿点
        Circle()
          .width(6)
          .height(6)
          .fill(ChatStore.connected ? Colors.success : Colors.foregroundLight)
        Text(this.getWorkspaceHostLabel())
          .fontSize(10)
          .fontColor(Colors.foregroundMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(VerticalAlign.Center)
      .margin({ top: 3 })
      .padding({ left: 10, right: 10, top: 2, bottom: 2 })
      .backgroundColor(Colors.surface2)
      .borderRadius(Radius.full)
      .visibility(this.getWorkspaceHostLabel().length > 0 ? Visibility.Visible : Visibility.None)
    }
    .alignItems(HorizontalAlign.Center)
    .constraintSize({ maxWidth: '65%' })
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
    .animation({ duration: 150, curve: AnimationPresets.spring })
    .onClick(action)
  }

  @Builder
  PickerWorkspaceRow(workspace: WorkspaceInfo, index: number) {
    Button({ type: ButtonType.Normal }) {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(16)
          .fontColor([Colors.foregroundMuted])
          .margin({ right: Spacing.sm })

        Text(workspace.name)
          .fontSize(FontSize.base)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .maxLines(1)
          .layoutWeight(1)

        if (WorkspaceStore.currentIndex === index) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([Colors.accent])
        }
      }
      .width('100%')
      .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
    }
    .width('100%')
    .backgroundColor(Color.Transparent)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Color.Transparent) }
    })
    .onClick(() => { this.selectWorkspace(index); })
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
              Button({ type: ButtonType.Normal }) {
                Row() {
                  Text(opt.name)
                    .fontSize(FontSize.base)
                    .fontColor(Colors.foreground)
                    .padding({ top: Spacing.md, bottom: Spacing.md, left: Spacing.md, right: Spacing.md })
                }
                .width('100%')
              }
              .width('100%')
              .borderRadius(Radius.md)
              .backgroundColor(Colors.surface1)
              .stateStyles({
                pressed: { .backgroundColor(Colors.surface2) },
                normal: { .backgroundColor(Colors.surface1) }
              })
              .animation({ duration: Duration.fast, curve: AnimationPresets.spring })
              .onClick(() => {
                if (this.onSelect) this.onSelect(opt.optionId);
              })
            }
            .width('100%')
            .margin({ bottom: Spacing.sm })
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
    .transition(AnimationPresets.fadeIn)
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
              Button({ type: ButtonType.Normal }) {
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
              .width('100%')
              .borderRadius(Radius.md)
              .backgroundColor(index === this.getCurrentIndex() ? Colors.accentLight : Colors.surface1)
              .stateStyles({
                pressed: { .backgroundColor(index === this.getCurrentIndex() ? Colors.accentLight : Colors.surface2) },
                normal: { .backgroundColor(index === this.getCurrentIndex() ? Colors.accentLight : Colors.surface1) }
              })
              .animation({ duration: Duration.fast, curve: AnimationPresets.spring })
              .accessibilityText(index === this.getCurrentIndex() ?
                this.text($r('app.string.accessibility_selected_item'), item) : item)
              .onClick(() => {
                if (this.onSelect) this.onSelect(index);
              })
            }
            .width('100%')
            .margin({ bottom: Spacing.sm })
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
    .transition(AnimationPresets.fadeIn)
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
