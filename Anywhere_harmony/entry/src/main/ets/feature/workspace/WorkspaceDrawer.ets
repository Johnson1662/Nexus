import { Colors, FontSize, Spacing, Radius } from '../../constants/Colors';
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
          .fontSize(FontSize.md)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .layoutWeight(1)

        Row() {
          Image($r('app.media.ic_close')).fillColor(Colors.foregroundMuted).width(24).height(24)
        }
        .width(36)
        .height(36)
        .backgroundColor(Colors.surface1)
        .borderRadius(Radius.md)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.onClose) {
            this.onClose();
          }
        })
      }
      .width('100%')
      .padding({ left: Spacing.xl, right: Spacing.xl, top: Spacing.xl, bottom: Spacing.lg })

      Divider().color(Colors.borderLight).width('100%')

      List() {
        ForEach(this.workspaces, (ws: WorkspaceInfo, index: number) => {
          ListItem() {
            Row() {
              if (index === this.currentIndex) {
                Column()
                  .width(3)
                  .height(16)
                  .backgroundColor(Colors.accent)
                  .borderRadius(Radius.full)
                  .margin({ right: Spacing.md })
              } else {
                Column().width(3).margin({ right: Spacing.md }) // Placeholder
              }

              Row() {
                Text(ws.name.charAt(0).toUpperCase())
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(index === this.currentIndex ? Colors.accent : Colors.foregroundMuted)
              }
              .width(32).height(32)
              .backgroundColor(index === this.currentIndex ? Colors.accentLight : Colors.surface1)
              .borderRadius(Radius.md)
              .justifyContent(FlexAlign.Center)
              .margin({ right: Spacing.md })

              Column() {
                Text(ws.name)
                  .fontSize(FontSize.base)
                  .fontColor(index === this.currentIndex ? Colors.accent : Colors.foreground)
                  .fontWeight(index === this.currentIndex ? FontWeight.Medium : FontWeight.Regular)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(ws.path)
                  .fontSize(FontSize.xs)
                  .fontColor(Colors.foregroundMuted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 1 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: Spacing.md, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.lg })
            .backgroundColor(index === this.currentIndex ? Colors.accentTransparent : 'transparent')
            .borderRadius(Radius.md)
            .onClick(() => {
              if (this.onSelect) {
                this.onSelect(index);
              }
            })
            .gesture(
              LongPressGesture({ repeat: false, duration: 600 })
                .onAction(() => {
                  if (this.onDelete) {
                    this.onDelete(index);
                  }
                })
            )
          }
          .padding({ left: Spacing.sm, right: Spacing.md, bottom: Spacing.xs })
        }, (ws: WorkspaceInfo, index: number) => ws.id + index.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: Spacing.sm, bottom: Spacing.sm })

        Button('Add workspace')
          .width('100%').height(44)
          .backgroundColor(Colors.accentLight).fontColor(Colors.accent)
          .borderRadius(Radius.sm).fontSize(FontSize.sm)
          .margin({ left: Spacing.md, right: Spacing.md, bottom: Spacing.sm })
          .onClick(() => { 
            this.getUIContext()?.animateTo({ duration: 250, curve: Curve.Friction }, () => {
              this.showForm = !this.showForm; 
            })
          })

      if (this.showForm) {
        Column() {
          TextInput({ placeholder: 'Project path', text: this.newPath })
            .width('100%').height(40)
            .backgroundColor(Colors.surface1).borderRadius(Radius.sm)
            .padding({ left: Spacing.md, right: Spacing.md })
            .fontSize(FontSize.sm)
            .onChange((v: string) => { this.newPath = v; })

          Button('Add')
            .width('100%')
            .height(44)
            .margin({ top: Spacing.md })
            .backgroundColor(Colors.accent)
            .fontColor(Color.White)
            .borderRadius(Radius.md)
            .onClick(() => {
              if (this.newPath.length > 0 && this.onAddWorkspace) {
                this.onAddWorkspace(this.newPath);
                this.newPath = '';
                this.getUIContext()?.animateTo({ duration: 250, curve: Curve.Friction }, () => {
                  this.showForm = false;
                })
                if (this.onClose) {
                  this.onClose();
                }
              }
            })
        }
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.95, y: 0.95 })))
        .width('100%')
        .padding(Spacing.md)
        .backgroundColor(Colors.surfaceElevated)
        .borderRadius(Radius.md)
        .margin({ left: Spacing.md, right: Spacing.md, bottom: Spacing.sm })
      }

      Column() {
        Row() {
          Circle().width(6).height(6).fill(Colors.success)
          Text(this.agentType).fontSize(FontSize.sm).fontColor(Colors.foregroundMuted)
            .margin({ left: Spacing.sm }).layoutWeight(1)
          Button('Disconnect')
            .height(28).borderRadius(Radius.sm).fontSize(FontSize.xs)
            .backgroundColor('transparent').fontColor(Colors.foregroundLight)
            .onClick(() => { if (this.onSwitchHost) this.onSwitchHost(); })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface0)
  }
}
