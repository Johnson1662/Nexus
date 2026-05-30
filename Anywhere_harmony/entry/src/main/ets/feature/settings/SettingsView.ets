import { Colors, FontSize, Spacing, Radius } from '../../constants/DesignTokens';
import { StorageService } from '../../services/StorageService';

@Component
export struct SettingsPage {
  @StorageLink('pref_thinking_expanded') thinkingExpanded: boolean = true;
  @StorageLink('pref_toolcall_expanded') toolcallExpanded: boolean = true;

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('设置')
            .fontSize(FontSize.xl).fontColor(Colors.foreground).fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.lg, bottom: Spacing.lg })

        List() {
          ListItem() {
            Row() {
              Column() {
                Text('Thinking 默认展开')
                  .fontSize(FontSize.base).fontColor(Colors.foreground)
                Text('流式结束后自动展开思考内容')
                  .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
                  .margin({ top: Spacing.xxs })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.thinkingExpanded })
                .onChange((isOn: boolean) => {
                  this.thinkingExpanded = isOn;
                  StorageService.getInstance().putString('pref_thinking_expanded', isOn ? '1' : '0');
                })
            }
            .width('100%')
            .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
          }

          ListItem() {
            Row() {
              Column() {
                Text('工具调用 默认展开')
                  .fontSize(FontSize.base).fontColor(Colors.foreground)
                Text('完成后自动展开工具调用详情')
                  .fontSize(FontSize.sm).fontColor(Colors.foregroundLight)
                  .margin({ top: Spacing.xxs })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.toolcallExpanded })
                .onChange((isOn: boolean) => {
                  this.toolcallExpanded = isOn;
                  StorageService.getInstance().putString('pref_toolcall_expanded', isOn ? '1' : '0');
                })
            }
            .width('100%')
            .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%').height('100%')
      .backgroundColor(Colors.surface0)
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
