import { Colors, FontSize, Spacing, Radius, Layout } from '../../constants/DesignTokens';
import { HostStore, DeviceEntry, ServerSession } from '../../common/model/WorkspaceInfo';
import { ChatStore } from '../../common/model/ChatState';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { AgentInfo } from '../../common/websocket/WSProtocol';
import { CustomIcon } from '../../common/ui/CustomIcon';

@Component
export struct AgentDetailView {
  @Prop deviceIndex: number = 0;
  onBack?: () => void;
  @State currentTab: string = 'overview';

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
        // Header
        Row() {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([Colors.foreground])
            .onClick(() => { this.onBack?.(); })
          Blank()
        }
        .width(Layout.contentWidth)
        .padding({ top: Spacing.xl, bottom: Spacing.md })

        // Device Info
        Column() {
          Column() {
            CustomIcon({ name: 'model', iconSize: 48, color: Colors.foreground })
          }
          .width(80).height(80).borderRadius(Radius.lg).backgroundColor(Colors.surface1)
          .justifyContent(FlexAlign.Center).margin({ bottom: Spacing.md })

          Text(this.getDevice()?.name || 'Unknown')
            .fontSize(FontSize.xxxl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
            .margin({ bottom: Spacing.xs })

          Row() {
            Circle({ width: 6, height: 6 })
              .fill(this.isOnline() ? Colors.success : Colors.foregroundMuted)
              .margin({ right: Spacing.xs })
            Text(this.isOnline() ? 'Online' : 'Offline')
              .fontSize(FontSize.sm)
              .fontColor(this.isOnline() ? Colors.success : Colors.foregroundMuted)
          }
        }
        .width(Layout.contentWidth).alignItems(HorizontalAlign.Center).margin({ bottom: Spacing.xl })

        // Tabs
        Row() {
          this.TabItem('overview', 'Overview')
          this.TabItem('tools', 'Tools')
          this.TabItem('sessions', 'Sessions')
        }
        .width(Layout.contentWidth).justifyContent(FlexAlign.SpaceEvenly)
        .border({ width: { bottom: 1 }, color: Colors.borderLight })
        .margin({ bottom: Spacing.lg })

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
    .hideTitleBar(true).width('100%').height('100%')
  }

  @Builder
  TabItem(key: string, name: string) {
    Column() {
      Text(name)
        .fontSize(FontSize.sm)
        .fontWeight(this.currentTab === key ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.currentTab === key ? Colors.foreground : Colors.foregroundMuted)
        .padding({ bottom: Spacing.sm })
      if (this.currentTab === key) {
        Divider().strokeWidth(2).color(Colors.foreground).width(40)
      } else {
        Divider().strokeWidth(2).color(Colors.transparent).width(40)
      }
    }
    .onClick(() => { this.currentTab = key; })
  }

  @Builder
  OverviewContent() {
    Column() {
      Text("Device Info").fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
        .margin({ bottom: Spacing.lg })

      Row() {
        SymbolGlyph($r('sys.symbol.vpn_key')).fontSize(20).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.md })
        Column() {
          Text("Host ID").fontSize(FontSize.xs).fontColor(Colors.foregroundMuted).margin({ bottom: 2 })
          Text(this.getDevice()?.hostId || this.getDevice()?.name || '—').fontSize(FontSize.sm).fontColor(Colors.foreground)
        }.alignItems(HorizontalAlign.Start)
      }.width('100%').margin({ bottom: Spacing.lg })

      // Endpoint: clean URL without ws://
      Row() {
        SymbolGlyph($r('sys.symbol.wifi')).fontSize(20).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.md })
        Column() {
          Text("Endpoint").fontSize(FontSize.xs).fontColor(Colors.foregroundMuted).margin({ bottom: 2 })
          Text(this.getDevice()?.urls && this.getDevice()!.urls!.length > 0 ? this.cleanUrl(this.getDevice()!.urls![0]) : '—')
            .fontSize(FontSize.sm).fontColor(Colors.foreground)
        }.alignItems(HorizontalAlign.Start)
      }.width('100%').margin({ bottom: Spacing.lg })

      if (this.getAgents().length > 0) {
        Row() {
          Text("ACP Agents").fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
          Blank()
          Text(this.getAgents().length.toString() + ' found').fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
        }.width('100%').margin({ top: Spacing.xl, bottom: Spacing.md })

        ForEach(this.getAgents(), (agent: AgentInfo) => {
          Row() {
            CustomIcon({ name: 'model', iconSize: 24, color: Colors.foreground }).margin({ right: Spacing.md })
            Column() {
              Text(agent.title || agent.name).fontSize(FontSize.sm).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
              if (agent.title && agent.title !== agent.name) {
                Text(agent.name).fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
              }
            }.alignItems(HorizontalAlign.Start)
          }.width('100%').padding({ top: Spacing.sm, bottom: Spacing.sm })
            .border({ width: { bottom: 1 }, color: Colors.borderLight })
        }, (agent: AgentInfo) => agent.name)
      } else {
        Text("No ACP agents discovered").fontSize(FontSize.sm).fontColor(Colors.foregroundMuted).padding({ top: Spacing.md })
      }
    }
    .width(Layout.contentWidth).alignItems(HorizontalAlign.Start)
  }

  @Builder
  ToolsContent() {
    Column() {
      Text("Capabilities").fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
        .margin({ bottom: Spacing.lg })

      if (this.getAgents().length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(20).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.md })
          Text("File System").fontSize(FontSize.sm).fontColor(Colors.foreground)
          Blank()
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([Colors.foreground])
        }.width('100%').padding({ top: Spacing.sm, bottom: Spacing.sm })

        Row() {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(20).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.md })
          Text("Shell Access").fontSize(FontSize.sm).fontColor(Colors.foreground)
          Blank()
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([Colors.foreground])
        }.width('100%').padding({ top: Spacing.sm, bottom: Spacing.sm })

        ForEach(this.getAgents(), (agent: AgentInfo) => {
          if (agent.installed) {
            Text(agent.title || agent.name).fontSize(FontSize.sm).fontColor(Colors.success)
              .width('100%').padding({ top: Spacing.sm, bottom: Spacing.sm })
          }
        }, (agent: AgentInfo) => 'cap_' + agent.name)
      } else {
        Text("No agents connected").fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
      }
    }.width(Layout.contentWidth)
  }

  @Builder
  SessionsContent() {
    Column() {
      Row() {
        Text("Sessions").fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
        Blank()
        Text(ChatStore.sessions.length.toString()).fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
      }.width('100%').margin({ bottom: Spacing.lg })

      ForEach(ChatStore.sessions, (session: ServerSession) => {
        Row() {
          Column() {
            SymbolGlyph($r('sys.symbol.doc')).fontSize(20).fontColor([Colors.foregroundMuted])
          }
          .width(40).height(40).borderRadius(Radius.md).backgroundColor(Colors.surface1)
          .justifyContent(FlexAlign.Center).margin({ right: Spacing.md })

          Column() {
            Text(session.title || 'Untitled').fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(session.agent || '').fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        }.width('100%').margin({ bottom: Spacing.md })
      }, (session: ServerSession) => session.sessionId)

      if (ChatStore.sessions.length === 0) {
        Text("No sessions").fontSize(FontSize.sm).fontColor(Colors.foregroundMuted).padding({ top: Spacing.lg })
      }
    }.width(Layout.contentWidth)
  }
}
