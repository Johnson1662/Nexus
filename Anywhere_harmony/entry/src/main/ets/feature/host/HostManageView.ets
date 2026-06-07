import { Colors, FontSize, Spacing, Radius, Layout } from '../../constants/DesignTokens';
import { HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { ChatStore } from '../../common/model/ChatState';

@Component
export struct HostManagePage {
  @State showForm: boolean = false;
  @State newUrl: string = '';
  @StorageLink('serverUrl') serverUrl: string = '';
  onConnect?: (url: string) => void;
  onDeleteHost?: (index: number) => void;

  isCurrentHost(urls: string[]): boolean {
    let current: string = this.serverUrl;
    if (current.length === 0) return false;
    for (let i: number = 0; i < urls.length; i++) {
      if (urls[i].length > 0 && current.indexOf(urls[i]) >= 0) return true;
      if (urls[i].length > 0 && urls[i].indexOf(current) >= 0) return true;
    }
    if (ChatStore.connected) {
      for (let i: number = 0; i < urls.length; i++) {
        if (urls[i].length > 0 && current === urls[i]) return true;
      }
    }
    return false;
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('Host 管理')
            .fontSize(FontSize.xl).fontColor(Colors.foreground).fontWeight(FontWeight.Bold)
        }
        .width(Layout.contentWidth)
        .padding({ top: Spacing.lg, bottom: Spacing.lg })

        if (HostStore.devices.length === 0) {
          Column() {
            Text('暂无已保存的服务器')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
            Text('点击下方添加')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
              .margin({ top: Spacing.xs })
          }
          .width(Layout.contentWidth).layoutWeight(1)
          .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
          .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md })
        } else {
          List({ space: Spacing.sm }) {
            ForEach(HostStore.devices, (device: DeviceEntry, index: number) => {
              ListItem() {
                Row() {
                  Image($r('app.media.ic_terminal_window'))
                    .width(20).height(20)
                    .fillColor(Colors.foregroundMuted)
                    .margin({ right: Spacing.md })

                  Column() {
                    Text(device.name)
                      .fontSize(FontSize.base).fontColor(Colors.foreground).fontWeight(FontWeight.Medium)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(device.urls.length > 0 ? device.urls[0] : '')
                      .fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: Spacing.xxs })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (ChatStore.connected && this.isCurrentHost(device.urls)) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(16).fontColor([Colors.accent])
                      .margin({ right: Spacing.sm })
                    Text('当前')
                      .fontSize(FontSize.xs).fontColor(Colors.accent)
                  } else {
                    Text(ChatStore.connected ? '切换' : '连接')
                      .fontSize(FontSize.xs).fontColor(Colors.accent)
                      .margin({ right: Spacing.sm })
                  }
                }
                .width('100%')
                .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
                .borderRadius(Radius.md)
                .onClick(() => {
                  if (!this.isCurrentHost(device.urls) && this.onConnect && device.urls.length > 0) {
                    this.onConnect(device.urls[0]);
                  }
                })
                .stateStyles({
                  pressed: {
                    .backgroundColor(Colors.surface1)
                  },
                  normal: {
                    .backgroundColor(Colors.transparent)
                  }
                })
              }
              .width('100%')
              .gesture(
                LongPressGesture({ repeat: false, duration: 600 })
                  .onAction(() => { if (this.onDeleteHost) this.onDeleteHost(index) })
              )
            }, (device: DeviceEntry, index: number) => device.hostId || device.name + index.toString())
          }
          .width(Layout.contentWidth)
          .layoutWeight(1)
        }

        Column() {
          if (this.showForm) {
            Row() {
              TextInput({ placeholder: 'ws://IP:PORT', text: this.newUrl })
                .layoutWeight(1).height(44)
                .borderRadius(Radius.sm)
                .padding({ left: Spacing.md, right: Spacing.md })
                .fontSize(FontSize.sm)
                .backgroundColor(Colors.transparent)
                .onChange((v: string) => { this.newUrl = v })
                .onSubmit(() => {
                  if (this.newUrl.length > 0 && this.onConnect) {
                    this.onConnect(this.newUrl);
                    this.newUrl = '';
                    this.showForm = false;
                  }
                })
              Button('连接')
                .height(44).backgroundColor(Colors.transparent).fontColor(Colors.accent)
                .fontWeight(FontWeight.Medium)
                .borderRadius(Radius.sm).fontSize(FontSize.sm)
                .margin({ left: Spacing.sm })
                .onClick(() => {
                  if (this.newUrl.length > 0 && this.onConnect) {
                    this.onConnect(this.newUrl);
                    this.newUrl = '';
                    this.showForm = false;
                  }
                })
                .stateStyles({
                  pressed: {
                    .backgroundColor(Colors.surface1)
                  },
                  normal: {
                    .backgroundColor(Colors.transparent)
                  }
                })
            }
            .width('100%')
            .padding({ bottom: Spacing.md })
          } else {
            Button('添加服务器')
              .width('100%').height(44)
              .backgroundColor(Colors.transparent).fontColor(Colors.accent)
              .fontWeight(FontWeight.Medium)
              .borderRadius(Radius.sm).fontSize(FontSize.base)
              .margin({ bottom: Spacing.xxxl })
              .onClick(() => { this.showForm = true })
              .stateStyles({
                pressed: {
                  .backgroundColor(Colors.surface1)
                },
                normal: {
                  .backgroundColor(Colors.transparent)
                }
              })
          }
        }
        .width(Layout.contentWidth)
      }
      .width('100%').height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
