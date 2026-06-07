import { Colors, FontSize, Spacing, Radius, Layout } from '../../constants/DesignTokens';
import { WorkspaceStore, WorkspaceInfo } from '../../common/model/WorkspaceInfo';

@Component
export struct WorkspaceSelectView {
  @State showForm: boolean = false;
  @State newPath: string = '';
  onSelect?: (index: number) => void;
  onAddWorkspace?: (path: string) => void;

  build() {
    NavDestination() {
      Column() {
        // 头部
        Row() {
          Text($r('app.string.ws_title'))
            .fontSize(FontSize.xl)
            .fontColor(Colors.foreground)
          Blank()
        }
        .width(Layout.contentWidth)
        .padding({ top: Spacing.lg, bottom: Spacing.lg })

        // 空状态
        if (WorkspaceStore.workspaces.length === 0) {
          Column() {
            Text('No Workspaces')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
            Text('Add a project path to get started')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
              .margin({ top: Spacing.xs })
          }
          .width(Layout.contentWidth)
          .layoutWeight(1)
          .justifyContent(FlexAlign.Start)
          .alignItems(HorizontalAlign.Start)
          .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md })
        } else {
          // 工作区列表
          List({ space: Spacing.sm }) {
            ForEach(WorkspaceStore.workspaces, (ws: WorkspaceInfo, index: number) => {
              ListItem() {
                Row() {
                  SymbolGlyph($r('sys.symbol.folder'))
                    .fontSize(22)
                    .fontColor([index === WorkspaceStore.currentIndex ? Colors.accent : Colors.foregroundMuted])
                    .margin({ right: Spacing.md })

                  Column() {
                    Text(ws.name)
                      .fontSize(FontSize.base)
                      .fontColor(index === WorkspaceStore.currentIndex ? Colors.accent : Colors.foreground)
                      .fontWeight(index === WorkspaceStore.currentIndex ? FontWeight.Medium : FontWeight.Normal)
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

                  if (index === WorkspaceStore.currentIndex) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(16)
                      .fontColor([Colors.accent])
                  }
                }
                .width('100%')
                .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
                .onClick(() => {
                  WorkspaceStore.currentIndex = index;
                  if (this.onSelect) this.onSelect(index);
                })
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

        // 底部区域
        Column() {
          if (this.showForm) {
            Column() {
              TextInput({ placeholder: '/path/to/project', text: this.newPath })
                .width('100%').height(44)
                .backgroundColor(Colors.transparent)
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
            .width('100%')
            .padding({ bottom: Spacing.xl, top: Spacing.sm })
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
            .padding({ bottom: Spacing.xxl, top: Spacing.lg })
            .onClick(() => { this.showForm = true })
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
      }
      .width('100%').height('100%')
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(Colors.surfaceElevated)
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
    .backgroundColor(Colors.surfaceElevated)
  }
}
