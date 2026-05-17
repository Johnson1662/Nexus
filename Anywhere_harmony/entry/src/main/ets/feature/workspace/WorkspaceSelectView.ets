import { Colors, FontSize, Spacing, Radius, Shadow, Duration } from '../../constants/DesignTokens';
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
        Row() {
          Text('Select Workspace')
            .fontSize(FontSize.xxl)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.foreground)
        }
        .width('100%')
        .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.xl, bottom: Spacing.md })

        if (WorkspaceStore.workspaces.length === 0) {
          Column() {
            SymbolGlyph($r('sys.symbol.doc'))
              .fontSize(48)
              .fontColor([Colors.foregroundLight])
              .margin({ bottom: Spacing.xxl })

            Text('No Workspaces')
              .fontSize(FontSize.xxl).fontWeight(FontWeight.Bold)
              .fontColor(Colors.foreground)

            Text('Add a project path to get started')
              .fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
              .margin({ top: Spacing.sm, bottom: Spacing.xxl })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Column() {
            Text('Select a workspace to continue')
              .fontSize(FontSize.sm)
              .fontColor(Colors.foregroundMuted)
              .width('100%').padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.md, bottom: Spacing.md })

            Scroll() {
              Column() {
                ForEach(WorkspaceStore.workspaces, (ws: WorkspaceInfo, index: number) => {
                  Row() {
                    Row() {
                      Text(ws.name.charAt(0).toUpperCase())
                        .fontSize(FontSize.xl)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(index === WorkspaceStore.currentIndex ? Color.White : Colors.accent)
                    }
                    .width(44).height(44)
                    .backgroundColor(index === WorkspaceStore.currentIndex ? Colors.accent : Colors.accentLight)
                    .borderRadius(Radius.lg)
                    .justifyContent(FlexAlign.Center)
                    .margin({ right: Spacing.md })

                    Column() {
                      Text(ws.name)
                        .fontSize(FontSize.base)
                        .fontColor(Colors.foreground)
                        .fontWeight(FontWeight.Medium)
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
                        .fontSize(FontSize.lg)
                        .fontColor([Colors.accent])
                    }

                    SymbolGlyph($r('sys.symbol.chevron_right'))
                      .fontSize(FontSize.sm)
                      .fontColor([Colors.foregroundLight])
                      .margin({ left: Spacing.sm })
                  }
                  .width('100%')
                  .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.md, bottom: Spacing.md })
                  .backgroundColor(index === WorkspaceStore.currentIndex ? Colors.surface1 : 'transparent')
                  .borderRadius(Radius.lg)
                  .onClick(() => {
                    WorkspaceStore.currentIndex = index;
                    if (this.onSelect) this.onSelect(index);
                  })
                  .margin({ bottom: Spacing.sm })
                }, (ws: WorkspaceInfo, index: number): string => ws.id + index.toString())
              }
              .width('100%')
              .padding({ left: Spacing.lg, right: Spacing.lg })
            }
            .layoutWeight(1)
            .width('100%')
          }
          .width('100%')
        }

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          Row() {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(FontSize.sm)
              .fontColor([Colors.accent])
            Text(' Add Workspace')
              .fontSize(FontSize.sm)
              .fontColor(Colors.accent)
          }
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%').height(48)
        .backgroundColor(Colors.surface1)
        .borderRadius(Radius.lg)
        .margin({ left: Spacing.xl, right: Spacing.xl, top: Spacing.xs, bottom: Spacing.sm })
        .onClick(() => {
          this.showForm = !this.showForm;
        })

        if (this.showForm) {
          Column() {
            TextInput({ placeholder: 'Enter project path...', text: this.newPath })
              .width('100%').height(44)
              .backgroundColor(Colors.surface0).borderRadius(Radius.md)
              .padding({ left: Spacing.md, right: Spacing.md })
              .fontSize(FontSize.sm)
              .onChange((v: string) => {
                this.newPath = v;
              })

            Row() {
              Button('Cancel')
                .layoutWeight(1).height(40)
                .backgroundColor(Colors.surface2).fontColor(Colors.foreground)
                .borderRadius(Radius.md).fontSize(FontSize.sm)
                .onClick(() => {
                  this.showForm = false;
                  this.newPath = '';
                })
              Button('Add')
                .layoutWeight(1).height(40).margin({ left: Spacing.md })
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
          .padding(Spacing.lg)
          .backgroundColor(Colors.surfaceElevated)
          .borderRadius(Radius.lg)
          .margin({ left: Spacing.xl, right: Spacing.xl, bottom: Spacing.sm })
          .shadow(Shadow.md)
          .transition(TransitionEffect.OPACITY)
        }
      }
      .width('100%').height('100%')
      .padding({ bottom: Spacing.xl })
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
    .backgroundColor(Colors.surface0)
  }
}
