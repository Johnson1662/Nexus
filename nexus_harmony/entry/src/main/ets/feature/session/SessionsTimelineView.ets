import { Colors, FontSize, Spacing, Radius, Layout, getLocalizedString } from '../../constants/DesignTokens';
import { ChatStore } from '../../common/model/ChatState';
import { ServerSession } from '../../common/model/WorkspaceInfo';

@Component
export struct SessionsTimelineView {
  onSelectSession?: (session: ServerSession) => void;

  text(res: Resource, ...args: Array<string | number>): string {
    let context = this.getUIContext().getHostContext();
    if (!context) return '';
    return getLocalizedString(context, res, ...args);
  }

  formatTime(epoch: number): string {
    if (!epoch || epoch <= 0) return '';
    let d = new Date(epoch);
    return d.getHours().toString().padStart(2, '0') + ':' + d.getMinutes().toString().padStart(2, '0');
  }

  formatRelativeTime(epoch: number): string {
    if (!epoch || epoch <= 0) return '';
    let diff = Date.now() - epoch;
    let mins = Math.floor(diff / 60000);
    if (mins < 1) return this.text($r('app.string.common_now'));
    if (mins < 60) return this.text($r('app.string.common_minutes_ago'), mins);
    let hours = Math.floor(mins / 60);
    if (hours < 24) return this.text($r('app.string.common_hours_ago'), hours);
    return this.text($r('app.string.common_days_ago'), Math.floor(hours / 24));
  }

  getSortedSessions(): ServerSession[] {
    let sorted: ServerSession[] = [];
    for (let i = 0; i < ChatStore.sessions.length; i++) {
      sorted.push(ChatStore.sessions[i]);
    }
    sorted.sort((a, b) => b.createdAt - a.createdAt);
    return sorted;
  }

  getSessionKey(session: ServerSession): string {
    return session.sessionId;
  }

  build() {
    Column() {
      // Header
      Row() {
        Text($r('app.string.session_timeline_title')).fontSize(FontSize.xxxxl).fontWeight(FontWeight.Bold).fontColor(Colors.foreground)
      }
      .width(Layout.contentWidth)
      .padding({ top: Spacing.xxxl, bottom: Spacing.lg })

      if (ChatStore.sessions.length === 0) {
        // Empty state
        Column() {
          Text($r('app.string.session_timeline_empty'))
            .fontSize(FontSize.sm)
            .fontColor(Colors.foregroundMuted)
        }
        .width(Layout.contentWidth)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md })
      } else {
        Scroll() {
          Column() {
            ForEach(this.getSortedSessions(), (session: ServerSession) => {
              this.TimelineItem(session)
            }, (session: ServerSession) => this.getSessionKey(session))
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ bottom: Spacing.xxxl })
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Colors.surface0)
  }

  @Builder
  TimelineItem(session: ServerSession) {
    Row() {
      Column() {
        Text(this.formatTime(session.createdAt)).fontSize(FontSize.xs).fontColor(Colors.foregroundMuted).margin({ right: Spacing.md })
      }.width(44).alignItems(HorizontalAlign.Start).margin({ top: 4 })

      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.person_2')).fontSize(14).fontColor([Colors.foregroundMuted]).margin({ right: Spacing.xs })
          Text(session.agent || this.text($r('app.string.config_agent'))).fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
        }.margin({ bottom: 4 })

        Text(session.title || this.text($r('app.string.common_untitled'))).fontSize(FontSize.md).fontWeight(FontWeight.Medium).fontColor(Colors.foreground).margin({ bottom: 4 })
        Text(this.formatRelativeTime(session.createdAt)).fontSize(FontSize.xs).fontColor(Colors.foregroundMuted)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }
    .width(Layout.contentWidth)
    .padding({ top: Spacing.md, bottom: Spacing.md })
    .backgroundColor(Colors.transparent)
    .onClick(() => { this.onSelectSession?.(session); })
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
