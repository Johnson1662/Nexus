import { MessageData, PlanEntry, WorkspaceInfo, ServerSession } from '../store/SessionStore';
import { MessageBubble } from './MessageBubble';
import { PlanView } from './PlanView';
import { Colors, FontSize, Spacing, Radius } from '../constants/DesignTokens';

interface ModelInfo {
  modelId: string;
  name: string;
}

@Component
export struct WorkspaceDetailView {
  @Prop messages: MessageData[] = [];
  @Prop planEntries: PlanEntry[] = [];
  @Prop currentWorkspace: WorkspaceInfo | null = null;
  @Prop connected: boolean = false;
  @Prop turnActive: boolean = false;
  @Prop showSessionMenu: boolean = false;
  @Prop workspaceSessions: ServerSession[] = [];
  @Prop activeSessionId: string = '';
  @Prop inputText: string = '';
  @Prop allModels: ModelInfo[] = [];
  @Prop selectedModelIndex: number = 0;
  
  onOpenDrawer?: () => void;
  onNewSession?: () => void;
  onToggleSessionMenu?: () => void;
  onSelectSession?: (session: ServerSession) => void;
  onInputChange?: (text: string) => void;
  onSendMessage?: () => void;
  onModelChange?: (index: number) => void;

  build() {
    Stack() {
      Column() {
        // Top bar
        Row() {
          Row() {
            Text('☰')
              .fontSize(20)
              .fontColor(Colors.foreground)
          }
          .width(40)
          .height(40)
          .borderRadius(Radius.md)
          .backgroundColor(Colors.surface1)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            if (this.onOpenDrawer) {
              this.onOpenDrawer();
            }
          })

          Column() {
            Text(this.currentWorkspace ? this.currentWorkspace.name : '')
              .fontSize(FontSize.lg)
              .fontWeight(FontWeight.Medium)
              .fontColor(Colors.foreground)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row() {
              Circle()
                .width(6)
                .height(6)
                .fill(this.connected ? Colors.success : Colors.error)
                .margin({ right: Spacing.xs })

              Text(this.connected ? (this.turnActive ? '思考中...' : '就绪') : '离线')
                .fontSize(FontSize.xs)
                .fontColor(Colors.foregroundMuted)
            }
            .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: Spacing.md, right: Spacing.md })

          Row() {
            Row() {
              Text(this.workspaceSessions.length.toString())
                .fontSize(FontSize.xxs)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Bold)
            }
            .width(20)
            .height(20)
            .backgroundColor(this.showSessionMenu ? Colors.accent : Colors.foregroundMuted)
            .borderRadius(10)
            .justifyContent(FlexAlign.Center)
            .margin({ right: 4 })

            Text(this.showSessionMenu ? '▴' : '▾')
              .fontSize(10)
              .fontColor(Colors.foreground)
          }
          .height(38)
          .padding({ left: Spacing.md, right: Spacing.md })
          .backgroundColor(this.showSessionMenu ? Colors.accentLight : Colors.surface1)
          .borderRadius(Radius.lg)
          .onClick(() => {
            if (this.onToggleSessionMenu) {
              this.onToggleSessionMenu();
            }
          })

          Row() {
            Text('+')
              .fontSize(22)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          .width(40)
          .height(40)
          .backgroundColor(Colors.accent)
          .borderRadius(Radius.lg)
          .justifyContent(FlexAlign.Center)
          .margin({ left: Spacing.sm })
          .shadow({ radius: 8, color: Colors.shadowAccent, offsetY: 3 })
          .onClick(() => {
            if (this.onNewSession) {
              this.onNewSession();
            }
          })
        }
        .width('100%')
        .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
        .backgroundColor(Colors.surfaceElevated)
        .shadow({ radius: 4, color: Colors.shadowColor, offsetY: 2 })

        Divider()
          .color(Colors.borderLight)
          .width('100%')
          .height(1)

        // Message area
        if (this.messages.length === 0 && this.planEntries.length === 0) {
          Column() {
            Text('💬')
              .fontSize(48)
              .margin({ bottom: Spacing.md })

            Text('开始对话')
              .fontSize(FontSize.xl)
              .fontColor(Colors.foregroundMuted)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.messages, (msg: MessageData) => {
              ListItem() {
                MessageBubble({ message: msg })
              }
            }, (msg: MessageData) => msg.id + '_v' + msg.version.toString())

            if (this.planEntries.length > 0) {
              ListItem() {
                PlanView({ entries: this.planEntries })
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .backgroundColor(Colors.surface0)
          .padding({ top: Spacing.sm, bottom: Spacing.xs })
          .scrollBar(BarState.Off)
        }

        // Input area
        Column() {
          Row() {
            TextInput({ placeholder: '输入消息...', text: this.inputText })
              .layoutWeight(1)
              .height(48)
              .backgroundColor(Colors.surface0)
              .borderRadius(Radius.xxl)
              .border({
                width: 1.5,
                color: this.inputText.trim().length > 0 ? Colors.borderFocus : Colors.borderLight
              })
              .padding({ left: Spacing.lg, right: Spacing.lg })
              .onChange((value: string) => {
                if (this.onInputChange) {
                  this.onInputChange(value);
                }
              })
              .onSubmit(() => {
                if (this.onSendMessage) {
                  this.onSendMessage();
                }
              })

            Row() {
              Text('↑')
                .fontSize(18)
                .fontColor(Color.White)
                .fontWeight(FontWeight.Bold)
            }
            .width(48)
            .height(48)
            .backgroundColor(this.inputText.trim().length > 0 ? Colors.accent : Colors.surface2)
            .borderRadius(Radius.xxl)
            .justifyContent(FlexAlign.Center)
            .margin({ left: Spacing.sm })
            .shadow({
              radius: this.inputText.trim().length > 0 ? 8 : 0,
              color: this.inputText.trim().length > 0 ? Colors.shadowAccent : 'transparent',
              offsetY: this.inputText.trim().length > 0 ? 3 : 0
            })
            .onClick(() => {
              if (this.onSendMessage) {
                this.onSendMessage();
              }
            })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.lg })
        .backgroundColor(Colors.surfaceElevated)
        .shadow({ radius: 8, color: Colors.shadowColor, offsetY: -3 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.surfaceElevated)

      // Session menu overlay
      if (this.showSessionMenu) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#00000030')
          .onClick(() => {
            if (this.onToggleSessionMenu) {
              this.onToggleSessionMenu();
            }
          })

        Column() {
          Row() {
            Text('会话列表')
              .fontSize(FontSize.xl)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.foreground)
              .layoutWeight(1)

            Row() {
              Text('+')
                .fontSize(20)
                .fontColor(Colors.accent)
                .fontWeight(FontWeight.Bold)
            }
            .width(32)
            .height(32)
            .backgroundColor(Colors.accentLight)
            .borderRadius(Radius.md)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              if (this.onNewSession) {
                this.onNewSession();
              }
              if (this.onToggleSessionMenu) {
                this.onToggleSessionMenu();
              }
            })
          }
          .width('100%')
          .padding({ left: Spacing.xl, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.md })

          Divider()
            .color(Colors.borderLight)
            .width('100%')

          if (this.workspaceSessions.length === 0) {
            Column() {
              Text('📝')
                .fontSize(32)
                .margin({ bottom: Spacing.md })

              Text('暂无会话')
                .fontSize(FontSize.base)
                .fontColor(Colors.foregroundMuted)
            }
            .width('100%')
            .padding({ top: Spacing.xxxl, bottom: Spacing.xxxl })
          } else {
            List() {
              ForEach(this.workspaceSessions, (s: ServerSession) => {
                ListItem() {
                  Row() {
                    Row() {
                      Text('💬')
                        .fontSize(16)
                    }
                    .width(36)
                    .height(36)
                    .backgroundColor(s.sessionId === this.activeSessionId ? Colors.accentLight : Colors.surface1)
                    .borderRadius(Radius.md)
                    .justifyContent(FlexAlign.Center)
                    .margin({ right: Spacing.md })

                    Column() {
                      Text(s.title || s.sessionId.substring(0, 8))
                        .fontSize(FontSize.base)
                        .fontColor(s.sessionId === this.activeSessionId ? Colors.accent : Colors.foreground)
                        .fontWeight(s.sessionId === this.activeSessionId ? FontWeight.Medium : FontWeight.Medium)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                      if (s.updatedAt && s.updatedAt.length > 0) {
                        Text(s.updatedAt)
                          .fontSize(FontSize.xxs)
                          .fontColor(Colors.foregroundLight)
                          .margin({ top: 2 })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    if (s.sessionId === this.activeSessionId) {
                      Circle()
                        .width(6)
                        .height(6)
                        .fill(Colors.accent)
                    }
                  }
                  .width('100%')
                  .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.sm, bottom: Spacing.sm })
                  .backgroundColor(s.sessionId === this.activeSessionId ? Colors.accentTransparent : 'transparent')
                  .borderRadius(Radius.md)
                  .onClick(() => {
                    if (this.onSelectSession) {
                      this.onSelectSession(s);
                    }
                    if (this.onToggleSessionMenu) {
                      this.onToggleSessionMenu();
                    }
                  })
                }
                .margin({ left: Spacing.sm, right: Spacing.sm, top: Spacing.xxs, bottom: Spacing.xxs })
              }, (s: ServerSession) => s.sessionId)
            }
            .constraintSize({ maxHeight: 360 })
            .width('100%')
            .padding({ top: Spacing.sm, bottom: Spacing.md })
          }
        }
        .width('92%')
        .backgroundColor(Colors.surfaceElevated)
        .borderRadius(Radius.xl)
        .shadow({ radius: 20, color: Colors.shadowColorStrong, offsetY: 6 })
        .margin({ top: 70 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
