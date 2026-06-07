import { Colors, FontSize, Spacing, Radius, Layout } from '../../constants/DesignTokens';
import { HostStore, DeviceEntry, ServerSession } from '../../common/model/WorkspaceInfo';
import { ChatStore } from '../../common/model/ChatState';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { AgentInfo } from '../../common/websocket/WSProtocol';
import { CustomIcon } from '../../common/ui/CustomIcon';

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
    if (!ChatStore.connected) return false;
    let d = this.getDevice();
    if (!d) return false;
    let did = ChatStore.currentDeviceId;
    return (!!d.hostId && d.hostId === did) || d.name === did;
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
            CustomIcon({ name: 'model', iconSize: 48, color: Colors.foreground })
          }
          .width(80).height(80)
          .justifyContent(FlexAlign.Center).margin({ bottom: Spacing.md })

          Text(this.getDevice()?.name || 'Unknown')
            .fontSize(FontSize.xl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
            .margin({ bottom: Spacing.xs })

          Row() {
            Circle({ width: 6, height: 6 })
              .fill(this.isOnline() ? Colors.success : Colors.foregroundMuted)
              .margin({ right: Spacing.xs })
            Text(this.isOnline() ? 'Online' : 'Offline')
              .fontSize(FontSize.sm).fontWeight(FontWeight.Medium)
              .fontColor(this.isOnline() ? Colors.success : Colors.foregroundMuted)
          }
        }
        .width(Layout.contentWidth).alignItems(HorizontalAlign.Center).margin({ bottom: Spacing.xl })

        // Tabs
        Row() {
          TabItem({ itemKey: 'overview', name: 'Overview', currentTab: this.currentTab, onSelect: () => { this.currentTab = 'overview'; } })
          TabItem({ itemKey: 'tools', name: 'Tools', currentTab: this.currentTab, onSelect: () => { this.currentTab = 'tools'; } })
          TabItem({ itemKey: 'sessions', name: 'Sessions', currentTab: this.currentTab, onSelect: () => { this.currentTab = 'sessions'; } })
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
    .hideTitleBar(true)

  }

  @Builder
  OverviewContent() {
    Column() {
      Text("Device Info").fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
        .margin({ bottom: Spacing.xl })

      Row() {
        SymbolGlyph($r('sys.symbol.vpn_key')).fontSize(24).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.lg })
        Column() {
          Text("Host ID").fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted).margin({ bottom: 2 })
          Text(this.getDevice()?.hostId || this.getDevice()?.name || '—').fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
        }.alignItems(HorizontalAlign.Start)
      }.width('100%').margin({ bottom: Spacing.xl })

      // Endpoint: clean URL without ws://
      Row() {
        SymbolGlyph($r('sys.symbol.wifi')).fontSize(24).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.lg })
        Column() {
          Text("Endpoint").fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted).margin({ bottom: 2 })
          Text(this.getDevice()?.urls && this.getDevice()!.urls!.length > 0 ? this.cleanUrl(this.getDevice()!.urls![0]) : '—')
            .fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
        }.alignItems(HorizontalAlign.Start)
      }.width('100%').margin({ bottom: Spacing.xl })

      if (this.getAgents().length > 0) {
        Row() {
          Text("ACP Agents").fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
          Blank()
          Text(this.getAgents().length.toString() + ' found').fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted)
        }.width('100%').margin({ top: Spacing.xl, bottom: Spacing.lg })

        ForEach(this.getAgents(), (agent: AgentInfo) => {
          Row() {
            CustomIcon({ name: 'model', iconSize: 24, color: Colors.foreground }).margin({ right: Spacing.lg })
            Column() {
              Text(agent.title || agent.name).fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
              if (agent.title && agent.title !== agent.name) {
                Text(agent.name).fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
              }
            }.alignItems(HorizontalAlign.Start)
          }.width('100%').padding({ top: Spacing.md, bottom: Spacing.md })
        }, (agent: AgentInfo) => agent.name)
      } else {
        Text("No ACP agents discovered").fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted).padding({ top: Spacing.lg })
      }
    }
    .width(Layout.contentWidth).alignItems(HorizontalAlign.Start)
  }

  @Builder
  ToolsContent() {
    Column() {
      Text("Capabilities").fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
        .margin({ bottom: Spacing.xl })

      if (this.getAgents().length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(24).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.lg })
          Text("File System").fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
          Blank()
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([Colors.foreground])
        }.width('100%').padding({ top: Spacing.md, bottom: Spacing.md })

        Row() {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(24).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.lg })
          Text("Shell Access").fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
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
        Text("No agents connected").fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted)
      }
    }.width(Layout.contentWidth).alignItems(HorizontalAlign.Start)
  }

  @Builder
  SessionsContent() {
    Column() {
      Row() {
        Text("Sessions").fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
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
            Text(session.title || 'Untitled').fontSize(FontSize.md).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(session.agent || '').fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.width('100%').margin({ bottom: Spacing.xl })
      }, (session: ServerSession) => session.sessionId)

      if (ChatStore.sessions.length === 0) {
        Text("No sessions").fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foregroundMuted).padding({ top: Spacing.lg })
      }
    }.width(Layout.contentWidth)
  }
}
