import { Colors, FontSize, Spacing, Radius, Layout } from '../../constants/DesignTokens';
import { StorageService } from '../../services/StorageService';
import { HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { HostPhase, HostRuntimeStore } from '../../common/model/HostState';

@Component
export struct SettingsPage {
  @StorageLink('pref_thinking_expanded') thinkingExpanded: boolean = true;
  @StorageLink('pref_toolcall_expanded') toolcallExpanded: boolean = true;
  @State showForm: boolean = false;
  @State newUrl: string = '';
  @StorageLink('serverUrl') serverUrl: string = '';
  onConnect?: (url: string) => void;
  onDeleteHost?: (index: number) => void;
  onScan?: () => void;

  getHostKey(device: DeviceEntry): string {
    return device.hostId || device.name;
  }

  getHostPhase(device: DeviceEntry): string {
    return HostRuntimeStore.getPhase(this.getHostKey(device));
  }

  isCurrentHost(device: DeviceEntry): boolean {
    return HostRuntimeStore.isCurrentHostOnline(this.getHostKey(device));
  }

  getActionText(device: DeviceEntry): string {
    let phase: string = this.getHostPhase(device);
    if (this.isCurrentHost(device)) return '当前';
    if (phase === HostPhase.CONNECTING) return '连接中';
    if (phase === HostPhase.WAITING_HOST) return '等待主机';
    if (phase === HostPhase.RECONNECTING) return '重连中';
    if (phase === HostPhase.ERROR) return '重试';
    if (HostRuntimeStore.isOnline(HostRuntimeStore.activeHostKey)) return '切换';
    return '连接';
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // 服务器管理
          Row() {
            Text('服务器管理')
              .fontSize(FontSize.lg).fontColor(Colors.foreground).fontWeight(FontWeight.Bold)
            Blank()
            Button() {
              Image($r('app.media.ic_scan'))
                .width(20).height(20).fillColor(Colors.foreground)
            }
            .width(36).height(36).backgroundColor(Color.Transparent)
            .margin({ right: Spacing.xs })
            .onClick(() => { if (this.onScan) this.onScan(); })

            Button() {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(20).fontColor([Colors.foreground])
            }
            .width(36).height(36).backgroundColor(Color.Transparent)
            .onClick(() => { this.showForm = true; })
          }
          .width(Layout.contentWidth)
          .padding({ top: Spacing.lg, bottom: Spacing.sm })

          if (HostStore.devices.length === 0) {
            Text('暂无已保存的服务器')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
              .width(Layout.contentWidth)
              .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
          } else {
            List({ space: Spacing.sm }) {
              ForEach(HostStore.devices, (device: DeviceEntry, index: number) => {
                ListItem() {
                  Row() {
                    Image($r('app.media.ic_terminal_window'))
                      .width(20).height(20).fillColor(Colors.foregroundMuted)
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

                    if (this.isCurrentHost(device)) {
                      SymbolGlyph($r('sys.symbol.checkmark'))
                        .fontSize(16).fontColor([Colors.accent]).margin({ right: Spacing.sm })
                      Text('当前').fontSize(FontSize.xs).fontColor(Colors.accent)
                    } else {
                      Text(this.getActionText(device))
                        .fontSize(FontSize.xs).fontColor(Colors.accent).margin({ right: Spacing.sm })
                    }
                  }
                  .width('100%')
                  .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
                  .borderRadius(Radius.md)
                  .onClick(() => {
                    if (!this.isCurrentHost(device) && this.onConnect && device.urls.length > 0) {
                      this.onConnect(device.urls[0]);
                    }
                  })
                  .stateStyles({
                    pressed: { .backgroundColor(Colors.surface1) },
                    normal: { .backgroundColor(Colors.transparent) }
                  })
                }
                .gesture(
                  LongPressGesture({ repeat: false, duration: 600 })
                    .onAction(() => { if (this.onDeleteHost) this.onDeleteHost(index) })
                )
              }, (device: DeviceEntry, index: number) => device.hostId || device.name + index.toString())
            }
            .width(Layout.contentWidth)
          }

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
                .fontWeight(FontWeight.Medium).borderRadius(Radius.sm).fontSize(FontSize.sm)
                .margin({ left: Spacing.sm })
                .onClick(() => {
                  if (this.newUrl.length > 0 && this.onConnect) {
                    this.onConnect(this.newUrl);
                    this.newUrl = '';
                    this.showForm = false;
                  }
                })
                .stateStyles({
                  pressed: { .backgroundColor(Colors.surface1) },
                  normal: { .backgroundColor(Colors.transparent) }
                })
            }
            .width(Layout.contentWidth)
            .padding({ bottom: Spacing.md })
          }

          Divider().width(Layout.contentWidth).margin({ top: Spacing.lg, bottom: Spacing.lg })

          Row() {
            Text('偏好设置')
              .fontSize(FontSize.lg).fontColor(Colors.foreground).fontWeight(FontWeight.Bold)
          }
          .width(Layout.contentWidth)
          .padding({ bottom: Spacing.sm })

          List({ space: Spacing.sm }) {
            ListItem() {
              Row() {
                Column() {
                  Text('Thinking 默认展开')
                    .fontSize(FontSize.base).fontColor(Colors.foreground).fontWeight(FontWeight.Medium)
                  Text('流式结束后自动展开思考内容')
                    .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
                    .margin({ top: Spacing.xxs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.thinkingExpanded })
                  .selectedColor(Colors.foreground)
                  .onChange((isOn: boolean) => {
                    this.thinkingExpanded = isOn;
                    StorageService.getInstance().putString('pref_thinking_expanded', isOn ? '1' : '0');
                  })
              }
              .width('100%')
              .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
              .backgroundColor(Colors.transparent)
              .borderRadius(Radius.lg)
              .stateStyles({
                pressed: { .backgroundColor(Colors.surface1) },
                normal: { .backgroundColor(Colors.transparent) }
              })
            }

            ListItem() {
              Row() {
                Column() {
                  Text('工具调用 默认展开')
                    .fontSize(FontSize.base).fontColor(Colors.foreground).fontWeight(FontWeight.Medium)
                  Text('完成后自动展开工具调用详情')
                    .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
                    .margin({ top: Spacing.xxs })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Blank()
                Toggle({ type: ToggleType.Switch, isOn: this.toolcallExpanded })
                  .selectedColor(Colors.foreground)
                  .onChange((isOn: boolean) => {
                    this.toolcallExpanded = isOn;
                    StorageService.getInstance().putString('pref_toolcall_expanded', isOn ? '1' : '0');
                  })
              }
              .width('100%')
              .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
              .backgroundColor(Colors.transparent)
              .borderRadius(Radius.lg)
              .stateStyles({
                pressed: { .backgroundColor(Colors.surface1) },
                normal: { .backgroundColor(Colors.transparent) }
              })
            }
          }
          .width(Layout.contentWidth)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: Spacing.xxxl })
      }
      .width('100%')
    }
    .title('设置')
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }
}
