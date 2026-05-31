import { Colors, FontSize, Spacing, Radius, Duration } from '../../constants/DesignTokens';
import { WorkspaceInfo } from '../../common/model/WorkspaceInfo';

@Component
export struct WorkspaceDrawer {
  @Prop workspaces: WorkspaceInfo[] = [];
  @Prop currentIndex: number = -1;
  @Prop hostName: string = '';
  @Prop hostUrl: string = '';
  @Prop agentType: string = '';
  @State showForm: boolean = false;
  @State newPath: string = '';
  onSelect?: (index: number) => void;
  onDelete?: (index: number) => void;
  onClose?: () => void;
  onSwitchHost?: () => void;
  onAddWorkspace?: (path: string) => void;
  onSettings?: () => void;
  onHostManage?: () => void;

  build() {
    Column() {
      // Header
      Row() {
        SymbolGlyph($r('sys.symbol.close_sidebar'))
          .fontSize(24)
          .fontColor([Colors.foreground])
          .onClick(() => { if (this.onClose) this.onClose() })

        Text($r('app.string.ws_title'))
          .fontSize(FontSize.lg)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
          .margin({ left: Spacing.sm })
        Blank()
      }
      .width('100%')
      .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.lg })
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -10 })))
      // Workspace list
      if (this.workspaces.length === 0) {
        Column() {
          Text('No Workspaces')
            .fontSize(FontSize.lg).fontWeight(FontWeight.Bold).fontColor(Colors.foregroundMuted)
          Text('Add a path to get started')
            .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
            .margin({ top: Spacing.xs })
        }
        .width('100%').layoutWeight(1)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
      } else {
        List({ space: Spacing.sm }) {
        ForEach(this.workspaces, (ws: WorkspaceInfo, index: number) => {
          ListItem() {
            Row() {
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(22)
                .fontColor([index === this.currentIndex ? Colors.accent : Colors.foregroundMuted])
                .margin({ right: Spacing.md })

              Column() {
                Text(ws.name)
                  .fontSize(FontSize.lg)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(index === this.currentIndex ? Colors.accent : Colors.foreground)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ bottom: Spacing.xs })
                Text(ws.path)
                  .fontSize(FontSize.sm)
                  .fontColor(Colors.foregroundMuted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: Spacing.xxs })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Row() {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(20)
                  .fontColor([Colors.foregroundMuted])
                  .padding({ left: Spacing.sm, right: Spacing.xs, top: Spacing.sm, bottom: Spacing.sm })
                  .onClick(() => {
                    if (this.onDelete) this.onDelete(index);
                  })
              }
            }
            .width('100%')
            .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.lg })
            .backgroundColor(index === this.currentIndex ? Colors.surface1 : 'transparent')
            .borderRadius(Radius.lg)
            .onClick(() => { if (this.onSelect) this.onSelect(index) })
            .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: -20 })))
            .animation({ duration: Duration.normal, curve: Curve.EaseOut, delay: index * 40 })
          }
        }, (ws: WorkspaceInfo, index: number) => ws.id + index.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: Spacing.sm, right: Spacing.sm })
      }

      // Bottom area
      Column() {
        Divider().color(Colors.borderLight).strokeWidth(0.5).margin({ left: Spacing.xl, right: Spacing.xl })
        // Navigation entries
        if (this.onHostManage) {
          Row() {
            SymbolGlyph($r('sys.symbol.ohos_wifi'))
              .fontSize(22)
              .fontColor([Colors.foreground])
              .margin({ right: Spacing.md })
            Text('Host 管理')
              .fontSize(FontSize.base)
              .fontColor(Colors.foreground)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.lg, bottom: Spacing.sm })
          .onClick(() => { if (this.onHostManage) this.onHostManage() })
        }

        if (this.onSettings) {
          Row() {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(22)
              .fontColor([Colors.foreground])
              .margin({ right: Spacing.md })
            Text('设置')
              .fontSize(FontSize.base)
              .fontColor(Colors.foreground)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.sm, bottom: Spacing.sm })
          .onClick(() => { if (this.onSettings) this.onSettings() })
        }

        if (this.showForm) {
          Column() {
            TextInput({ placeholder: '/path/to/project', text: this.newPath })
              .width('100%').height(44)
              .backgroundColor(Colors.surface1).borderRadius(Radius.md)
              .padding({ left: Spacing.md, right: Spacing.md })
              .fontSize(FontSize.base)
              .onChange((v: string) => { this.newPath = v })

            Row() {
              Button('Cancel')
                .layoutWeight(1).height(44)
                .backgroundColor('transparent').fontColor(Colors.foregroundMuted)
                .fontSize(FontSize.base)
                .onClick(() => { this.showForm = false; this.newPath = '' })
              Button('Add')
                .layoutWeight(1).height(44)
                .backgroundColor(Colors.accent).fontColor(Color.White)
                .borderRadius(Radius.md).fontSize(FontSize.base)
                .onClick(() => {
                  if (this.newPath.length > 0 && this.onAddWorkspace) {
                    this.onAddWorkspace(this.newPath);
                    this.newPath = '';
                    this.showForm = false;
                  }
                })
            }
            .width('100%').margin({ top: Spacing.md })
          }
          .padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xl, top: Spacing.sm })
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))
        } else {
          Row() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(22)
              .fontColor([Colors.foreground])
              .margin({ right: Spacing.md })
            Text('Add Workspace')
              .fontSize(FontSize.base)
              .fontColor(Colors.foreground)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xxl, top: Spacing.lg })
          .onClick(() => { this.showForm = true })
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 })))
        }
      }
      .width('100%')
      .animation({ duration: Duration.normal, curve: Curve.EaseOut })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surfaceElevated)
  }
}
