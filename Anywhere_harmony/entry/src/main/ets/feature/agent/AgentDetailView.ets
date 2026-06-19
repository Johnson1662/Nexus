import { Colors, FontSize, Spacing, Radius, Layout, getLocalizedString } from '../../constants/DesignTokens';
import { HostStore, DeviceEntry, ServerSession } from '../../common/model/WorkspaceInfo';
import { ChatStore } from '../../common/model/ChatState';
import { HostPhase, HostRuntimeStore } from '../../common/model/HostState';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { AgentInfo } from '../../common/websocket/WSProtocol';

@Component
struct TabItem {
  @Prop itemKey: string;
  @Prop name: string;
  @Prop currentTab: string;
  onSelect?: () => void;
  @State bgColor: ResourceColor = Colors.transparent;

  build() {
    Column() {
      Text(this.name)
        .fontSize(FontSize.md)
        .fontWeight(this.currentTab === this.itemKey ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentTab === this.itemKey ? Colors.foreground : Colors.foregroundMuted)
        .padding({ bottom: Spacing.xs })
      if (this.currentTab === this.itemKey) {
        Divider().strokeWidth(2).color(Colors.foreground).width(24)
      } else {
        Divider().strokeWidth(2).color(Colors.transparent).width(24)
      }
    }
    .padding(Spacing.sm)
    .backgroundColor(this.bgColor)
    .borderRadius(Radius.md)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .onClick(() => { this.onSelect?.(); })
  }
}

@Component
export struct AgentDetailView {
  @Prop deviceIndex: number = 0;
  onBack?: () => void;
  @State currentTab: string = 'overview';
  @State backBg: ResourceColor = Colors.transparent;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  getDevice(): DeviceEntry | null {
    if (this.deviceIndex >= 0 && this.deviceIndex < HostStore.devices.length) {
      return HostStore.devices[this.deviceIndex];
    }
    return null;
  }

  getAgents(): AgentInfo[] {
    let d = this.getDevice();
    if (!d) return [];
    return DeviceAgentStore.getAgents(d.hostId || d.name);
  }

  isOnline(): boolean {
    let d = this.getDevice();
    if (!d) return false;
    return HostRuntimeStore.isDeviceOnline(d);
  }

  getHostPhase(): string {
    let d = this.getDevice();
    if (!d) return HostPhase.UNKNOWN;
    return HostRuntimeStore.getDevicePhase(d);
  }

  getStatusText(): string {
    let phase: string = this.getHostPhase();
    if (phase === HostPhase.ONLINE || phase === HostPhase.SYNCING) return this.text($r('app.string.agent_status_online'));
    if (phase === HostPhase.CONNECTING) return this.text($r('app.string.agent_status_connecting'));
    if (phase === HostPhase.WAITING_HOST) return this.text($r('app.string.agent_status_waiting_host'));
    if (phase === HostPhase.RECONNECTING) return this.text($r('app.string.agent_status_reconnecting'));
    if (phase === HostPhase.ERROR) return this.text($r('app.string.agent_status_error'));
    return this.text($r('app.string.agent_status_offline'));
  }

  getStatusColor(): Resource {
    let phase: string = this.getHostPhase();
    if (phase === HostPhase.ONLINE || phase === HostPhase.SYNCING) return Colors.success;
    if (phase === HostPhase.CONNECTING || phase === HostPhase.WAITING_HOST || phase === HostPhase.RECONNECTING) {
      return Colors.warning;
    }
    if (phase === HostPhase.ERROR) return Colors.error;
    return Colors.foregroundMuted;
  }

  /** 清理 URL 显示：去掉 ws:// 协议前缀 */
  cleanUrl(raw: string): string {
    if (raw.startsWith('ws://')) return raw.substring(5);
    if (raw.startsWith('wss://')) return raw.substring(6);
    return raw;
  }

  build() {
    NavDestination() {
      Column() {
        // Device Info
        Column() {
          Column() {
            SymbolGlyph($r('sys.symbol.externaldrive'))
              .fontSize(48)
              .fontColor([Colors.foreground])
          }
          .width(80).height(80)
          .justifyContent(FlexAlign.Center).margin({ bottom: Spacing.md })

          Text(this.getDevice()?.name || this.text($r('app.string.agent_unknown_host')))
            .fontSize(FontSize.xl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
            .margin({ bottom: Spacing.xs })

          Row() {
            Circle({ width: 6, height: 6 })
              .fill(this.getStatusColor())
              .margin({ right: Spacing.xs })
            Text(this.getStatusText())
              .fontSize(FontSize.sm).fontWeight(FontWeight.Medium)
              .fontColor(this.getStatusColor())
          }
        }
        .width(Layout.contentWidth).alignItems(HorizontalAlign.Center).margin({ bottom: Spacing.xl })

        // Tabs
        Row() {
          TabItem({ itemKey: 'overview', name: this.text($r('app.string.agent_tab_overview')), currentTab: this.currentTab, onSelect: () => { this.currentTab = 'overview'; } })
          TabItem({ itemKey: 'tools', name: this.text($r('app.string.agent_tab_tools')), currentTab: this.currentTab, onSelect: () => { this.currentTab = 'tools'; } })
          TabItem({ itemKey: 'sessions', name: this.text($r('app.string.agent_tab_sessions')), currentTab: this.currentTab, onSelect: () => { this.currentTab = 'sessions'; } })
        }
        .width(Layout.contentWidth).justifyContent(FlexAlign.SpaceEvenly)
        .margin({ bottom: Spacing.xl })

        // Content
        Scroll() {
          Column() {
            if (this.currentTab === 'overview') {
              this.OverviewContent()
            } else if (this.currentTab === 'tools') {
              this.ToolsContent()
            } else if (this.currentTab === 'sessions') {
              this.SessionsContent()
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: Spacing.xxxl })
        }
        .layoutWeight(1)
      }
      .width('100%').height('100%').alignItems(HorizontalAlign.Center).backgroundColor(Colors.surface0)
    }
    .hideTitleBar(false)
    .title(this.getDevice()?.name || this.text($r('app.string.agent_unknown_host')))

  }

  @Builder
  OverviewContent() {
    Column() {
      Text($r('app.string.agent_device_info')).fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
        .margin({ bottom: Spacing.xl })

      Row() {
        SymbolGlyph($r('sys.symbol.vpn_key')).fontSize(24).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.lg })
        Column() {
          Text($r('app.string.agent_host_id')).fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted).margin({ bottom: 2 })
          Text(this.getDevice()?.hostId || this.getDevice()?.name || '—').fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
        }.alignItems(HorizontalAlign.Start)
      }.width('100%').margin({ bottom: Spacing.xl })

      // Endpoint: clean URL without ws://
      Row() {
        SymbolGlyph($r('sys.symbol.wifi')).fontSize(24).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.lg })
        Column() {
          Text($r('app.string.agent_endpoint')).fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted).margin({ bottom: 2 })
          Text(this.getDevice()?.urls && this.getDevice()!.urls!.length > 0 ? this.cleanUrl(this.getDevice()!.urls![0]) : '—')
            .fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
        }.alignItems(HorizontalAlign.Start)
      }.width('100%').margin({ bottom: Spacing.xl })

      if (this.getAgents().length > 0) {
        Row() {
          Text($r('app.string.agent_acp_agents')).fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
          Blank()
          Text(this.text($r('app.string.agent_found_count'), this.getAgents().length))
            .fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted)
        }.width('100%').margin({ top: Spacing.xl, bottom: Spacing.lg })

        ForEach(this.getAgents(), (agent: AgentInfo) => {
          Row() {
            SymbolGlyph($r('sys.symbol.externaldrive'))
              .fontSize(24)
              .fontColor([Colors.foreground])
              .margin({ right: Spacing.lg })
            Column() {
              Text(agent.title || agent.name).fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
              if (agent.title && agent.title !== agent.name) {
                Text(agent.name).fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
              }
            }.alignItems(HorizontalAlign.Start)
          }.width('100%').padding({ top: Spacing.md, bottom: Spacing.md })
        }, (agent: AgentInfo) => agent.name)
      } else {
        Text($r('app.string.agent_no_acp_agents')).fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted).padding({ top: Spacing.lg })
      }
    }
    .width(Layout.contentWidth).alignItems(HorizontalAlign.Start)
  }

  @Builder
  ToolsContent() {
    Column() {
      Text($r('app.string.agent_capabilities')).fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
        .margin({ bottom: Spacing.xl })

      if (this.getAgents().length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(24).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.lg })
          Text($r('app.string.agent_file_system')).fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
          Blank()
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([Colors.foreground])
        }.width('100%').padding({ top: Spacing.md, bottom: Spacing.md })

        Row() {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(24).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.lg })
          Text($r('app.string.agent_shell_access')).fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
          Blank()
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([Colors.foreground])
        }.width('100%').padding({ top: Spacing.md, bottom: Spacing.md })

        ForEach(this.getAgents(), (agent: AgentInfo) => {
          if (agent.installed) {
            Text(agent.title || agent.name).fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.success)
              .width('100%').padding({ top: Spacing.md, bottom: Spacing.md })
          }
        }, (agent: AgentInfo) => 'cap_' + agent.name)
      } else {
        Text($r('app.string.agent_no_agents_connected')).fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted)
      }
    }.width(Layout.contentWidth).alignItems(HorizontalAlign.Start)
  }

  @Builder
  SessionsContent() {
    Column() {
      Row() {
        Text($r('app.string.agent_tab_sessions')).fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
        Blank()
        Text(ChatStore.sessions.length.toString()).fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted)
      }.width('100%').margin({ bottom: Spacing.xl })

      ForEach(ChatStore.sessions, (session: ServerSession) => {
        Row() {
          Column() {
            SymbolGlyph($r('sys.symbol.doc')).fontSize(24).fontColor([Colors.foregroundMuted])
          }
          .width(40).height(40)
          .justifyContent(FlexAlign.Center).margin({ right: Spacing.lg })

          Column() {
            Text(session.title || this.text($r('app.string.common_untitled'))).fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(session.agent || '').fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.width('100%').margin({ bottom: Spacing.xl })
      }, (session: ServerSession) => session.sessionId)

      if (ChatStore.sessions.length === 0) {
        Text($r('app.string.agent_no_sessions')).fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted).padding({ top: Spacing.lg })
      }
    }.width(Layout.contentWidth)
  }
}
