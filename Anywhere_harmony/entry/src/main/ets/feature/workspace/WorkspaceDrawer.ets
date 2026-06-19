import { Colors, FontSize, Spacing, Radius, Layout, Duration } from '../../constants/DesignTokens';
import { WorkspaceInfo } from '../../common/model/WorkspaceInfo';

@Component
export struct WorkspaceDrawer {
  @Prop workspaces: WorkspaceInfo[] = [];
  @Prop currentIndex: number = -1;
  @State showForm: boolean = false;
  @State newPath: string = '';
  onSelect?: (index: number) => void;
  onDelete?: (index: number) => void;
  onClose?: () => void;
  onAddWorkspace?: (path: string) => void;

  build() {
    Column() {
      // Header
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(24)
            .fontColor([Colors.foreground])
        }
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .width(40).height(40)
        .onClick(() => { if (this.onClose) this.onClose() })

        Text($r('app.string.ws_title'))
          .fontSize(FontSize.lg)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
          .margin({ left: Spacing.sm })
        Blank()
      }
      .width(Layout.contentWidth)
      .padding({ top: Spacing.lg, bottom: Spacing.lg })
      .transition(TransitionEffect.OPACITY)
      // Workspace list
      if (this.workspaces.length === 0) {
        Column() {
          Text($r('app.string.ws_empty_prompt'))
            .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
          Text($r('app.string.ws_empty_subtitle'))
            .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
            .margin({ top: Spacing.xs })
        }
        .width(Layout.contentWidth).layoutWeight(1)
        .justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Start)
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md })
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
                SymbolGlyph($r('sys.symbol.ohos_trash'))
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
            .onClick(() => { if (this.onSelect) this.onSelect(index) })
            .transition(TransitionEffect.OPACITY)
            .stateStyles({
              pressed: {
                .backgroundColor(Colors.surface1)
              },
              normal: {
                .backgroundColor(Colors.transparent)
              }
            })
          }
        }, (ws: WorkspaceInfo, index: number) => ws.id + index.toString())
      }
      .width(Layout.contentWidth)
      .layoutWeight(1)
      }

      // Bottom area
      Column() {
        if (this.showForm) {
          Column() {
            TextInput({ placeholder: $r('app.string.ws_path_placeholder'), text: this.newPath })
              .width('100%').height(44)
              .backgroundColor(Colors.transparent)
              .padding({ left: Spacing.md, right: Spacing.md })
              .fontSize(FontSize.base)
              .onChange((v: string) => { this.newPath = v })

            Row() {
              Button($r('app.string.ws_cancel'))
                .layoutWeight(1).height(44)
                .backgroundColor('transparent').fontColor(Colors.foregroundMuted)
                .fontSize(FontSize.base)
                .onClick(() => { this.showForm = false; this.newPath = '' })
              Button($r('app.string.ws_add'))
                .layoutWeight(1).height(44)
                .backgroundColor(Colors.accent).fontColor(Colors.surface0)
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
          .transition(TransitionEffect.OPACITY)
        } else {
          Row() {
            SymbolGlyph($r('sys.symbol.ohos_folder_badge_plus'))
              .fontSize(22)
              .fontColor([Colors.foreground])
              .margin({ right: Spacing.md })
            Text($r('app.string.ws_add_button'))
              .fontSize(FontSize.base)
              .fontColor(Colors.foreground)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xxl, top: Spacing.lg })
          .onClick(() => { this.showForm = true })
          .transition(TransitionEffect.OPACITY)
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
      .width(Layout.contentWidth)
      .animation({ duration: Duration.normal, curve: Curve.EaseOut })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Colors.surfaceElevated)
  }
}
