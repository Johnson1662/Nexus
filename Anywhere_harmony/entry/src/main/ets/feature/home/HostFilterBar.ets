import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
import { ChatStore } from '../../common/model/ChatState';
import { DeviceEntry } from '../../common/model/WorkspaceInfo';

@Component
export struct HostFilterBar {
  @Prop devices: DeviceEntry[] = [];
  @Prop selectedKey: string = '';
  onSelect?: (key: string) => void;
  @State pressedKey: string = '';

  build() {
    Scroll() {
      Row({ space: Spacing.sm }) {
        this.Chip('All', 'all', true)
        ForEach(this.devices, (device: DeviceEntry) => {
          this.Chip(
            this.getHostLabel(device),
            device.hostId || device.name,
            this.isOnline(device)
          )
        }, (device: DeviceEntry) => device.hostId || device.name)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height(42)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .padding({ left: Spacing.xl, right: Spacing.xl })
  }

  isOnline(device: DeviceEntry): boolean {
    return ChatStore.connected && ChatStore.currentDeviceId.length > 0 &&
      (device.hostId === ChatStore.currentDeviceId || device.name === ChatStore.currentDeviceId);
  }

  @Builder
  Chip(label: string, key: string, online: boolean) {
    Button() {
      Row() {
        if (key !== 'all') {
          Circle({ width: 6, height: 6 })
            .fill(online ? Colors.success : Colors.foregroundMuted)
            .margin({ right: Spacing.xs })
        }
        Text(label)
          .fontSize(FontSize.sm)
          .fontWeight(this.selectedKey === key ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.selectedKey === key ? Colors.surface0 : Colors.foreground)
          .maxLines(1)
      }
    }
    .height(32)
    .padding({ left: Spacing.md, right: Spacing.md })
    .backgroundColor(this.selectedKey === key ? Colors.foreground : (this.pressedKey === key ? Colors.surfaceElevated : Colors.surface1))
    .border({ width: 0 })
    .borderRadius(Radius.full)
    .animation({ duration: Duration.fast, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedKey = key;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onClick(() => { if (this.onSelect) this.onSelect(key); })
  }

  getHostLabel(device: DeviceEntry): string {
    if (device.name.length > 16) {
      return device.name.substring(0, 16);
    }
    return device.name;
  }
}
