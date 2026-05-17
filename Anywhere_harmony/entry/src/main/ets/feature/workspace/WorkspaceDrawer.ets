import { Colors, FontSize, Spacing, Radius } from '../../constants/DesignTokens';
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

  build() {
    Column() {
      // 头部
      Row() {
        Text('Workspaces')
          .fontSize(FontSize.xl)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
        Blank()
      }
      .width('100%')
      .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.xxl, bottom: Spacing.xl })

      // 工作区列表
      List() {
        ForEach(this.workspaces, (ws: WorkspaceInfo, index: number) => {
          ListItem() {
            Row() {
              SymbolGlyph($r('sys.symbol.folder'))
                .fontSize(22)
                .fontColor([index === this.currentIndex ? Colors.accent : Colors.foregroundMuted])
                .margin({ right: Spacing.md })

              Column() {
                Text(ws.name)
                  .fontSize(FontSize.base)
                  .fontColor(index === this.currentIndex ? Colors.accent : Colors.foreground)
                  .fontWeight(index === this.currentIndex ? FontWeight.Medium : FontWeight.Normal)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(ws.path)
                  .fontSize(FontSize.xs)
                  .fontColor(Colors.foregroundMuted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: Spacing.xxs })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (index === this.currentIndex) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(16)
                  .fontColor([Colors.accent])
              }
            }
            .width('100%')
            .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.md, bottom: Spacing.md })
            .backgroundColor(index === this.currentIndex ? Colors.surface1 : 'transparent')
            .onClick(() => { if (this.onSelect) this.onSelect(index) })
            .gesture(
              LongPressGesture({ repeat: false, duration: 600 })
                .onAction(() => { if (this.onDelete) this.onDelete(index) })
            )
          }
        }, (ws: WorkspaceInfo, index: number) => ws.id + index.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: Colors.borderLight, startMargin: Spacing.xl, endMargin: Spacing.xl })

      // 底部区域
      Column() {
        if (this.showForm) {
          Column() {
            TextInput({ placeholder: '/path/to/project', text: this.newPath })
              .width('100%').height(44)
              .backgroundColor(Colors.surface1).borderRadius(Radius.sm)
              .padding({ left: Spacing.md, right: Spacing.md })
              .fontSize(FontSize.sm)
              .onChange((v: string) => { this.newPath = v })

            Row() {
              Button('Cancel')
                .layoutWeight(1).height(40)
                .backgroundColor('transparent').fontColor(Colors.foregroundMuted)
                .fontSize(FontSize.sm)
                .onClick(() => { this.showForm = false; this.newPath = '' })
              Button('Add')
                .layoutWeight(1).height(40)
                .backgroundColor(Colors.accent).fontColor(Color.White)
                .borderRadius(Radius.md).fontSize(FontSize.sm)
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
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(18)
              .fontColor([Colors.foregroundMuted])
              .margin({ right: Spacing.sm })
            Text('Add Workspace')
              .fontSize(FontSize.base)
              .fontColor(Colors.foregroundMuted)
          }
          .width('100%')
          .padding({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.xxl, top: Spacing.lg })
          .onClick(() => { this.showForm = true })
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surfaceElevated)
  }
}
