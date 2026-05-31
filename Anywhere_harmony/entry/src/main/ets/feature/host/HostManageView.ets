import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
import { HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { CustomIcon } from '../../common/ui/CustomIcon';
import { ChatStore } from '../../common/model/ChatState';
import { saveHosts } from '../../services/StorageService';

@Component
export struct HostManagePage {
  @State showForm: boolean = false;
  @State newUrl: string = '';
  @StorageLink('serverUrl') serverUrl: string = '';
  onConnect?: (url: string) => void;
  onDeleteHost?: (index: number) => void;

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('Host 管理')
            .fontSize(FontSize.xl).fontColor(Colors.foreground).fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.lg })

        if (HostStore.devices.length === 0) {
          Column() {
            Text('暂无已保存的服务器')
              .fontSize(FontSize.base).fontColor(Colors.foregroundMuted)
            Text('点击下方添加')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
              .margin({ top: Spacing.xs })
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        } else {
          List() {
            ForEach(HostStore.devices, (device: DeviceEntry, index: number) => {
              ListItem() {
                Row() {
                  CustomIcon({
                    name: 'wifi',
                    iconSize: 20,
                    color: Colors.foregroundMuted
                  })
                    .margin({ right: Spacing.md })

                  Column() {
                    Text(device.name)
                      .fontSize(FontSize.base).fontColor(Colors.foreground)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(device.urls.length > 0 ? device.urls[0] : '')
                      .fontSize(FontSize.xs).fontColor(Colors.foregroundLight)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: Spacing.xxs })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  if (ChatStore.connected) {
                    CustomIcon({
                      name: 'checkmark',
                      iconSize: 16,
                      color: Colors.accent
                    })
                      .margin({ right: Spacing.sm })
                    Text('切换')
                      .fontSize(FontSize.xs).fontColor(Colors.accent)
                      .onClick(() => { if (this.onConnect && device.urls.length > 0) this.onConnect(device.urls[0]) })
                  }
                }
                .width('100%')
                .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
              }
              .width('100%')
              .gesture(
                LongPressGesture({ repeat: false, duration: 600 })
                  .onAction(() => { if (this.onDeleteHost) this.onDeleteHost(index) })
              )
            }, (device: DeviceEntry, index: number) => device.hostId || device.name + index.toString())
          }
          .width('100%')
          .layoutWeight(1)
        }

        Column() {
          if (this.showForm) {
            Row() {
              TextInput({ placeholder: 'ws://IP:PORT', text: this.newUrl })
                .layoutWeight(1).height(44)
                .backgroundColor(Colors.surface1).borderRadius(Radius.sm)
                .padding({ left: Spacing.md, right: Spacing.md })
                .fontSize(FontSize.sm)
                .onChange((v: string) => { this.newUrl = v })
                .onSubmit(() => {
                  if (this.newUrl.length > 0 && this.onConnect) {
                    this.onConnect(this.newUrl);
                    this.newUrl = '';
                    this.showForm = false;
                  }
                })
              Button('连接')
                .height(44).backgroundColor(Colors.accent).fontColor(Color.White)
                .borderRadius(Radius.sm).fontSize(FontSize.sm)
                .margin({ left: Spacing.sm })
                .onClick(() => {
                  if (this.newUrl.length > 0 && this.onConnect) {
                    this.onConnect(this.newUrl);
                    this.newUrl = '';
                    this.showForm = false;
                  }
                })
            }
            .width('100%')
            .padding({ left: Spacing.lg, right: Spacing.lg, bottom: Spacing.md })
          } else {
            Button('添加服务器')
              .width('100%').height(44)
              .backgroundColor(Colors.accent).fontColor(Color.White)
              .borderRadius(Radius.sm).fontSize(FontSize.base)
              .margin({ left: Spacing.lg, right: Spacing.lg, bottom: Spacing.xxxl })
              .onClick(() => { this.showForm = true })
          }
        }
        .width('100%')
      }
      .width('100%').height('100%')
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
