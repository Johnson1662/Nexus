import { Colors, FontSize, Spacing, Radius } from '../../constants/DesignTokens';
import { DeviceEntry } from '../../common/model/WorkspaceInfo';
import { HostPhase, HostRuntimeStore } from '../../common/model/HostState';

@Component
export struct HostFilterBar {
  @Prop devices: DeviceEntry[] = [];
  @Prop selectedKey: string = '';
  @Prop statusRevision: number = 0;
  onSelect?: (key: string) => void;
  @State pressedKey: string = '';

  build() {
    Scroll() {
      Row({ space: Spacing.md }) {
        ForEach(this.devices, (device: DeviceEntry) => {
          this.Chip(
            this.getHostLabel(device),
            device.hostId || device.name,
            this.getPhase(device)
          )
        }, (device: DeviceEntry) => (device.hostId || device.name) + ':' + this.statusRevision.toString())
      }
      .padding({ left: Spacing.xl, right: Spacing.xl })
      .height('100%')
    }
    .width('100%')
    .height(48)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
  }

  getPhase(device: DeviceEntry): string {
    return HostRuntimeStore.getDevicePhase(device);
  }

  getPhaseColor(phase: string): Resource {
    if (phase === HostPhase.ONLINE || phase === HostPhase.SYNCING) return Colors.success;
    if (phase === HostPhase.WAITING_HOST || phase === HostPhase.RECONNECTING || phase === HostPhase.CONNECTING) {
      return Colors.warning;
    }
    if (phase === HostPhase.ERROR) return Colors.error;
    return Colors.foregroundMuted;
  }

  @Builder
  Chip(label: string, key: string, phase: string) {
    Button() {
      Row() {
        Circle({ width: 7, height: 7 })
          .fill(this.getPhaseColor(phase))
          .margin({ right: Spacing.xs })
        Text(label)
          .fontSize(FontSize.md)
          .fontWeight(this.selectedKey === key ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.selectedKey === key ? Colors.surface0 : Colors.foreground)
          .maxLines(1)
      }
    }
    .height(36)
    .padding({ left: Spacing.xl, right: Spacing.xl })
    .backgroundColor(this.selectedKey === key ? Colors.foreground : Colors.surface1)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface0) }
    })

    .border({ width: 0 })
    .borderRadius(Radius.full)
    .animation({ duration: 200, curve: Curve.EaseOut })

    .onClick(() => { if (this.onSelect) this.onSelect(key); })
  }
  getHostLabel(device: DeviceEntry): string {
    if (device.name.length > 16) {
      return device.name.substring(0, 16);
    }
    return device.name;
  }
}
