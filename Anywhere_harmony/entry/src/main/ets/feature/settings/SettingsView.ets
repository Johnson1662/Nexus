import { Colors, FontSize, Spacing, Radius, Layout, getLocalizedString } from '../../constants/DesignTokens';
import { StorageService, PrefsKeys } from '../../services/StorageService';
import { AppPreferenceService } from '../../services/AppPreferenceService';
import { HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { HostPhase, HostRuntimeStore, HostRuntimeState } from '../../common/model/HostState';

@Component
export struct SettingsPage {
  @StorageLink('pref_thinking_expanded') thinkingExpanded: boolean = true;
  @StorageLink('pref_toolcall_expanded') toolcallExpanded: boolean = true;
  @StorageLink('pref_app_language') appLanguage: string = AppPreferenceService.LANGUAGE_SYSTEM;
  @StorageLink('pref_color_mode') colorMode: string = AppPreferenceService.COLOR_SYSTEM;
  @StorageLink('serverUrl') serverUrl: string = '';
  @State showManualConnect: boolean = false;
  @State newUrl: string = '';
  @State expandedHostKey: string = '';
  @State showAllAddresses: boolean = false;
  @State expandedSettingKey: string = '';
  private preferenceLoadId: number = 0;
  private languageTouched: boolean = false;
  private colorModeTouched: boolean = false;
  onConnect?: (url: string) => void;
  onConnectHost?: (index: number) => void;
  onDeleteHost?: (index: number) => void;
  onScan?: () => void;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  aboutToAppear(): void {
    this.preferenceLoadId += 1;
    let loadId: number = this.preferenceLoadId;
    this.languageTouched = false;
    this.colorModeTouched = false;
    StorageService.getInstance().getString(PrefsKeys.APP_LANGUAGE, AppPreferenceService.LANGUAGE_SYSTEM)
      .then((value: string) => {
        if (loadId !== this.preferenceLoadId || this.languageTouched) return;
        this.appLanguage = AppPreferenceService.normalizeLanguage(value);
        AppPreferenceService.setPreferenceState('pref_app_language', this.appLanguage);
      })
      .catch(() => {});
    StorageService.getInstance().getString(PrefsKeys.COLOR_MODE, AppPreferenceService.COLOR_SYSTEM)
      .then((value: string) => {
        if (loadId !== this.preferenceLoadId || this.colorModeTouched) return;
        this.colorMode = AppPreferenceService.normalizeColorMode(value);
        AppPreferenceService.setPreferenceState('pref_color_mode', this.colorMode);
      })
      .catch(() => {});
  }

  getLanguageLabel(value: string): string {
    let normalized: string = AppPreferenceService.normalizeLanguage(value);
    if (normalized === AppPreferenceService.LANGUAGE_ZH) return this.text($r('app.string.settings_language_zh'));
    if (normalized === AppPreferenceService.LANGUAGE_EN) return this.text($r('app.string.settings_language_en'));
    return this.text($r('app.string.settings_language_system'));
  }

  getColorModeLabel(value: string): string {
    let normalized: string = AppPreferenceService.normalizeColorMode(value);
    if (normalized === AppPreferenceService.COLOR_LIGHT) return this.text($r('app.string.settings_color_light'));
    if (normalized === AppPreferenceService.COLOR_DARK) return this.text($r('app.string.settings_color_dark'));
    return this.text($r('app.string.settings_color_system'));
  }

  toggleSetting(key: string): void {
    this.expandedSettingKey = this.expandedSettingKey === key ? '' : key;
  }

  showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
    } catch (_err) {}
  }

  selectLanguage(value: string): void {
    let normalized: string = AppPreferenceService.normalizeLanguage(value);
    this.languageTouched = true;
    if (!AppPreferenceService.applyLanguage(normalized)) {
      this.showToast(this.text($r('app.string.settings_apply_failed')));
      return;
    }
    this.appLanguage = normalized;
    AppPreferenceService.setPreferenceState('pref_app_language', normalized);
    StorageService.getInstance().putString(PrefsKeys.APP_LANGUAGE, normalized).catch(() => {});
    this.showToast(this.text($r('app.string.settings_language_applied')));
  }

  selectColorMode(value: string): void {
    let normalized: string = AppPreferenceService.normalizeColorMode(value);
    this.colorModeTouched = true;
    let applied: boolean = false;
    try {
      let context = this.getUIContext().getHostContext();
      if (context) {
        applied = AppPreferenceService.applyColorMode(context, normalized);
      }
    } catch (_err) {}
    if (!applied) {
      this.showToast(this.text($r('app.string.settings_apply_failed')));
      return;
    }
    this.colorMode = normalized;
    AppPreferenceService.setPreferenceState('pref_color_mode', normalized);
    StorageService.getInstance().putString(PrefsKeys.COLOR_MODE, normalized).catch(() => {});
  }

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
    if (this.isCurrentHost(device)) return this.text($r('app.string.settings_action_current'));
    if (phase === HostPhase.CONNECTING) return this.text($r('app.string.settings_action_connecting'));
    if (phase === HostPhase.RECONNECTING) return this.text($r('app.string.settings_action_reconnecting'));
    if (phase === HostPhase.WAITING_HOST) return this.text($r('app.string.settings_action_waiting_host'));
    if (phase === HostPhase.ERROR) return this.text($r('app.string.settings_action_retry'));
    if (HostRuntimeStore.isOnline(HostRuntimeStore.activeHostKey)) return this.text($r('app.string.settings_action_switch'));
    return this.text($r('app.string.settings_action_connect'));
  }

  getPhaseLabel(phase: string): string {
    if (phase === HostPhase.ONLINE) return this.text($r('app.string.settings_phase_online'));
    if (phase === HostPhase.SYNCING) return this.text($r('app.string.settings_phase_syncing'));
    if (phase === HostPhase.CONNECTING) return this.text($r('app.string.settings_action_connecting'));
    if (phase === HostPhase.RECONNECTING) return this.text($r('app.string.settings_action_reconnecting'));
    if (phase === HostPhase.WAITING_HOST) return this.text($r('app.string.settings_action_waiting_host'));
    if (phase === HostPhase.OFFLINE) return this.text($r('app.string.settings_phase_offline'));
    if (phase === HostPhase.ERROR) return this.text($r('app.string.settings_phase_error'));
    return this.text($r('app.string.settings_phase_unknown'));
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
      return this.text($r('app.string.settings_connection_unconnected'));
    }
    if (this.isRelayClientUrl(url)) return this.text($r('app.string.settings_connection_relay'));
    return this.text($r('app.string.settings_connection_direct'));
  }

  getRelayStatus(device: DeviceEntry): string {
    if ((device.relayUrl || '').length > 0 || this.isRelayClientUrl(this.getActiveUrl(device))) {
      return this.text($r('app.string.settings_configured'));
    }
    return this.text($r('app.string.settings_unconfigured'));
  }

  getPairingStatus(device: DeviceEntry): string {
    let storedHostId: string = AppStorage.get<string>('hostId') || '';
    let hostEd25519PublicKey: string = AppStorage.get<string>('hostEd25519PublicKey') || '';
    if ((device.hostId || '').length > 0 && storedHostId === device.hostId && hostEd25519PublicKey.length > 0) {
      return this.text($r('app.string.settings_saved'));
    }
    return this.text($r('app.string.settings_missing'));
  }

  shortText(value: string, head: number = 8, tail: number = 4): string {
    if (value.length === 0) return this.text($r('app.string.common_none'));
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
    if (this.expandedHostKey === hostKey) {
      this.expandedHostKey = '';
      this.showAllAddresses = false;
      return;
    }
    this.expandedHostKey = hostKey;
    this.showAllAddresses = false;
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
      title: this.text($r('app.string.settings_delete_host_title')),
      message: this.text($r('app.string.settings_delete_host_message'), hostName),
      primaryButton: {
        value: this.text($r('app.string.common_cancel')),
        action: () => {}
      },
      secondaryButton: {
        value: this.text($r('app.string.common_delete')),
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
  HostSectionTitle() {
    Row() {
      Text($r('app.string.settings_hosts_section'))
        .fontSize(FontSize.lg)
        .fontColor(Colors.foreground)
        .fontWeight(FontWeight.Bold)
        .layoutWeight(1)
      this.ScanIconButton()
      this.SymbolIconButton($r('sys.symbol.plus'), () => {
        this.showManualConnect = !this.showManualConnect;
      })
    }
    .width(Layout.contentWidth)
    .padding({ top: Spacing.xl, bottom: Spacing.sm })
  }

  @Builder
  ScanIconButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.line_viewfinder'))
        .fontSize(20)
        .fontColor([Colors.foreground])
    }
    .width(36)
    .height(36)
    .borderRadius(Radius.full)
    .backgroundColor(Colors.transparent)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface2) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .onClick(() => { if (this.onScan) this.onScan(); })
  }

  @Builder
  SymbolIconButton(symbol: Resource, action: () => void) {
    Button() {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([Colors.foreground])
    }
    .width(36)
    .height(36)
    .borderRadius(Radius.full)
    .backgroundColor(Colors.transparent)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface2) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .onClick(action)
  }

  @Builder
  SettingsDivider(insetLeft: number = Spacing.md) {
    Row()
      .height(1)
      .backgroundColor(Colors.borderLight)
      .margin({ left: insetLeft, right: Spacing.md })
  }

  @Builder
  DeleteSwipeAction(index: number) {
    Row() {
      Button($r('app.string.common_delete'))
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

      if (this.isCurrentHost(device) || this.isBusy(device)) {
        Text(this.getActionText(device))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .margin({ left: Spacing.sm })
      } else {
        Button(this.getActionText(device))
          .height(30)
          .padding({ left: Spacing.sm, right: Spacing.sm })
          .fontSize(FontSize.sm)
          .fontColor(Colors.accent)
          .backgroundColor(Colors.transparent)
          .borderRadius(Radius.sm)
          .stateStyles({
            pressed: { .backgroundColor(Colors.surface1) },
            normal: { .backgroundColor(Colors.transparent) }
          })
          .onClick(() => { this.connectHost(index, device); })
      }

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontColor([Colors.foregroundMuted])
        .rotate({ angle: this.expandedHostKey === this.getHostKey(device) ? 90 : 0 })
        .margin({ left: Spacing.xs })
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface2) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .onClick(() => { this.toggleHost(device); })
  }

  @Builder
  DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
        .width(92)
      Text(value)
        .fontSize(FontSize.sm)
        .fontColor(Colors.foreground)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(38)
    .padding({ top: Spacing.xs, bottom: Spacing.xs })
  }

  @Builder
  HostDetail(device: DeviceEntry, index: number) {
    Column() {
      this.DetailRow(this.text($r('app.string.settings_detail_connection_type')), this.getConnectionType(device))
      this.DetailRow('Relay', this.getRelayStatus(device))
      this.DetailRow('Host ID', this.shortText(device.hostId || '', 12, 6))
      this.DetailRow(this.text($r('app.string.settings_detail_current_address')),
        this.getCurrentAddress(device).length > 0 ? this.getCurrentAddress(device) :
          this.text($r('app.string.settings_connection_unconnected')))

      this.AddressToggleRow(device)

      if (this.showAllAddresses) {
        this.AddressList(device)
      }

      this.HostDetailActionRow(this.text($r('app.string.settings_reconnect')), Colors.accent, () => { this.connectHost(index, device); })
      this.HostDetailActionRow(this.text($r('app.string.settings_rescan')), Colors.foreground, () => { if (this.onScan) this.onScan(); })
      this.HostDetailActionRow(this.text($r('app.string.settings_delete_host_action')), Colors.error, () => { this.showDeleteConfirmDialog(index); })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Spacing.xxl, right: Spacing.md, bottom: Spacing.sm })
  }

  @Builder
  AddressToggleRow(device: DeviceEntry) {
    Row() {
      Text($r('app.string.settings_detail_ipv4_address'))
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
        .width(92)
      Text(this.text($r('app.string.settings_ipv4_count'), this.getDirectUrls(device).length))
        .fontSize(FontSize.sm)
        .fontColor(Colors.foreground)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([Colors.foregroundMuted])
        .rotate({ angle: this.showAllAddresses ? 90 : 0 })
    }
    .width('100%')
    .height(38)
    .padding({ top: Spacing.xs, bottom: Spacing.xs })
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .onClick(() => { this.showAllAddresses = !this.showAllAddresses; })
  }

  @Builder
  AddressList(device: DeviceEntry) {
    Column() {
      if (this.getDirectUrls(device).length === 0) {
        Text($r('app.string.settings_empty_ipv4'))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .width('100%')
          .padding({ top: Spacing.xs, bottom: Spacing.xs })
      } else {
        ForEach(this.getDirectUrls(device), (url: string) => {
          Text(url)
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({ left: 92, top: Spacing.xs, bottom: Spacing.xs })
        }, (url: string) => url)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  HostDetailActionRow(label: string, color: Resource, action: () => void) {
    Button() {
      Row() {
        Text(label)
          .fontSize(FontSize.sm)
          .fontColor(color)
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .height(38)
    .padding({ left: 0, right: 0 })
    .backgroundColor(Colors.transparent)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .onClick(action)
  }

  @Builder
  ManualConnectForm() {
    Column() {
      Row() {
        Text($r('app.string.settings_manual_address'))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .width(56)
        TextInput({ placeholder: 'ws://IP:PORT', text: this.newUrl })
          .layoutWeight(1)
          .height(40)
          .padding({ left: Spacing.sm, right: Spacing.sm })
          .fontSize(FontSize.sm)
          .fontColor(Colors.foreground)
          .placeholderColor(Colors.foregroundLight)
          .backgroundColor(Colors.surface1)
          .borderRadius(Radius.sm)
          .onChange((v: string) => { this.newUrl = v; })
          .onSubmit(() => { this.submitManualConnect(); })
        Button($r('app.string.settings_action_connect'))
          .height(32)
          .padding({ left: Spacing.sm, right: Spacing.sm })
          .fontWeight(FontWeight.Medium)
          .borderRadius(Radius.sm)
          .fontSize(FontSize.sm)
          .fontColor(Colors.accent)
          .backgroundColor(Colors.transparent)
          .stateStyles({
            pressed: { .backgroundColor(Colors.surface1) },
            normal: { .backgroundColor(Colors.transparent) }
          })
          .onClick(() => { this.submitManualConnect(); })
      }
      .width('100%')
      .height(54)

      Row() {
        Text($r('app.string.settings_manual_helper'))
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 56, bottom: Spacing.sm })
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.xs })
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
    .height(62)
    .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
    .backgroundColor(Colors.transparent)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
  }

  @Builder
  SettingSummaryRow(title: string, value: string, key: string) {
    Button() {
      Row() {
        Text(title)
          .fontSize(FontSize.base)
          .fontColor(Colors.foreground)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
        Text(value)
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .margin({ left: Spacing.sm, right: Spacing.xs })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([Colors.foregroundMuted])
          .rotate({ angle: this.expandedSettingKey === key ? 90 : 0 })
      }
      .width('100%')
    }
    .width('100%')
    .height(52)
    .padding({ left: Spacing.md, right: Spacing.md })
    .backgroundColor(Colors.transparent)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .onClick(() => { this.toggleSetting(key); })
  }

  @Builder
  SettingOptionRow(label: string, selected: boolean, action: () => void) {
    Button() {
      Row() {
        Text(label)
          .fontSize(FontSize.md)
          .fontColor(selected ? Colors.foreground : Colors.foregroundMuted)
          .fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
          .layoutWeight(1)
        if (selected) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(16)
            .fontColor([Colors.foreground])
        } else {
          Blank()
            .width(16)
            .height(16)
        }
      }
      .width('100%')
    }
    .width('100%')
    .height(44)
    .padding({ left: Spacing.xxl, right: Spacing.md })
    .backgroundColor(Colors.transparent)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .onClick(action)
  }

  @Builder
  LanguageOptions() {
    Column() {
      this.SettingOptionRow(this.text($r('app.string.settings_language_system')),
        this.appLanguage === AppPreferenceService.LANGUAGE_SYSTEM,
        () => { this.selectLanguage(AppPreferenceService.LANGUAGE_SYSTEM); })
      this.SettingOptionRow(this.text($r('app.string.settings_language_zh')),
        this.appLanguage === AppPreferenceService.LANGUAGE_ZH,
        () => { this.selectLanguage(AppPreferenceService.LANGUAGE_ZH); })
      this.SettingOptionRow(this.text($r('app.string.settings_language_en')),
        this.appLanguage === AppPreferenceService.LANGUAGE_EN,
        () => { this.selectLanguage(AppPreferenceService.LANGUAGE_EN); })
    }
    .width('100%')
    .padding({ bottom: Spacing.xs })
  }

  @Builder
  ColorModeOptions() {
    Column() {
      this.SettingOptionRow(this.text($r('app.string.settings_color_system')),
        this.colorMode === AppPreferenceService.COLOR_SYSTEM,
        () => { this.selectColorMode(AppPreferenceService.COLOR_SYSTEM); })
      this.SettingOptionRow(this.text($r('app.string.settings_color_light')),
        this.colorMode === AppPreferenceService.COLOR_LIGHT,
        () => { this.selectColorMode(AppPreferenceService.COLOR_LIGHT); })
      this.SettingOptionRow(this.text($r('app.string.settings_color_dark')),
        this.colorMode === AppPreferenceService.COLOR_DARK,
        () => { this.selectColorMode(AppPreferenceService.COLOR_DARK); })
    }
    .width('100%')
    .padding({ bottom: Spacing.xs })
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          this.HostSectionTitle()

          List({ space: 0 }) {
            if (this.showManualConnect) {
              ListItem() {
                this.ManualConnectForm()
              }

              if (HostStore.devices.length > 0) {
                ListItem() {
                  this.SettingsDivider()
                }
              }
            }

            if (HostStore.devices.length === 0) {
              ListItem() {
                Text($r('app.string.settings_empty_hosts'))
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

                  if (index < HostStore.devices.length - 1) {
                    ListItem() {
                      this.SettingsDivider()
                    }
                  }
                }
              }, (device: DeviceEntry, index: number) => (device.hostId || device.name) + ':' + index.toString() + ':' + this.expandedHostKey)
            }
          }
          .width(Layout.contentWidth)
          .backgroundColor(Colors.surfaceElevated)
          .borderRadius(Radius.xxl)
          .clip(true)

          this.SectionTitle(this.text($r('app.string.settings_display_section')))

          List({ space: 0 }) {
            ListItem() {
              this.SettingSummaryRow(this.text($r('app.string.settings_language_title')),
                this.getLanguageLabel(this.appLanguage), 'language')
            }

            if (this.expandedSettingKey === 'language') {
              ListItem() {
                this.LanguageOptions()
              }
            }

            ListItem() {
              this.SettingsDivider()
            }

            ListItem() {
              this.SettingSummaryRow(this.text($r('app.string.settings_color_mode_title')),
                this.getColorModeLabel(this.colorMode), 'color')
            }

            if (this.expandedSettingKey === 'color') {
              ListItem() {
                this.ColorModeOptions()
              }
            }
          }
          .width(Layout.contentWidth)
          .backgroundColor(Colors.surfaceElevated)
          .borderRadius(Radius.xxl)
          .clip(true)

          this.SectionTitle(this.text($r('app.string.settings_preferences_section')))

          List({ space: 0 }) {
            ListItem() {
              this.PreferenceRow(this.text($r('app.string.settings_pref_thinking_title')),
                this.text($r('app.string.settings_pref_thinking_desc')), this.thinkingExpanded, (isOn: boolean) => {
                this.thinkingExpanded = isOn;
                StorageService.getInstance().putString('pref_thinking_expanded', isOn ? '1' : '0');
              })
            }

            ListItem() {
              this.SettingsDivider()
            }

            ListItem() {
              this.PreferenceRow(this.text($r('app.string.settings_pref_tool_title')),
                this.text($r('app.string.settings_pref_tool_desc')), this.toolcallExpanded, (isOn: boolean) => {
                this.toolcallExpanded = isOn;
                StorageService.getInstance().putString('pref_toolcall_expanded', isOn ? '1' : '0');
              })
            }
          }
          .width(Layout.contentWidth)
          .backgroundColor(Colors.surfaceElevated)
          .borderRadius(Radius.xxl)
          .clip(true)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ bottom: Spacing.xxxl })
      }
      .width('100%')
      .backgroundColor(Colors.surface1)
    }
    .title(this.text($r('app.string.settings_title')))
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface1)
  }
}
