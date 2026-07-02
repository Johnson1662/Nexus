import { Colors, FontSize, Spacing, Radius, AnimationPresets } from '../../constants/DesignTokens';
import { HostStore, DeviceEntry } from '../../common/model/WorkspaceInfo';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { AgentInfo, RegistryAgentInfo } from '../../common/websocket/WSProtocol';

@Component
export struct AgentManageTabItem {
  @Prop itemKey: string = '';
  @Prop name: string = '';
  @Prop currentTab: string = '';
  onSelect?: () => void;

  build() {
    Column() {
      Text(this.name)
        .fontSize(FontSize.md)
        .fontWeight(this.currentTab === this.itemKey ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentTab === this.itemKey ? Colors.foreground : Colors.foregroundMuted)
        .padding({ bottom: Spacing.xs })
      if (this.currentTab === this.itemKey) {
        Divider().strokeWidth(2).color(Colors.foreground).width(24)
      } else {
        Divider().strokeWidth(2).color(Colors.transparent).width(24)
      }
    }
    .padding(Spacing.sm)
    .borderRadius(Radius.md)
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
    .onClick(() => { this.onSelect?.(); })
  }
}

@Component
export struct AgentManageView {
  @Prop deviceIndex: number = 0;
  onBack?: () => void;

  @State currentTab: string = 'installed';
  @State registryAgents: RegistryAgentInfo[] = [];
  @State installedAgents: AgentInfo[] = [];
  @State loading: boolean = false;
  @State searchQuery: string = '';
  @State showCustomForm: boolean = false;
  @State customCommand: string = '';
  @State customArgs: string = '';
  @State customName: string = '';
  @StorageLink('registryAgents') @Watch('onRegistryStrChange') registryAgentsStr: string = '';
  @StorageLink('installedAgents') @Watch('onInstalledStrChange') installedAgentsStr: string = '';

  onRefreshRegistry?: () => void;
  onInstallAgent?: (agentId: string) => void;
  onUninstallAgent?: (agentId: string) => void;
  onInstallCustomAgent?: (command: string, args: string[], name: string) => void;

  aboutToAppear(): void {
    this.loading = true;
    this.parseRegistryFromStorage();
    this.syncInstalledFromDevice();
    if (this.onRefreshRegistry) {
      this.onRefreshRegistry();
    }
    // Timeout: stop loading after 8s even if no response
    setTimeout(() => {
      if (this.loading && this.registryAgents.length === 0) {
        this.loading = false;
      }
    }, 8000);
  }

  onRegistryStrChange(): void {
    this.parseRegistryFromStorage();
  }

  onInstalledStrChange(): void {
    this.parseInstalledFromStorage();
  }

  parseRegistryFromStorage(): void {
    let raw: string = this.registryAgentsStr;
    if (raw.length > 0) {
      try {
        this.registryAgents = JSON.parse(raw) as RegistryAgentInfo[];
        this.loading = false;
      } catch (_e) {}
    }
  }

  parseInstalledFromStorage(): void {
    let raw: string = this.installedAgentsStr;
    if (raw.length > 0) {
      try {
        let parsed: AgentInfo[] = JSON.parse(raw) as AgentInfo[];
        if (parsed.length > 0) {
          this.installedAgents = parsed;
        }
      } catch (_e) {}
    }
  }

  getHostKey(): string {
    if (this.deviceIndex >= 0 && this.deviceIndex < HostStore.devices.length) {
      let d: DeviceEntry = HostStore.devices[this.deviceIndex];
      return d.hostId || d.name;
    }
    return '';
  }

  syncInstalledFromDevice(): void {
    let hostKey: string = this.getHostKey();
    if (hostKey.length === 0) {
      return;
    }
    let all: AgentInfo[] = DeviceAgentStore.getAgents(hostKey);
    let installed: AgentInfo[] = [];
    for (let i: number = 0; i < all.length; i++) {
      if (all[i].installed) {
        installed.push(all[i]);
      }
    }
    if (installed.length > 0) {
      this.installedAgents = installed;
    }
  }

  isRegistryAgentInstalled(agent: RegistryAgentInfo): boolean {
    for (let i: number = 0; i < this.installedAgents.length; i++) {
      let inst: AgentInfo = this.installedAgents[i];
      if (inst.name === agent.id || inst.name === agent.name) {
        return true;
      }
    }
    return false;
  }

  getFilteredRegistryAgents(): RegistryAgentInfo[] {
    let q: string = this.searchQuery.trim().toLowerCase();
    if (q.length === 0) {
      return this.registryAgents;
    }
    let result: RegistryAgentInfo[] = [];
    for (let i: number = 0; i < this.registryAgents.length; i++) {
      let a: RegistryAgentInfo = this.registryAgents[i];
      let name: string = (a.name || '').toLowerCase();
      let desc: string = (a.description || '').toLowerCase();
      if (name.indexOf(q) >= 0 || desc.indexOf(q) >= 0) {
        result.push(a);
      }
    }
    return result;
  }

  getSourceLabel(agent: AgentInfo): string {
    let src: string = agent.source || '';
    if (src.toLowerCase() === 'registry') {
      return 'Registry';
    }
    if (src.toLowerCase() === 'custom') {
      return 'Custom';
    }
    if (src.length > 0) {
      return src;
    }
    return 'Custom';
  }

  deriveNameFromCommand(cmd: string): string {
    let trimmed: string = cmd.trim();
    if (trimmed.length === 0) {
      return '';
    }
    let sep: string = trimmed.indexOf('\\') >= 0 ? '\\' : '/';
    let parts: string[] = trimmed.split(sep);
    let last: string = parts[parts.length - 1];
    return last.length > 0 ? last : trimmed;
  }

  parseCustomArgs(raw: string): string[] {
    let trimmed: string = raw.trim();
    if (trimmed.length === 0) {
      return [];
    }
    let parts: string[] = trimmed.split(' ');
    let result: string[] = [];
    for (let i: number = 0; i < parts.length; i++) {
      if (parts[i].length > 0) {
        result.push(parts[i]);
      }
    }
    return result;
  }

  onCustomCommandChange(value: string): void {
    this.customCommand = value;
    if (this.customName.length === 0 || this.customName === this.deriveNameFromCommand(this.customCommand)) {
      this.customName = this.deriveNameFromCommand(value);
    }
  }

  showUninstallConfirm(agent: AgentInfo): void {
    let label: string = agent.title || agent.name;
    this.getUIContext().showAlertDialog({
      title: '卸载 Agent',
      message: label,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '卸载',
        fontColor: Colors.error,
        action: () => {
          if (this.onUninstallAgent) {
            this.onUninstallAgent(agent.name);
          }
        }
      }
    });
  }

  submitCustomInstall(): void {
    let cmd: string = this.customCommand.trim();
    if (cmd.length === 0) {
      return;
    }
    let name: string = this.customName.trim();
    if (name.length === 0) {
      name = this.deriveNameFromCommand(cmd);
    }
    let args: string[] = this.parseCustomArgs(this.customArgs);
    if (this.onInstallCustomAgent) {
      this.onInstallCustomAgent(cmd, args, name);
    }
    this.customCommand = '';
    this.customArgs = '';
    this.customName = '';
    this.showCustomForm = false;
  }

  build() {
    NavDestination() {
      Column() {
        // Tab bar
        Row() {
          AgentManageTabItem({
            itemKey: 'installed',
            name: '已安装',
            currentTab: this.currentTab,
            onSelect: () => { this.currentTab = 'installed'; }
          })
          AgentManageTabItem({
            itemKey: 'store',
            name: '商店',
            currentTab: this.currentTab,
            onSelect: () => { this.currentTab = 'store'; }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: Spacing.sm, bottom: Spacing.xs })

        // Content — left-aligned, flush with tab bar
        Scroll() {
          Column() {
            if (this.currentTab === 'installed') {
              this.InstalledTabContent()
            } else {
              this.StoreTabContent()
            }
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
          .padding({ bottom: Spacing.xxxl })
        }
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.None)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(false)
    .title('Agent 管理')
    .padding({ left: 0, right: 0, top: 0, bottom: 0 })
    .transition(AnimationPresets.fadeIn)
  }

  @Builder
  StoreTabContent() {
    Column() {
      TextInput({ placeholder: '搜索 Agent', text: this.searchQuery })
        .width('100%')
        .height(44)
        .fontSize(FontSize.md)
        .fontColor(Colors.foreground)
        .placeholderColor(Colors.foregroundMuted)
        .backgroundColor(Colors.surface1)
        .borderRadius(Radius.sm)
        .padding({ left: Spacing.md, right: Spacing.md })
        .onChange((value: string) => { this.searchQuery = value; })

      if (this.loading && this.registryAgents.length === 0) {
        Text('加载中…')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .padding({ top: Spacing.xl })
      } else if (this.registryAgents.length === 0) {
        Text('暂无可用 Agent')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .padding({ top: Spacing.xl })
        Text('请确保 PC 端 Anywhere Server 已更新到最新版本')
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .padding({ top: Spacing.sm })
      } else if (this.getFilteredRegistryAgents().length === 0) {
        Text('无匹配的 Agent')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .padding({ top: Spacing.xl })
      } else {
        Column() {
          ForEach(this.getFilteredRegistryAgents(), (agent: RegistryAgentInfo) => {
            this.RegistryAgentRow(agent)
          }, (agent: RegistryAgentInfo) => agent.id)
        }
        .width('100%')
        .backgroundColor(Colors.surfaceElevated)
        .borderRadius(Radius.md)
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
      }
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md })
  }

  @Builder
  RegistryAgentRow(agent: RegistryAgentInfo) {
    Row() {
      Column() {
        Text(agent.name)
          .fontSize(FontSize.md)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if ((agent.description || '').length > 0) {
          Text(agent.description)
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
            .margin({ top: Spacing.xxs })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ right: Spacing.md })

      if (this.isRegistryAgentInstalled(agent)) {
        Text('已安装')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
      } else {
        Button('安装')
          .type(ButtonType.Normal)
          .height(36)
          .fontSize(FontSize.sm)
          .fontColor(Colors.surface0)
          .backgroundColor(Colors.accent)
          .borderRadius(Radius.sm)
          .onClick(() => {
            if (this.onInstallAgent) {
              this.onInstallAgent(agent.id);
            }
          })
          .stateStyles({
            pressed: { .backgroundColor(Colors.accentDark) },
            normal: { .backgroundColor(Colors.accent) }
          })
      }
    }
    .width('100%')
    .padding({ top: Spacing.md, bottom: Spacing.md })
  }

  @Builder
  InstalledTabContent() {
    Column() {
      if (this.installedAgents.length === 0) {
        Text('尚未安装任何 Agent')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .padding({ top: Spacing.xl, bottom: Spacing.sm })
        Button('前往商店安装')
          .type(ButtonType.Normal)
          .height(40)
          .fontSize(FontSize.md)
          .fontColor(Colors.surface0)
          .backgroundColor(Colors.accent)
          .borderRadius(Radius.sm)
          .onClick(() => { this.currentTab = 'store'; })
          .stateStyles({
            pressed: { .backgroundColor(Colors.accentDark) },
            normal: { .backgroundColor(Colors.accent) }
          })
      } else {
        Column() {
          ForEach(this.installedAgents, (agent: AgentInfo) => {
            this.InstalledAgentRow(agent)
          }, (agent: AgentInfo) => agent.name)
        }
        .width('100%')
        .backgroundColor(Colors.surfaceElevated)
        .borderRadius(Radius.md)
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.sm, bottom: Spacing.sm })
        .margin({ bottom: Spacing.lg })
      }

      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([Colors.accent])
          .margin({ right: Spacing.sm })
        Text('添加自定义 Agent')
          .fontSize(FontSize.md)
          .fontColor(Colors.accent)
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding(Spacing.md)
      .borderRadius(Radius.md)
      .backgroundColor(Colors.surface1)
      .onClick(() => { this.showCustomForm = !this.showCustomForm; })
      .stateStyles({
        pressed: { .backgroundColor(Colors.surface2) },
        normal: { .backgroundColor(Colors.surface1) }
      })

      if (this.showCustomForm) {
        Column() {
          TextInput({ placeholder: '命令路径', text: this.customCommand })
            .width('100%')
            .height(44)
            .fontSize(FontSize.md)
            .backgroundColor(Colors.surface1)
            .borderRadius(Radius.sm)
            .padding({ left: Spacing.md, right: Spacing.md })
            .margin({ bottom: Spacing.md })
            .onChange((value: string) => { this.onCustomCommandChange(value); })

          TextInput({ placeholder: '参数（空格分隔）', text: this.customArgs })
            .width('100%')
            .height(44)
            .fontSize(FontSize.md)
            .backgroundColor(Colors.surface1)
            .borderRadius(Radius.sm)
            .padding({ left: Spacing.md, right: Spacing.md })
            .margin({ bottom: Spacing.md })
            .onChange((value: string) => { this.customArgs = value; })

          TextInput({ placeholder: '名称', text: this.customName })
            .width('100%')
            .height(44)
            .fontSize(FontSize.md)
            .backgroundColor(Colors.surface1)
            .borderRadius(Radius.sm)
            .padding({ left: Spacing.md, right: Spacing.md })
            .margin({ bottom: Spacing.lg })
            .onChange((value: string) => { this.customName = value; })

          Button('安装')
            .type(ButtonType.Normal)
            .width('100%')
            .height(44)
            .fontSize(FontSize.md)
            .fontColor(Colors.surface0)
            .backgroundColor(Colors.accent)
            .borderRadius(Radius.sm)
            .onClick(() => { this.submitCustomInstall(); })
            .stateStyles({
              pressed: { .backgroundColor(Colors.accentDark) },
              normal: { .backgroundColor(Colors.accent) }
            })
        }
        .width('100%')
        .margin({ top: Spacing.lg })
      }
    }
    .width('100%')
    .padding({ left: Spacing.md, right: Spacing.md })
  }

  @Builder
  InstalledAgentRow(agent: AgentInfo) {
    Row() {
      Column() {
        Text(agent.title || agent.name)
          .fontSize(FontSize.md)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.getSourceLabel(agent))
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .margin({ top: Spacing.xxs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ right: Spacing.md })

      Button('卸载')
        .type(ButtonType.Normal)
        .height(36)
        .fontSize(FontSize.sm)
        .fontColor(Colors.error)
        .backgroundColor(Colors.errorLight)
        .borderRadius(Radius.sm)
        .onClick(() => { this.showUninstallConfirm(agent); })
        .stateStyles({
          pressed: { .opacity(0.85) },
          normal: { .opacity(1) }
        })
    }
    .width('100%')
    .padding({ top: Spacing.md, bottom: Spacing.md })
  }
}
