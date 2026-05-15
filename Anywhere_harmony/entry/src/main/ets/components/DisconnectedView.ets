import { Colors, FontSize, Spacing, Radius } from '../constants/DesignTokens';

@Component
export struct DisconnectedView {
  @Prop hostUrl: string = '';
  onReconnect?: () => void;
  onChangeHost?: (url: string) => void;

  @State inputUrl: string = '';

  build() {
    Column() {
      Column() {
        Row() {
          SymbolGlyph($r('sys.symbol.AI'))
            .fontSize(FontSize.xxxl)
            .fontColor([Colors.accent])
          
          Text('Anywhere')
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(Colors.foreground)
            .margin({ left: Spacing.sm })
        }
        .margin({ bottom: Spacing.lg })

        Text('连接已断开')
          .fontSize(FontSize.xl)
          .fontWeight(FontWeight.Medium)
          .fontColor(Colors.foreground)
          .margin({ bottom: Spacing.xs })

        Text('请重新连接或更换主机')
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .margin({ bottom: Spacing.xxl })

        Column() {
          Text('上次连接')
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundMuted)
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: Spacing.xs })

          TextInput({ placeholder: 'ws://host:port', text: this.inputUrl })
            .width('100%')
            .height(44)
            .backgroundColor(Colors.surface1)
            .borderRadius(Radius.md)
            .border({ width: 1, color: Colors.borderLight })
            .padding({ left: Spacing.md, right: Spacing.md })
            .onChange((v: string) => { this.inputUrl = v; })

          Button('重新连接')
            .width('100%')
            .height(44)
            .margin({ top: Spacing.md })
            .backgroundColor(Colors.accent)
            .fontColor(Color.White)
            .borderRadius(Radius.md)
            .fontSize(FontSize.md)
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              if (this.onReconnect) {
                this.onReconnect();
              }
            })
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg })
      }
      .padding(32)
      .backgroundColor(Colors.surfaceElevated)
      .borderRadius(Radius.xxl)
      .width('80%')
      .alignItems(HorizontalAlign.Center)
      .shadow({ radius: 16, color: Colors.shadowColor, offsetY: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
