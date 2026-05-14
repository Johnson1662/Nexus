import { Colors } from '../constants/Colors';
import { WorkspaceInfo } from '../store/SessionStore';
import { FontSize, Spacing, Radius, Duration } from '../constants/DesignTokens';

@Component
export struct WorkspaceDrawer {
  @Prop workspaces: WorkspaceInfo[] = [];
  @Prop currentIndex: number = -1;
  @Prop hostName: string = '';
  @Prop hostUrl: string = '';
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
        Text('工作区')
          .fontSize(FontSize.xxl)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.foreground)
          .layoutWeight(1)

        Row() {
          Text('✕')
            .fontSize(18)
            .fontColor(Colors.foregroundMuted)
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

      Divider()
        .color(Colors.borderLight)
        .width('100%')

      List() {
        ForEach(this.workspaces, (ws: WorkspaceInfo, index: number) => {
          ListItem() {
            Row() {
              if (index === this.currentIndex) {
                Column()
                  .width(4)
                  .height('100%')
                  .backgroundColor(Colors.accent)
                  .borderRadius(2)
                  .margin({ right: Spacing.md })
              }

              Text('📁')
                .fontSize(20)
                .margin({ right: Spacing.md })

              Column() {
                Text(ws.name)
                  .fontSize(FontSize.lg)
                  .fontWeight(index === this.currentIndex ? FontWeight.Medium : FontWeight.Medium)
                  .fontColor(Colors.foreground)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(ws.path)
                  .fontSize(FontSize.xs)
                  .fontColor(Colors.foregroundMuted)
                  .margin({ top: 2 })
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .lineHeight(16)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
            .backgroundColor(index === this.currentIndex ? Colors.accentTransparent : Colors.surfaceElevated)
            .borderRadius(Radius.lg)
            .border({ width: 1, color: index === this.currentIndex ? Colors.accent : Colors.borderLight })
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
          .padding({ left: Spacing.md, right: Spacing.md, bottom: Spacing.xs })
        }, (ws: WorkspaceInfo, index: number) => ws.id + '_' + index.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: Spacing.sm, bottom: Spacing.sm })

      Button('+ 添加工作区')
        .width('100%')
        .height(48)
        .backgroundColor(Colors.accentLight)
        .fontColor(Colors.accent)
        .borderRadius(Radius.md)
        .fontSize(FontSize.md)
        .fontWeight(FontWeight.Medium)
        .margin({ left: Spacing.md, right: Spacing.md, bottom: Spacing.sm })
        .onClick(() => {
          this.showForm = !this.showForm;
        })

      if (this.showForm) {
        Column() {
          TextInput({ placeholder: '项目路径', text: this.newPath })
            .width('100%')
            .height(44)
            .backgroundColor(Colors.surface1)
            .borderRadius(Radius.md)
            .border({ width: 1, color: Colors.borderLight })
            .padding({ left: Spacing.md, right: Spacing.md })
            .onChange((v: string) => { this.newPath = v; })

          Button('添加')
            .width('100%')
            .height(44)
            .margin({ top: Spacing.md })
            .backgroundColor(Colors.accent)
            .fontColor(Color.White)
            .borderRadius(Radius.md)
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              if (this.newPath.length > 0 && this.onAddWorkspace) {
                this.onAddWorkspace(this.newPath);
                this.newPath = '';
                this.showForm = false;
                if (this.onClose) {
                  this.onClose();
                }
              }
            })
        }
        .width('100%')
        .padding({ left: Spacing.md, right: Spacing.md, top: Spacing.md, bottom: Spacing.md })
        .backgroundColor(Colors.surfaceElevated)
        .borderRadius(Radius.md)
        .margin({ left: Spacing.md, right: Spacing.md, bottom: Spacing.sm })
      }

      Column() {
        Row() {
          Circle()
            .width(8)
            .height(8)
            .fill(Colors.success)
            .margin({ right: Spacing.md })

          Text(this.hostName)
            .fontSize(FontSize.base)
            .fontWeight(FontWeight.Medium)
            .fontColor(Colors.foreground)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: Spacing.xs })

        Text(this.hostUrl)
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .width('100%')
          .margin({ bottom: Spacing.lg })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button('断开并切换')
          .width('100%')
          .height(44)
          .backgroundColor(Colors.errorLight)
          .fontColor(Colors.error)
          .borderRadius(Radius.md)
          .fontSize(FontSize.md)
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            if (this.onSwitchHost) {
              this.onSwitchHost();
            }
          })
      }
      .width('90%')
      .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.lg })
      .backgroundColor(Colors.surfaceElevated)
      .borderRadius(Radius.xl)
      .margin({ bottom: Spacing.xl })
      .alignSelf(ItemAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Colors.surface0)
  }
}
