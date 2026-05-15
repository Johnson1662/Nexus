import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
import { MessageData } from '../../common/model/MessageData';
import { PlanEntry } from '../../common/model/ChatState';
import { MessageCard } from '../../common/ui/MessageCard';
import { PlanView } from '../../common/ui/PlanView';
import { ChatInputBar } from './ChatInputBar';
import { AgentModel, AgentMode } from '../../common/model/AgentConfig';
import { MessageDataSource } from '../../common/ui/MessageDataSource';

@Component
export struct ChatPage {
  @Prop @Watch('onMessagesChange') messages: MessageData[] = [];
  @Prop planEntries: PlanEntry[] = [];
  @Prop turnActive: boolean = false;
  @Prop models: AgentModel[] = [];
  @Prop modes: AgentMode[] = [];
  onSendMessage?: (text: string) => void;
  onSwitchModel?: (index: number) => void;
  onSwitchMode?: (index: number) => void;

  private scroller: Scroller = new Scroller();
  private dataSource: MessageDataSource = new MessageDataSource([]);

  aboutToAppear(): void {
    this.dataSource = new MessageDataSource(this.messages);
  }

  onMessagesChange(): void {
    this.dataSource.updateData(this.messages);
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  build() {
    Column() {
      if (this.messages.length === 0) {
          Column() {
            if (this.turnActive) {
              Column() {
                LoadingProgress().width(20).height(20).color(Colors.accent)
                Text('Waiting for response')
                  .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
                  .margin({ top: Spacing.sm })
              }
              .alignItems(HorizontalAlign.Center)
              .transition(TransitionEffect.OPACITY)
              .animation({ duration: Duration.fast, curve: Curve.EaseInOut })
            } else {
              Column() {
                Text('No active task')
                  .fontSize(FontSize.base).fontColor(Colors.foreground).fontWeight(FontWeight.Medium)
                Text('Type a message below to start a new session.')
                  .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
                  .margin({ top: Spacing.xs })
              }
              .alignItems(HorizontalAlign.Center)
            }
          }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .padding({ left: Spacing.xxl, right: Spacing.xxl })
      } else {
        List({ scroller: this.scroller }) {
          LazyForEach(this.dataSource, (msg: MessageData) => {
            ListItem() {
              if (msg.type === 'plan') {
                PlanView({ entries: this.planEntries })
                  .width('100%')
                  .padding(Spacing.lg)
                  .backgroundColor(Colors.surfaceElevated)
                  .borderRadius(Radius.md)
                  .margin({ bottom: Spacing.sm })
              } else {
                MessageCard({
                  isUser: msg.role === 'user',
                  time: this.formatTime(msg.timestamp),
                  status: (msg.role === 'assistant' && msg.type === 'text'
                    && this.turnActive) ? 'Running' : '',
                  msgContent: msg.content,
                  msgType: msg.type,
                  msgToolName: msg.toolName,
                  msgToolStatus: msg.toolStatus,
                  streaming: this.turnActive && msg.role === 'assistant' && msg.type === 'text'
                })
                  .margin({ bottom: Spacing.xs })
              }
            }
            .height('auto')
          }, (msg: MessageData) => msg.id + msg.content.length)
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .clip(false)
      }

      ChatInputBar({
        models: this.getModelNames(),
        modes: this.getModeNames(),
        disabled: this.turnActive,
        onSend: (text) => { if (this.onSendMessage) this.onSendMessage(text); },
        onModelChange: (i) => { if (this.onSwitchModel) this.onSwitchModel(i); },
        onModeChange: (i) => { if (this.onSwitchMode) this.onSwitchMode(i); }
      })
    }
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }

  getModelNames(): string[] {
    let n: string[] = [];
    for (let i = 0; i < this.models.length; i++) n.push(this.models[i].name);
    return n;
  }

  getModeNames(): string[] {
    let n: string[] = [];
    for (let i = 0; i < this.modes.length; i++) n.push(this.modes[i].name);
    return n;
  }

  formatTime(ts: number): string {
    if (!ts) return '';
    let d = Date.now() - ts;
    let m = Math.floor(d / 60000);
    if (m < 1) return 'now';
    if (m < 60) return m + 'm';
    let h = Math.floor(m / 60);
    if (h < 24) return h + 'h';
    let date = new Date(ts);
    return date.getHours().toString().padStart(2, '0') + ':' + date.getMinutes().toString().padStart(2, '0');
  }
}
