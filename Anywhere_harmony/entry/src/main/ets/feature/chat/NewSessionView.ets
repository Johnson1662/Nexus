import { Colors, FontSize, Spacing, Radius, Shadow } from '../../constants/DesignTokens';
import { WorkspaceStore, WorkspaceInfo } from '../../common/model/WorkspaceInfo';
import { ChatStore } from '../../common/model/ChatState';
import { DeviceAgentStore } from '../../common/model/DeviceAgentStore';
import { AgentInfo } from '../../common/websocket/WSProtocol';
import { CustomIcon } from '../../common/ui/CustomIcon';

class AgentOption {
  name: string = '';
  title: string = '';
}

@Component
export struct NewSessionView {
  @Prop initialWorkspaceIndex: number = -1;
  onClose?: () => void;
  onCreateSession?: (workspaceIndex: number, agentName: string, prompt: string) => void;

  @State stepIndex: number = 0;
  @State selectedWorkspaceIndex: number = -1;
  @State selectedAgentName: string = '';
  @State taskPrompt: string = '';

  aboutToAppear(): void {
    DeviceAgentStore.loadFromDisk();
    if (this.initialWorkspaceIndex >= 0 && this.initialWorkspaceIndex < WorkspaceStore.workspaces.length) {
      this.selectedWorkspaceIndex = this.initialWorkspaceIndex;
    } else if (WorkspaceStore.currentIndex >= 0 && WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length) {
      this.selectedWorkspaceIndex = WorkspaceStore.currentIndex;
    } else if (WorkspaceStore.workspaces.length > 0) {
      this.selectedWorkspaceIndex = 0;
    }
    if (ChatStore.selectedAgentName.length > 0) {
      this.selectedAgentName = ChatStore.selectedAgentName;
    } else if (ChatStore.agentType.length > 0) {
      this.selectedAgentName = ChatStore.agentType;
    } else {
      let agents: AgentOption[] = this.getAvailableAgents();
      if (agents.length > 0) {
        this.selectedAgentName = agents[0].name;
      }
    }
  }

  getAvailableAgents(): AgentOption[] {
    let currentDeviceId: string = ChatStore.currentDeviceId;
    let cachedAgents: AgentInfo[] = currentDeviceId.length > 0 ? DeviceAgentStore.getAgents(currentDeviceId) : [];
    if (cachedAgents.length > 0) {
      let mapped: AgentOption[] = [];
      for (let i: number = 0; i < cachedAgents.length; i++) {
        let option: AgentOption = new AgentOption();
        option.name = cachedAgents[i].name;
        option.title = cachedAgents[i].title || cachedAgents[i].name;
        mapped.push(option);
      }
      return mapped;
    }
    if (this.selectedAgentName.length > 0 || ChatStore.selectedAgentName.length > 0 || ChatStore.agentType.length > 0) {
      let fallback: AgentOption = new AgentOption();
      fallback.name = this.selectedAgentName || ChatStore.selectedAgentName || ChatStore.agentType;
      fallback.title = fallback.name;
      return [fallback];
    }
    return [];
  }

  getWorkspace(): WorkspaceInfo | null {
    if (this.selectedWorkspaceIndex >= 0 && this.selectedWorkspaceIndex < WorkspaceStore.workspaces.length) {
      return WorkspaceStore.workspaces[this.selectedWorkspaceIndex];
    }
    return null;
  }

  canContinue(): boolean {
    if (this.stepIndex === 0) {
      return this.selectedWorkspaceIndex >= 0;
    }
    if (this.stepIndex === 1) {
      return this.selectedAgentName.length > 0;
    }
    return this.taskPrompt.trim().length > 0 && ChatStore.connected;
  }

  handlePrimaryAction(): void {
    if (!this.canContinue()) {
      return;
    }
    if (this.stepIndex < 2) {
      this.stepIndex += 1;
      return;
    }
    this.onCreateSession?.(this.selectedWorkspaceIndex, this.selectedAgentName, this.taskPrompt.trim());
  }

  getPrimaryLabel(): string {
    return this.stepIndex < 2 ? '下一步' : '创建会话';
  }

  getStepTitle(index: number): string {
    if (index === 0) return '选择工作区';
    if (index === 1) return '选择';
    return '任务配置';
  }

  build() {
    NavDestination() {
      Column() {
        this.Header()
        this.Stepper()

        if (this.stepIndex === 0) {
          this.WorkspaceStep()
        } else if (this.stepIndex === 1) {
          this.AgentStep()
        } else {
          this.TaskStep()
        }

        Button(this.getPrimaryLabel())
          .width('100%')
          .height(52)
          .fontSize(FontSize.base)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.surface0)
          .backgroundColor(this.canContinue() ? Colors.foreground : Colors.border)
          .borderRadius(Radius.lg)
          .enabled(this.canContinue())
          .margin({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xl })
          .onClick(() => { this.handlePrimaryAction(); })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }

  @Builder
  Header() {
    Row() {
      Button(this.stepIndex === 0 ? '取消' : '上一步')
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
        .backgroundColor(Colors.transparent)
        .padding(0)
        .onClick(() => {
          if (this.stepIndex === 0) {
            this.onClose?.();
          } else {
            this.stepIndex -= 1;
          }
        })
      Blank()
      Text('新建会话')
        .fontSize(FontSize.base)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
      Blank()
      Column().width(44)
    }
    .width('100%')
    .padding({ top: Spacing.xxxl, left: Spacing.xl, right: Spacing.xl, bottom: Spacing.lg })
  }

  @Builder
  Stepper() {
    Row() {
      ForEach([0, 1, 2], (index: number) => {
        Row() {
          Row() {
            Text((index + 1).toString())
              .fontSize(FontSize.xs)
              .fontWeight(FontWeight.Medium)
              .fontColor(index <= this.stepIndex ? Colors.surface0 : Colors.foregroundMuted)
          }
          .width(22)
          .height(22)
          .borderRadius(Radius.full)
          .backgroundColor(index <= this.stepIndex ? Colors.foreground : Colors.surface1)
          .justifyContent(FlexAlign.Center)

          Text(this.getStepTitle(index))
            .fontSize(FontSize.xs)
            .fontColor(index === this.stepIndex ? Colors.foreground : Colors.foregroundMuted)
            .margin({ left: Spacing.sm, right: Spacing.sm })

          if (index < 2) {
            Column()
              .width(28)
              .height(1)
              .backgroundColor(index < this.stepIndex ? Colors.foreground : Colors.borderLight)
          }
        }
      }, (index: number) => index.toString())
    }
    .width('100%')
    .padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xl })
  }

  @Builder
  WorkspaceStep() {
    Column() {
      Text('选择工作区')
        .fontSize(FontSize.xxxl)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .width('100%')
        .margin({ bottom: Spacing.xs })
      Text('选择这次会话要进入的目录。')
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
        .width('100%')
        .margin({ bottom: Spacing.xl })

      if (WorkspaceStore.workspaces.length === 0) {
        Column() {
          Text('还没有工作区。先在 Chat 或 Workspace 侧边栏里添加项目路径，再回来创建会话。')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: Spacing.md })
      } else {
        List({ space: Spacing.md }) {
          ForEach(WorkspaceStore.workspaces, (workspace: WorkspaceInfo, index: number) => {
            ListItem() {
              this.WorkspaceRow(workspace, index)
            }
          }, (workspace: WorkspaceInfo) => workspace.id)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xl })
  }

  @Builder
  WorkspaceRow(workspace: WorkspaceInfo, index: number) {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.folder'))
          .fontSize(18)
          .fontColor([Colors.foreground])
      }
      .width(40)
      .height(40)
      .borderRadius(Radius.md)
      .backgroundColor(Colors.surface1)
      .justifyContent(FlexAlign.Center)
      .margin({ right: Spacing.md })

      Column() {
        Text(workspace.name)
          .fontSize(FontSize.md)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .maxLines(1)
        Text(workspace.path)
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: Spacing.xxs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.selectedWorkspaceIndex === index) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(22)
          .fontColor([Colors.foreground])
      } else {
        SymbolGlyph($r('sys.symbol.circle'))
          .fontSize(22)
          .fontColor([Colors.border])
      }
    }
    .width('100%')
    .padding(Spacing.lg)
    .backgroundColor(Colors.transparent)
    .onClick(() => { this.selectedWorkspaceIndex = index; })
    .stateStyles({
      pressed: {
        .backgroundColor(Colors.surface1)
      },
      normal: {
        .backgroundColor(Colors.transparent)
      }
    })
  }

  @Builder
  AgentStep() {
    Column() {
      Text('选择')
        .fontSize(FontSize.xxxl)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .width('100%')
        .margin({ bottom: Spacing.xs })
      Text('选择这次任务要交给谁。')
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
        .width('100%')
        .margin({ bottom: Spacing.xl })

      if (this.getAvailableAgents().length === 0) {
        Column() {
          Text('暂无可用 Agent。先连接设备并在引导页发现 Agent，或至少选中过一次 Agent。')
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: Spacing.md })
      } else {
        List({ space: Spacing.md }) {
          ForEach(this.getAvailableAgents(), (agent: AgentOption) => {
            ListItem() {
              this.AgentRow(agent)
            }
          }, (agent: AgentOption) => agent.name)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xl })
  }

  @Builder
  AgentRow(agent: AgentOption) {
    Row() {
      Row() {
        CustomIcon({ name: 'model', iconSize: 18, color: Colors.foreground })
      }
      .width(40)
      .height(40)
      .borderRadius(Radius.md)
      .backgroundColor(Colors.surface1)
      .justifyContent(FlexAlign.Center)
      .margin({ right: Spacing.md })

      Column() {
        Text(agent.title || agent.name)
          .fontSize(FontSize.md)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
        Text(agent.name)
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .margin({ top: Spacing.xxs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.selectedAgentName === agent.name) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(22)
          .fontColor([Colors.foreground])
      } else {
        SymbolGlyph($r('sys.symbol.circle'))
          .fontSize(22)
          .fontColor([Colors.border])
      }
    }
    .width('100%')
    .padding(Spacing.lg)
    .backgroundColor(Colors.transparent)
    .onClick(() => { this.selectedAgentName = agent.name; })
    .stateStyles({
      pressed: {
        .backgroundColor(Colors.surface1)
      },
      normal: {
        .backgroundColor(Colors.transparent)
      }
    })
  }

  @Builder
  TaskStep() {
    Column() {
      Text('任务配置')
        .fontSize(FontSize.xxxl)
        .fontWeight(FontWeight.Bold)
        .fontColor(Colors.foreground)
        .width('100%')
        .margin({ bottom: Spacing.xs })
      Text('写下你要它现在开始做的事。')
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
        .width('100%')
        .margin({ bottom: Spacing.xl })

      Column() {
        this.SummaryRow('工作区', this.getWorkspace()?.name || '未选择')
        this.SummaryRow('Agent', this.selectedAgentName || '未选择')
        this.SummaryRow('连接状态', ChatStore.connected ? '已连接' : '未连接')
      }
      .width('100%')
      .margin({ bottom: Spacing.xl })

      Column() {
        Text('任务描述')
          .fontSize(FontSize.sm)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .width('100%')
          .margin({ bottom: Spacing.sm })
        TextArea({
          placeholder: '例如：实现登录鉴权，使用 Next.js + Tailwind CSS，并补齐路由与表单校验',
          text: this.taskPrompt
        })
          .height(180)
          .backgroundColor(Colors.surface1)
          .borderRadius(Radius.lg)
          .padding(Spacing.md)
          .fontSize(FontSize.base)
          .fontColor(Colors.foreground)
          .placeholderColor(Colors.foregroundMuted)
          .onChange((value: string) => { this.taskPrompt = value; })
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xl })
  }

  @Builder
  SummaryRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(FontSize.sm)
        .fontColor(Colors.foregroundMuted)
      Blank()
      Text(value)
        .fontSize(FontSize.sm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Colors.foreground)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ bottom: Spacing.sm })
  }
}
