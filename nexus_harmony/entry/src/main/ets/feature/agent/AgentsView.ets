import { Colors, FontSize, Spacing, Radius, Layout, AnimationPresets, getLocalizedString } from '../../constants/DesignTokens';
import { HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { HostPhase, HostRuntimeStore } from '../../common/model/HostState';

@Component
export struct AgentsView {
  onNavigateToDetail?: (index: number) => void;
  onNavigateToSettings?: () => void;
  @State filterIndex: number = 0;

  text(res: Resource): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res);
  }

  getHostKey(device: DeviceEntry): string {
    return device.hostId || device.name;
  }

  getDevicePhase(device: DeviceEntry): string {
    return HostRuntimeStore.getDevicePhase(device);
  }

  isDeviceOnline(device: DeviceEntry): boolean {
    return HostRuntimeStore.isDeviceOnline(device);
  }

  getDeviceStatusText(device: DeviceEntry): string {
    let phase: string = this.getDevicePhase(device);
    if (phase === HostPhase.ONLINE || phase === HostPhase.SYNCING) return this.text($r('app.string.agent_status_online'));
    if (phase === HostPhase.CONNECTING) return this.text($r('app.string.agent_status_connecting'));
    if (phase === HostPhase.WAITING_HOST) return this.text($r('app.string.agent_status_waiting_short'));
    if (phase === HostPhase.RECONNECTING) return this.text($r('app.string.agent_status_reconnecting'));
    if (phase === HostPhase.ERROR) return this.text($r('app.string.agent_status_error'));
    return this.text($r('app.string.agent_status_offline'));
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
        Text($r('app.string.agents_title')).fontSize(FontSize.xxxxl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
        Blank()
        SymbolGlyph($r('sys.symbol.person_badge_plus')).fontSize(24).fontColor([Colors.foreground])
          .onClick(() => { this.onNavigateToSettings?.(); })
      }
      .width(Layout.contentWidth)
      .padding({ top: Spacing.xxxl, bottom: Spacing.lg })

      if (HostStore.devices.length > 0) {
        // Filter Tabs
        Row({ space: Spacing.sm }) {
          this.FilterTab(this.text($r('app.string.agents_filter_all')), 0)
          this.FilterTab(this.text($r('app.string.agents_filter_online')), 1)
          this.FilterTab(this.text($r('app.string.agents_filter_offline')), 2)
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
          Text($r('app.string.agents_empty_title'))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width(Layout.contentWidth)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md })
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
        SymbolGlyph($r('sys.symbol.externaldrive'))
          .fontSize(24)
          .fontColor([Colors.foreground])
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
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .transition(AnimationPresets.fadeIn)
  }
}
