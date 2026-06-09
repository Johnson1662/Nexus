import { Colors, FontSize, Spacing, Radius, Duration, Layout, getLocalizedString } from '../../constants/DesignTokens';
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
  @State showRename: boolean = false;
  @State renameText: string = '';
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
    if (WorkspaceStore.currentIndex < 0) {
      setTimeout(() => { this.showDrawer = true; }, 200);
    }
    if (WorkspaceStore.currentIndex >= 0 && this.onWorkspaceSelect) {
      this.onWorkspaceSelect(WorkspaceStore.currentIndex);
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



  /** Create and persist a new workspace in the global store. */
  addWorkspace(path: string): WorkspaceInfo {
    let ws = new WorkspaceInfo();
    ws.id = Date.now().toString();
    ws.name = path.split('\\').pop() || path.split('/').pop() || this.text($r('app.string.workspace_project_fallback'));
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
              this.addWorkspace(p);
              (this.getUIContext() as UIContext)?.animateTo({ duration: Duration.normal }, () => { this.showDrawer = false });
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

      }
      .width('100%').height('100%')
    }
    .title(this.getSessionTitle())
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
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }

  @Builder
  ControlBar() {
    Column() {
      Row({ space: Spacing.xs }) {
        this.ControlChip(this.text($r('app.string.config_agent')),
          ChatStore.selectedAgentName || this.text($r('app.string.config_select_agent')), () => {
          this.openPicker(3);
        })
        this.ControlChip(this.text($r('app.string.config_model')),
          this.getModelName().length > 0 ? this.getModelName() : this.text($r('app.string.config_select_model')), () => {
          if ((ChatStore.selectedAgentName || ChatStore.agentType).length > 0) {
            this.openPicker(1);
          }
        }, (ChatStore.selectedAgentName || ChatStore.agentType).length > 0)
        this.ControlChip(this.text($r('app.string.config_mode')), ChatStore.modeIndex >= 0 && ChatStore.modeIndex < ChatStore.modes.length
          ? ChatStore.modes[ChatStore.modeIndex].name : this.text($r('app.string.config_select_mode')), () => {
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
    .stateStyles({
      pressed: {
        .scale({ x: 0.98, y: 0.98 })
        .backgroundColor(Colors.surface2)
      },
      normal: {
        .scale({ x: 1, y: 1 })
        .backgroundColor(Colors.surface1)
      }
    })
    .animation({ duration: Duration.normal, curve: Duration.spring })
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
    .stateStyles({
      pressed: {
        .scale({ x: 0.95, y: 0.95 })
        .backgroundColor(Colors.surface2)
      },
      normal: {
        .scale({ x: 1, y: 1 })
        .backgroundColor(Colors.surface1)
      }
    })
    .animation({ duration: Duration.normal, curve: Duration.spring })
    .onClick(action)
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
    .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 20 })))
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
