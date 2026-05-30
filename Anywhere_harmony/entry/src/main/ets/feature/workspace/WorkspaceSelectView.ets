import { Colors, FontSize, Spacing, Radius } from '../../constants/DesignTokens';
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
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.lg })

        // 空状态
        if (WorkspaceStore.workspaces.length === 0) {
          Column() {
            Text('No Workspaces')
              .fontSize(FontSize.base).fontColor(Colors.foregroundMuted)
            Text('Add a project path to get started')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
              .margin({ top: Spacing.xs })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 工作区列表
          List() {
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
                .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.md, bottom: Spacing.md })
                .backgroundColor(index === WorkspaceStore.currentIndex ? Colors.surface1 : 'transparent')
                .onClick(() => {
                  WorkspaceStore.currentIndex = index;
                  if (this.onSelect) this.onSelect(index);
                })
              }
            }, (ws: WorkspaceInfo, index: number) => ws.id + index.toString())
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: Colors.borderLight, startMargin: Spacing.xl, endMargin: Spacing.xl })
        }

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
      .width('100%').height('100%')
      .backgroundColor(Colors.surfaceElevated)
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
    .backgroundColor(Colors.surfaceElevated)
  }
}
