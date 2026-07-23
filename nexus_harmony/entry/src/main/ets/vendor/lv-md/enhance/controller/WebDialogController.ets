import { ComponentContent, window } from "@kit.ArkUI"
import { WebDialogBuilder } from "../dialog/WebDialog"

export class WebDialogController {
  private static instance: WebDialogController
  private baseContentNode: ComponentContent<Object> | undefined = undefined
  title: string = ""
  src: string = ""

  /**
   * 打开模态框
   */
  async openBindSheet(title: string, src: string) {
    this.title = title
    this.src = src
    const sheetOptions: SheetOptions = {
      showClose: false,
      backgroundColor: "#FFF",
      dragBar: true,
      height: SheetSize.LARGE
    }
    const windowClass: window.Window = await window.getLastWindow(getContext())
    const builder: WrappedBuilder<[]> = wrapBuilder<[]>(WebDialogBuilder)
    this.baseContentNode = new ComponentContent(windowClass.getUIContext(), builder)
    windowClass.getUIContext().openBindSheet(this.baseContentNode, sheetOptions)
  }

  /**
   * 关闭模态弹窗
   */
  async closeBindSheet() {
    const windowClass = await window.getLastWindow(getContext())
    windowClass.getUIContext().closeBindSheet(this.baseContentNode)
  }

  static getInstance(): WebDialogController {
    if (!WebDialogController.instance) {
      WebDialogController.instance = new WebDialogController();
    }
    return WebDialogController.instance;
  }
}