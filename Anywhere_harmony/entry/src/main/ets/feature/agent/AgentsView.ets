import { Colors, FontSize, Spacing, Radius, Layout } from '../../constants/DesignTokens';
import { HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { HostPhase, HostRuntimeStore } from '../../common/model/HostState';
import { CustomIcon } from '../../common/ui/CustomIcon';

@Component
export struct AgentsView {
  onNavigateToDetail?: (index: number) => void;
  onNavigateToSettings?: () => void;
  @State filterIndex: number = 0;
  @State itemPressScale: number = 1.0;

  getHostKey(device: DeviceEntry): string {
    return device.hostId || device.name;
  }

  getDevicePhase(device: DeviceEntry): string {
    return HostRuntimeStore.getPhase(this.getHostKey(device));
  }

  isDeviceOnline(device: DeviceEntry): boolean {
    return HostRuntimeStore.isOnline(this.getHostKey(device));
  }

  getDeviceStatusText(device: DeviceEntry): string {
    let phase: string = this.getDevicePhase(device);
    if (phase === HostPhase.ONLINE || phase === HostPhase.SYNCING) return 'Online';
    if (phase === HostPhase.CONNECTING) return 'Connecting';
    if (phase === HostPhase.WAITING_HOST) return 'Waiting';
    if (phase === HostPhase.RECONNECTING) return 'Reconnecting';
    if (phase === HostPhase.ERROR) return 'Error';
    return 'Offline';
  }

  getDeviceStatusColor(device: DeviceEntry): Resource {
    let phase: string = this.getDevicePhase(device);
    if (phase === HostPhase.ONLINE || phase === HostPhase.SYNCING) return Colors.success;
    if (phase === HostPhase.CONNECTING || phase === HostPhase.WAITING_HOST || phase === HostPhase.RECONNECTING) {
      return Colors.warning;
    }
    if (phase === HostPhase.ERROR) return Colors.error;
    return Colors.foregroundMuted;
  }

  matchesFilter(device: DeviceEntry): boolean {
    let online = this.isDeviceOnline(device);
    if (this.filterIndex === 0) return true;
    if (this.filterIndex === 1 && online) return true;
    if (this.filterIndex === 2 && !online) return true;
    return false;
  }

  getDeviceName(device: DeviceEntry): string {
    return device.name + this.filterIndex.toString() + this.getDevicePhase(device);
  }

  build() {
    Column() {
      // Header
      Row() {
        Text("Agents").fontSize(FontSize.xxxxl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
        Blank()
        SymbolGlyph($r('sys.symbol.person_badge_plus')).fontSize(24).fontColor([Colors.foreground])
          .onClick(() => { this.onNavigateToSettings?.(); })
      }
      .width(Layout.contentWidth)
      .padding({ top: Spacing.xxxl, bottom: Spacing.lg })

      if (HostStore.devices.length > 0) {
        // Filter Tabs
        Row({ space: Spacing.sm }) {
          this.FilterTab('All', 0)
          this.FilterTab('Online', 1)
          this.FilterTab('Offline', 2)
        }
        .width(Layout.contentWidth)
        .padding({ bottom: Spacing.lg })

        // Device List
        List({ space: Spacing.sm }) {
          ForEach(HostStore.devices, (device: DeviceEntry, index: number) => {
            if (this.matchesFilter(device)) {
              ListItem() {
                this.AgentListItem(device, index)
              }
            }
          }, (device: DeviceEntry) => this.getDeviceName(device))
        }
        .width(Layout.contentWidth)
        .layoutWeight(1)
      } else {
        // Empty state — host pairing now lives in the shared host management flow.
        Column() {
          SymbolGlyph($r('sys.symbol.person_2')).fontSize(56).fontColor([Colors.foregroundMuted]).margin({ bottom: Spacing.lg })
            .opacity(0.55)
          Text("No Agents Yet").fontSize(FontSize.xl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground).margin({ bottom: Spacing.xs })
          Text("Add your first ACP bridge server\nto start managing agents").fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
            .textAlign(TextAlign.Center).margin({ bottom: Spacing.xl })
          Button("Add Device")
            .fontSize(FontSize.sm).fontWeight(FontWeight.Medium)
            .fontColor(Colors.surface0).backgroundColor(Colors.foreground)
            .borderRadius(Radius.lg).padding({ left: Spacing.xxl, right: Spacing.xxl, top: Spacing.md, bottom: Spacing.md })
            .onClick(() => { this.onNavigateToSettings?.(); })
        }
        .width(Layout.contentWidth)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding(Spacing.xxl)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Colors.surface0)
  }

  @Builder
  FilterTab(name: string, idx: number) {
    Text(name)
      .fontSize(FontSize.sm)
      .fontWeight(this.filterIndex === idx ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.filterIndex === idx ? Colors.surface0 : Colors.foreground)
      .backgroundColor(this.filterIndex === idx ? Colors.foreground : Colors.surface1)
      .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
      .borderRadius(Radius.full)
      .onClick(() => { this.filterIndex = idx; })
  }

  @Builder
  AgentListItem(device: DeviceEntry, index: number) {
    Row() {
      Column() {
        CustomIcon({ name: 'model', iconSize: 24, color: Colors.foreground })
      }
      .width(48)
      .height(48)
      .borderRadius(Radius.md)
      .backgroundColor(Colors.surface1)
      .justifyContent(FlexAlign.Center)
      .margin({ right: Spacing.md })

      Column() {
        Text(device.name).fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground).margin({ bottom: 2 })
        Text(device.urls.length > 0 ? device.urls[0] : '').fontSize(FontSize.xs).fontColor(Colors.foregroundMuted).maxLines(1)
      }.alignItems(HorizontalAlign.Start)

      Blank()

      Row() {
        Circle({ width: 6, height: 6 })
          .fill(this.getDeviceStatusColor(device))
          .margin({ right: Spacing.xs })
        Text(this.getDeviceStatusText(device)).fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
        SymbolGlyph($r('sys.symbol.ellipsis_message')).fontSize(16).fontColor([Colors.foregroundMuted]).margin({ left: Spacing.md })
          .onClick(() => { this.onNavigateToSettings?.(); })
      }
    }
    .width('100%')
    .padding(Spacing.md)
    .backgroundColor(Colors.surface0)
    .borderRadius(Radius.lg)
    .onClick(() => { this.onNavigateToDetail?.(index); })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) { this.itemPressScale = 0.97; }
      else { this.itemPressScale = 1.0; }
    })
    .scale({ x: this.itemPressScale, y: this.itemPressScale })
    .animation({ duration: Duration.fast, curve: Curve.EaseOut })
  }
}
