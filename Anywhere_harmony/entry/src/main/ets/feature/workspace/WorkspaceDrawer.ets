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
      Row() {
        Text('Workspaces')
          .fontSize(FontSize.xl)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
      }
      .width('100%')
      .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.xl, bottom: Spacing.md })

      List() {
        ForEach(this.workspaces, (ws: WorkspaceInfo, index: number) => {
          ListItem() {
            Row() {
              Row() {
                Text(ws.name.charAt(0).toUpperCase())
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(index === this.currentIndex ? Color.White : Colors.accent)
              }
              .width(40).height(40)
              .backgroundColor(index === this.currentIndex ? Colors.accent : Colors.accentLight)
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
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
            .backgroundColor(index === this.currentIndex ? Colors.surface1 : 'transparent')
            .borderRadius(Radius.lg)
            .onClick(() => { if (this.onSelect) this.onSelect(index) })
            .gesture(
              LongPressGesture({ repeat: false, duration: 600 })
                .onAction(() => { if (this.onDelete) this.onDelete(index) })
            )
          }
          .padding({ left: Spacing.sm, right: Spacing.sm, bottom: Spacing.sm })
        }, (ws: WorkspaceInfo, index: number) => ws.id + index.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: Spacing.sm })

      Button({ type: ButtonType.Normal, stateEffect: true }) {
        Row() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(FontSize.sm)
            .fontColor([Colors.accent])
          Text(' Add workspace')
            .fontSize(FontSize.sm)
            .fontColor(Colors.accent)
        }
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%').height(48)
      .backgroundColor(Colors.accentLight)
      .borderRadius(Radius.lg)
      .margin({ left: Spacing.lg, right: Spacing.lg, bottom: Spacing.sm })
      .onClick(() => { this.showForm = !this.showForm })

      if (this.showForm) {
        Column() {
          TextInput({ placeholder: 'Enter project path...', text: this.newPath })
            .width('100%').height(44)
            .backgroundColor(Colors.surface0).borderRadius(Radius.md)
            .padding({ left: Spacing.md, right: Spacing.md })
            .fontSize(FontSize.sm)
            .onChange((v: string) => { this.newPath = v })

          Row() {
            Button('Cancel')
              .layoutWeight(1).height(40)
              .backgroundColor(Colors.surface2).fontColor(Colors.foreground)
              .borderRadius(Radius.md).fontSize(FontSize.sm)
              .onClick(() => { this.showForm = false; this.newPath = '' })
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
        .margin({ left: Spacing.lg, right: Spacing.lg, bottom: Spacing.sm })
        .shadow({ radius: 8, color: '#00000010', offsetY: 4 })
        .transition(TransitionEffect.OPACITY)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface0)
  }
}
