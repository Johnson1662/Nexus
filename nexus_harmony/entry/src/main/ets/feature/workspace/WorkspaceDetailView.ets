import { Colors, FontSize, Spacing, Radius, Layout, getLocalizedString, AnimationPresets } from '../../constants/DesignTokens';
import { WorkspaceStore, WorkspaceInfo, ServerSession } from '../../common/model/WorkspaceInfo';
import { ChatStore } from '../../common/model/ChatState';

@Component
export struct WorkspaceDetailView {
  @Prop workspaceIndex: number = 0;
  onBack?: () => void;
  onSelectSession?: (session: ServerSession) => void;
  onNewSession?: (workspaceIndex: number) => void;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  getWorkspace(): WorkspaceInfo {
    if (this.workspaceIndex >= 0 && this.workspaceIndex < WorkspaceStore.workspaces.length) {
      return WorkspaceStore.workspaces[this.workspaceIndex];
    }
    return new WorkspaceInfo();
  }

  getWorkspaceSessions(): ServerSession[] {
    let result: ServerSession[] = [];
    let workspace: WorkspaceInfo = this.getWorkspace();
    for (let i: number = 0; i < ChatStore.sessions.length; i++) {
      let session: ServerSession = ChatStore.sessions[i];
      if (!session.cwd || session.cwd.length === 0 || session.cwd === workspace.path) {
        result.push(session);
      }
    }
    result.sort((a: ServerSession, b: ServerSession) => b.createdAt - a.createdAt);
    return result;
  }

  formatRelativeTime(epoch: number): string {
    if (!epoch || epoch <= 0) return this.text($r('app.string.common_now'));
    let diff: number = Date.now() - epoch;
    let minutes: number = Math.floor(diff / 60000);
    if (minutes < 1) return this.text($r('app.string.common_now'));
    if (minutes < 60) return this.text($r('app.string.common_minutes_ago'), minutes);
    let hours: number = Math.floor(minutes / 60);
    if (hours < 24) return this.text($r('app.string.common_hours_ago'), hours);
    return this.text($r('app.string.common_days_ago'), Math.floor(hours / 24));
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            this.NewSessionButton()

            if (this.getWorkspaceSessions().length === 0) {
              Text($r('app.string.workspace_empty_current'))
                .fontSize(FontSize.sm)
                .fontColor(Colors.foregroundMuted)
                .width(Layout.contentWidth)
                .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md })
            } else {
              List({ space: Spacing.sm }) {
                ForEach(this.getWorkspaceSessions(), (session: ServerSession) => {
                  ListItem() {
                    this.SessionCard(session)
                  }
                }, (session: ServerSession) => session.sessionId)
              }
              .width(Layout.contentWidth)
              .padding({ bottom: Spacing.xxxl })
            }
          }
          .width('100%')
          .padding({ top: Spacing.lg })
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(false)
    .title(this.getWorkspace().name || this.text($r('app.string.workspace_title_fallback')))
    .width('100%')
    .height('100%')
  }

  @Builder
  NewSessionButton() {
    Button() {
      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(16)
          .fontColor([Colors.surface0])
          .margin({ right: Spacing.sm })
        Text($r('app.string.workspace_quick_new_session'))
          .fontSize(FontSize.sm)
          .fontColor(Colors.surface0)
          .fontWeight(FontWeight.Medium)
      }
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width(Layout.contentWidth)
    .height(44)
    .backgroundColor(Colors.foreground)
    .borderRadius(Radius.full)
    .margin({ bottom: Spacing.lg })
    .stateStyles({
      pressed: { .backgroundColor(Colors.accentDark) },
      normal: { .backgroundColor(Colors.foreground) }
    })
    .animation({ duration: 150, curve: AnimationPresets.spring })
    .onClick(() => { this.onNewSession?.(this.workspaceIndex); })
  }

  @Builder
  SessionCard(session: ServerSession) {
    Row() {
      Column() {
        Text(session.title || this.text($r('app.string.common_untitled')))
          .fontSize(FontSize.md)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text((session.agent || this.text($r('app.string.config_agent'))) + ' · ' +
          this.formatRelativeTime(session.createdAt))
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .margin({ top: Spacing.xxs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([Colors.foregroundMuted])
    }
    .width('100%')
    .padding(Spacing.md)
    .onClick(() => { this.onSelectSession?.(session); })
    .stateStyles({
      pressed: { .backgroundColor(Colors.surface1) },
      normal: { .backgroundColor(Colors.transparent) }
    })
  }
}
