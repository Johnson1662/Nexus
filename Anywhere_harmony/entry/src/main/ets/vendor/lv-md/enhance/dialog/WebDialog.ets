import { WebDialogController } from '../controller/WebDialogController'
import { webview } from '@kit.ArkWeb'
import { WebImpl } from '../impl/WebImpl'

@Builder
export function WebDialogBuilder() {
  WebDialog()
}

@Component
export struct WebDialog {
  controller: WebviewController = new webview.WebviewController()
  @State loading: boolean = true

  build() {
    Column() {
      Row() {
        Text(WebDialogController.getInstance().title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor("#000")
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width("100%")
      .height(60)
      .padding({ left: 16, right: 16 })

      Stack({ alignContent: Alignment.Center }) {
        if (WebImpl.canBeLoadedAsWebComponentURL(WebDialogController.getInstance().src)) {
          Web({ src: WebDialogController.getInstance().src, controller: this.controller })
            .layoutWeight(1)
            .mixedMode(MixedMode.All)
            .domStorageAccess(true)
            .javaScriptAccess(true)
            .overviewModeAccess(false)
            .width("100%")
            .onProgressChange((e) => {
              if (e.newProgress > 70) {
                this.getUIContext().animateTo({ duration: 200 }, () => {
                  this.loading = false
                })
              }
            })
        } else {
          Column() {
            Text(WebDialogController.getInstance().src)
              .fontColor("#303133")
              .lineHeight(24)
              .onAppear(() => {
                this.loading = false
              })
          }
          .padding(16)
          .width("100%")
          .height("100%")
          .alignItems(HorizontalAlign.Start)
        }
        if (this.loading) {
          Column() {
            LoadingProgress().width(50).height(50).color("#333333")
          }
        }
      }
      .layoutWeight(1)
    }
    .width("100%")
    .height("100%")
  }
}