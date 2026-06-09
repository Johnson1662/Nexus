import { Colors, FontSize, Spacing, Radius, Layout } from '../../constants/DesignTokens';
import { StorageService } from '../../services/StorageService';
import { HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { HostPhase, HostRuntimeStore, HostRuntimeState } from '../../common/model/HostState';

@Component
export struct SettingsPage {
  @StorageLink('pref_thinking_expanded') thinkingExpanded: boolean = true;
  @StorageLink('pref_toolcall_expanded') toolcallExpanded: boolean = true;
  @StorageLink('serverUrl') serverUrl: string = '';
  @State showManualConnect: boolean = false;
  @State newUrl: string = '';
  @State expandedHostKey: string = '';
  onConnect?: (url: string) => void;
  onConnectHost?: (index: number) => void;
  onDeleteHost?: (index: number) => void;
  onScan?: () => void;

  getHostKey(device: DeviceEntry): string {
    return device.hostId || device.name;
  }

  getHostPhase(device: DeviceEntry): string {
    return HostRuntimeStore.getDevicePhase(device);
  }

  getRuntimeStatus(device: DeviceEntry): HostRuntimeState {
    if (HostRuntimeStore.matchesDevice(device, HostRuntimeStore.activeHostKey)) {
      return HostRuntimeStore.getStatus(HostRuntimeStore.activeHostKey);
    }
    return HostRuntimeStore.getStatus(this.getHostKey(device));
  }

  getActiveUrl(device: DeviceEntry): string {
    return this.getRuntimeStatus(device).activeUrl;
  }

  getCurrentAddress(device: DeviceEntry): string {
    if (!HostRuntimeStore.matchesDevice(device, HostRuntimeStore.activeHostKey)) {
      return '';
    }
    let phase: string = this.getHostPhase(device);
    if (phase === HostPhase.OFFLINE || phase === HostPhase.UNKNOWN || phase === HostPhase.ERROR) {
      return '';
    }
    return this.getActiveUrl(device);
  }

  isCurrentHost(device: DeviceEntry): boolean {
    return HostRuntimeStore.isDeviceOnline(device) && HostRuntimeStore.matchesDevice(device, HostRuntimeStore.activeHostKey);
  }

  isBusy(device: DeviceEntry): boolean {
    let phase: string = this.getHostPhase(device);
    return phase === HostPhase.CONNECTING || phase === HostPhase.RECONNECTING;
  }

  getActionText(device: DeviceEntry): string {
    let phase: string = this.getHostPhase(device);
    if (this.isCurrentHost(device)) return '当前';
    if (phase === HostPhase.CONNECTING) return '连接中';
    if (phase === HostPhase.RECONNECTING) return '重连中';
    if (phase === HostPhase.WAITING_HOST) return '等待主机';
    if (phase === HostPhase.ERROR) return '重试';
    if (HostRuntimeStore.isOnline(HostRuntimeStore.activeHostKey)) return '切换';
    return '连接';
  }

  getPhaseLabel(phase: string): string {
    if (phase === HostPhase.ONLINE) return '已连接';
    if (phase === HostPhase.SYNCING) return '同步中';
    if (phase === HostPhase.CONNECTING) return '连接中';
    if (phase === HostPhase.RECONNECTING) return '重连中';
    if (phase === HostPhase.WAITING_HOST) return '等待主机';
    if (phase === HostPhase.OFFLINE) return '离线';
    if (phase === HostPhase.ERROR) return '连接失败';
    return '未检测';
  }

  getPhaseColor(phase: string): Resource {
    if (phase === HostPhase.ONLINE || phase === HostPhase.SYNCING) return Colors.success;
    if (phase === HostPhase.CONNECTING || phase === HostPhase.RECONNECTING || phase === HostPhase.WAITING_HOST) {
      return Colors.warning;
    }
    if (phase === HostPhase.ERROR) return Colors.error;
    return Colors.foregroundMuted;
  }

  isKnownRelayUrl(url: string): boolean {
    return url.indexOf('relay.anywhere12138.lat') >= 0 || url.indexOf('35.212.155.17') >= 0;
  }

  isRelayClientUrl(url: string): boolean {
    return this.isKnownRelayUrl(url) && url.indexOf('targetHostId=') >= 0;
  }

  isDirectIpv6Url(url: string): boolean {
    return url.startsWith('ws://[') || url.startsWith('wss://[');
  }

  getConnectionType(device: DeviceEntry): string {
    let phase: string = this.getHostPhase(device);
    let url: string = this.getCurrentAddress(device);
    if (url.length === 0 || phase === HostPhase.OFFLINE || phase === HostPhase.UNKNOWN || phase === HostPhase.ERROR) {
      return '未连接';
    }
    if (this.isRelayClientUrl(url)) return '中继';
    return '直连';
  }

  getRelayStatus(device: DeviceEntry): string {
    if ((device.relayUrl || '').length > 0 || this.isRelayClientUrl(this.getActiveUrl(device))) return '已配置';
    return '未配置';
  }

  getPairingStatus(device: DeviceEntry): string {
    let storedHostId: string = AppStorage.get<string>('hostId') || '';
    let hostEd25519PublicKey: string = AppStorage.get<string>('hostEd25519PublicKey') || '';
    if ((device.hostId || '').length > 0 && storedHostId === device.hostId && hostEd25519PublicKey.length > 0) {
      return '已保存';
    }
    return '缺失';
  }

  shortText(value: string, head: number = 8, tail: number = 4): string {
    if (value.length === 0) return '无';
    if (value.length <= head + tail + 3) return value;
    return value.substring(0, head) + '...' + value.substring(value.length - tail);
  }

  getDirectUrls(device: DeviceEntry): string[] {
    let urls: string[] = [];
    for (let i: number = 0; i < device.urls.length; i++) {
      let url: string = device.urls[i];
      if (this.isDirectIpv6Url(url) || this.isKnownRelayUrl(url) || url.indexOf('targetHostId=') >= 0) {
        continue;
      }
      if (urls.indexOf(url) < 0) {
        urls.push(url);
      }
    }
    return urls;
  }

  getPrimaryDisplayUrl(device: DeviceEntry): string {
    let activeUrl: string = this.getCurrentAddress(device);
    if (activeUrl.length > 0) return activeUrl;
    let directUrls: string[] = this.getDirectUrls(device);
    if (directUrls.length > 0) return directUrls[0];
    if ((device.relayUrl || '').length > 0) return device.relayUrl || '';
    return '';
  }

  submitManualConnect(): void {
    let url: string = this.newUrl.trim();
    if (url.length === 0 || !this.onConnect) return;
    this.onConnect(url);
    this.newUrl = '';
    this.showManualConnect = false;
  }

  toggleHost(device: DeviceEntry): void {
    let hostKey: string = this.getHostKey(device);
    this.expandedHostKey = this.expandedHostKey === hostKey ? '' : hostKey;
  }

  connectHost(index: number, device: DeviceEntry): void {
    if (this.isCurrentHost(device) || this.isBusy(device)) return;
    if (this.onConnectHost) {
      this.onConnectHost(index);
      return;
    }
    let directUrls: string[] = this.getDirectUrls(device);
    if (this.onConnect && directUrls.length > 0) {
      this.onConnect(directUrls[0]);
    }
  }

  showDeleteConfirmDialog(index: number): void {
    let device: DeviceEntry | undefined = HostStore.devices[index];
    let hostName: string = device ? device.name : '';
    this.getUIContext().showAlertDialog({
      title: '删除主机',
      message: hostName + '\n删除后需要重新扫码或手动连接。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: Colors.error,
        action: () => {
          if (this.onDeleteHost) {
            this.onDeleteHost(index);
          }
          if (device && this.expandedHostKey === this.getHostKey(device)) {
            this.expandedHostKey = '';
          }
        }
      }
    });
  }

  @Builder
  SectionTitle(title: string) {
    Row() {
      Text(title)
        .fontSize(FontSize.lg)
        .fontColor(Colors.foreground)
        .fontWeight(FontWeight.Bold)
      Blank()
    }
    .width(Layout.contentWidth)
    .padding({ top: Spacing.xl, bottom: Spacing.sm })
  }

  @Builder
  IconButton(icon: Resource, label: string, action: () => void) {
    Button() {
      Row({ space: Spacing.xs }) {
        Image(icon)
          .width(18)
          .height(18)
          .fillColor(Colors.foreground)
        Text(label)
          .fontSize(FontSize.sm)
          .fontColor(Colors.foreground)
      }
    }
    .height(40)
    .padding({ left: Spacing.md, right: Spacing.md })
    .borderRadius(Radius.sm)
    .backgroundColor(Colors.surface1)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface2) },
      normal: { .backgroundColor(Colors.surface1) }
    })
    .onClick(action)
  }

  @Builder
  DeleteSwipeAction(index: number) {
    Row() {
      Button('删除')
        .height('100%')
        .width(72)
        .fontSize(FontSize.sm)
        .fontColor(Colors.surface0)
        .backgroundColor(Colors.error)
        .borderRadius(Radius.sm)
        .onClick(() => { this.showDeleteConfirmDialog(index); })
    }
    .height('100%')
    .padding({ left: Spacing.xs, right: Spacing.xs })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  HostRow(device: DeviceEntry, index: number) {
    Row() {
      Circle({ width: 7, height: 7 })
        .fill(this.getPhaseColor(this.getHostPhase(device)))
        .margin({ right: Spacing.md })

      Column() {
        Text(device.name)
          .fontSize(FontSize.base)
          .fontColor(Colors.foreground)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: Spacing.xs }) {
          Text(this.getPhaseLabel(this.getHostPhase(device)))
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
          Text('·')
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
          Text(this.getConnectionType(device))
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
          Text('·')
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
          Text(this.shortText(this.getPrimaryDisplayUrl(device), 22, 0))
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .margin({ top: Spacing.xxs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.getActionText(device))
        .height(32)
        .padding({ left: Spacing.md, right: Spacing.md })
        .fontSize(FontSize.xs)
        .fontColor(this.isBusy(device) ? Colors.foregroundMuted : Colors.accent)
        .backgroundColor(Colors.transparent)
        .borderRadius(Radius.sm)
        .enabled(!this.isCurrentHost(device) && !this.isBusy(device))
        .stateStyles({
          pressed: { .backgroundColor(Colors.surface1) },
          normal: { .backgroundColor(Colors.transparent) }
        })
        .onClick(() => { this.connectHost(index, device); })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([Colors.foregroundMuted])
        .rotate({ angle: this.expandedHostKey === this.getHostKey(device) ? 90 : 0 })
        .margin({ left: Spacing.xs })
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
    .borderRadius(Radius.sm)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
  }

  @Builder
  DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
        .width(84)
      Text(value)
        .fontSize(FontSize.sm)
        .fontColor(Colors.foreground)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: Spacing.xxs, bottom: Spacing.xxs })
  }

  @Builder
  HostDetail(device: DeviceEntry, index: number) {
    Column() {
      this.DetailRow('Host ID', this.shortText(device.hostId || '', 12, 6))
      this.DetailRow('连接方式', this.getConnectionType(device))
      this.DetailRow('Relay', this.getRelayStatus(device))
      this.DetailRow('配对密钥', this.getPairingStatus(device))
      this.DetailRow('当前地址', this.getCurrentAddress(device).length > 0 ? this.getCurrentAddress(device) : '未连接')

      Column() {
        Text('IPv4 地址')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .width('100%')
          .margin({ top: Spacing.sm, bottom: Spacing.xxs })
        if (this.getDirectUrls(device).length === 0) {
          Text('暂无可自动连接的 IPv4 地址')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .width('100%')
        } else {
          ForEach(this.getDirectUrls(device), (url: string) => {
            Text(url)
              .fontSize(FontSize.sm)
              .fontColor(Colors.foreground)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ top: Spacing.xxs, bottom: Spacing.xxs })
          }, (url: string) => url)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Row({ space: Spacing.sm }) {
        Button('重新连接')
          .height(36)
          .padding({ left: Spacing.md, right: Spacing.md })
          .fontSize(FontSize.sm)
          .fontColor(Colors.accent)
          .backgroundColor(Colors.surface1)
          .borderRadius(Radius.sm)
          .onClick(() => { this.connectHost(index, device); })
        Button('重新扫码')
          .height(36)
          .padding({ left: Spacing.md, right: Spacing.md })
          .fontSize(FontSize.sm)
          .fontColor(Colors.foreground)
          .backgroundColor(Colors.surface1)
          .borderRadius(Radius.sm)
          .onClick(() => { if (this.onScan) this.onScan(); })
        Button('删除主机')
          .height(36)
          .padding({ left: Spacing.md, right: Spacing.md })
          .fontSize(FontSize.sm)
          .fontColor(Colors.error)
          .backgroundColor(Colors.transparent)
          .borderRadius(Radius.sm)
          .onClick(() => { this.showDeleteConfirmDialog(index); })
      }
      .width('100%')
      .margin({ top: Spacing.md })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Spacing.xxl, right: Spacing.md, bottom: Spacing.md })
  }

  @Builder
  ManualConnectForm() {
    Row({ space: Spacing.sm }) {
      TextInput({ placeholder: 'ws://IP:PORT', text: this.newUrl })
        .layoutWeight(1)
        .height(42)
        .borderRadius(Radius.sm)
        .padding({ left: Spacing.md, right: Spacing.md })
        .fontSize(FontSize.sm)
        .backgroundColor(Colors.surface1)
        .onChange((v: string) => { this.newUrl = v; })
        .onSubmit(() => { this.submitManualConnect(); })
      Button('连接')
        .height(42)
        .padding({ left: Spacing.md, right: Spacing.md })
        .fontWeight(FontWeight.Medium)
        .borderRadius(Radius.sm)
        .fontSize(FontSize.sm)
        .fontColor(Colors.accent)
        .backgroundColor(Colors.transparent)
        .onClick(() => { this.submitManualConnect(); })
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, bottom: Spacing.md })
  }

  @Builder
  PreferenceRow(title: string, description: string, isOn: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Column() {
        Text(title)
          .fontSize(FontSize.base)
          .fontColor(Colors.foreground)
          .fontWeight(FontWeight.Medium)
        Text(description)
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .margin({ top: Spacing.xxs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn })
        .selectedColor(Colors.foreground)
        .onChange(onChange)
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
    .backgroundColor(Colors.transparent)
    .borderRadius(Radius.sm)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          this.SectionTitle('连接与主机')

          Row({ space: Spacing.sm }) {
            this.IconButton($r('app.media.ic_scan'), '扫码添加', () => { if (this.onScan) this.onScan(); })
            this.IconButton($r('app.media.ic_link'), '手动连接', () => {
              this.showManualConnect = !this.showManualConnect;
            })
          }
          .width(Layout.contentWidth)
          .padding({ bottom: this.showManualConnect ? Spacing.sm : Spacing.md })

          List({ space: Spacing.xs }) {
            if (this.showManualConnect) {
              ListItem() {
                this.ManualConnectForm()
              }
            }

            if (HostStore.devices.length === 0) {
              ListItem() {
                Text('暂无已保存的主机')
                  .fontSize(FontSize.sm)
                  .fontColor(Colors.foregroundMuted)
                  .width('100%')
                  .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
              }
            } else {
              ForEach(HostStore.devices, (device: DeviceEntry, index: number) => {
                ListItemGroup() {
                  ListItem() {
                    this.HostRow(device, index)
                  }
                  .onClick(() => { this.toggleHost(device); })
                  .swipeAction({
                    end: {
                      builder: () => {
                        this.DeleteSwipeAction(index)
                      },
                      onAction: () => { this.showDeleteConfirmDialog(index); },
                      actionAreaDistance: 72
                    }
                  })

                  if (this.expandedHostKey === this.getHostKey(device)) {
                    ListItem() {
                      this.HostDetail(device, index)
                    }
                  }
                }
              }, (device: DeviceEntry, index: number) => (device.hostId || device.name) + ':' + index.toString() + ':' + this.expandedHostKey)
            }
          }
          .width(Layout.contentWidth)

          this.SectionTitle('偏好设置')

          List({ space: Spacing.xs }) {
            ListItem() {
              this.PreferenceRow('Thinking 默认展开', '流式结束后自动展开思考内容', this.thinkingExpanded, (isOn: boolean) => {
                this.thinkingExpanded = isOn;
                StorageService.getInstance().putString('pref_thinking_expanded', isOn ? '1' : '0');
              })
            }

            ListItem() {
              this.PreferenceRow('工具调用默认展开', '完成后自动展开工具调用详情', this.toolcallExpanded, (isOn: boolean) => {
                this.toolcallExpanded = isOn;
                StorageService.getInstance().putString('pref_toolcall_expanded', isOn ? '1' : '0');
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
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface0)
  }
}
