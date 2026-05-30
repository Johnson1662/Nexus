import { CodeTheme } from '../constant/CodeTheme';
import { CodeBlockImpl } from '../impl/CodeBlockImpl';
import { CodeHighlight } from '../model/CodeHighlight';
import { generateRandomString } from '../utils/RandomString';
import { MDBaseController } from './BaseController';
import { componentUtils, promptAction } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

/**
 * @description Markdown 组件的控制器，可以将此对象绑定至 Markdown 组件，然后通过它控制 Markdown 组件的自定义样式。同一个控制器可以控制多个 Markdown 组件，多个 API 支持链式调用语法。
 */
@ObservedV2
export class MarkdownController {
  // 随机字符串
  private union: string = ""
  private uiContext: UIContext | null = null;
  // ** ================================================= 标题 ==================================================== **
  // 标题-文字颜色
  @Trace private titleColor: ResourceColor | [ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor] =
    "#ff1d2c39"
  // 标题-字号（1-6级）
  @Trace private titleSize: [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number] =
    [30, 28, 24, 20, 18, 16]
  // 标题-行高（1-6级）
  @Trace private titleLineHeight: [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number] =
    [36, 34, 30, 26, 24, 22]
  // 标题-字体粗细
  @Trace private titleFontWeight: FontWeight | [FontWeight, FontWeight, FontWeight, FontWeight, FontWeight, FontWeight] =
    FontWeight.Bold
  // 标题-字体样式
  @Trace private titleFontStyle: FontStyle | [FontStyle, FontStyle, FontStyle, FontStyle, FontStyle, FontStyle] =
    FontStyle.Normal
  // 标题-字体族（自定义字体）
  @Trace private titleFontFamily: ResourceStr | [ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr] =
    ""
  // ** ================================================= 普通文本 ==================================================== **
  // 普通文本-颜色
  @Trace private textColor: ResourceColor = "#e61f1f39"
  // 普通文本-行高
  @Trace private textLineHeight: ResourceStr | number = 24
  // 普通文本-字号
  @Trace private textSize: ResourceStr | number = 16
  // 普通文本-字体族（自定义字体）
  @Trace private textFontFamily: ResourceStr = ""
  // ** ================================================= 行内代码 ==================================================== **
  // 行内代码-颜色
  @Trace private inlineCodeColor: ResourceColor = "#F4271C"
  // 行内代码-背景颜色
  @Trace private inlineCodeBackgroundColor: ResourceColor = "#0eff0000"
  // 行内代码-背景圆角
  @Trace private inlineCodeBackgroundRadius: Dimension = 5
  // ** ================================================= 引用块 ==================================================== **
  // 引用块-左边颜色
  @Trace private quoteBorderColor: ResourceColor = "#F4271C"
  // 引用块-左边宽度
  @Trace private quoteBorderWidth: ResourceStr | number = 5
  // 引用块-背景颜色
  @Trace private quoteBackgroundColor: ResourceColor = "#ccf5f7fa"
  // 引用块-圆角
  @Trace private quoteBorderRadius: ResourceStr | number = 0
  // 引用块-内边距
  @Trace private quotePadding: Padding | Length | LocalizedPadding = {
    left: 10,
    top: 8,
    right: 8,
    bottom: 10
  }
  // ** ================================================= 代码块 ==================================================== **
  // 代码块-主题
  @Trace private codeBlockTheme: CodeTheme = "light"
  // 代码块-索引控制
  @Trace private codeBlockIdxState: boolean = false
  // 代码块-圆角
  @Trace private codeBlockBorderRadius: ResourceStr | number = 14
  // 代码块-代码高亮
  @Trace private codeHighlight: CodeHighlight = new CodeHighlight()
  // 代码块-点击复制回调
  @Trace private codeCopyListener: (text: string) => void = (text: string) => {
    if (this.uiContext) {
      this.uiContext.getPromptAction().showToast({ message: "复制失败，请检查 setCodeCopyListener 接口实现" });
    }
  }
  // ** ================================================= 图片 ==================================================== **
  // 图片-宽度
  @Trace private imageWidth: ResourceStr | number | null = "100%"
  // 图片-最大宽度
  @Trace private imageMaxWidth: ResourceStr | number | null = null
  // 图片-高度
  @Trace private imageHeight: ResourceStr | number | null = null
  // 图片-最大高度
  @Trace private imageMaxHeight: ResourceStr | number | null = null
  // 图片-圆角
  @Trace private imageBorderRadius: ResourceStr | number = 14
  // 图片-点击监听回调
  @Trace private imageClickListener: (src: string) => boolean = (src: string) => {
    return false
  }
  // 图片-加载代理
  @Trace private imageLoadProxy: (src: string) => string = (src: string) => {
    return src
  }
  // ** ================================================= 超链接 ==================================================== **
  // 超链接-文字颜色
  @Trace private hyperlinkTextColor: ResourceColor = "#0664EC"
  // 超链接-文字字号
  @Trace private hyperlinkTextSize: ResourceStr | number | null = null
  // 超链接-下划线展示状态
  @Trace private hyperlinkUnderlineState: boolean = false
  // 超链接-背景颜色
  @Trace private hyperlinkBackgroundColor: ResourceColor = Color.Transparent
  // 超链接-背景圆角
  @Trace private hyperlinkBackgroundRadius: Dimension = 5
  // 图片-点击监听回调
  @Trace private hyperlinkClickListener: (title: string, src: string,
    anchorInfo?: componentUtils.ComponentInfo) => boolean = (src: string) => {
    return false
  }
  // ** ================================================= 表格 ==================================================== **
  // 表格-背景色
  @Trace private tableBackgroundColor: ResourceColor = "#FFFFFF"
  // 表格-表头背景色
  @Trace private tableTitleBackgroundColor: ResourceColor = "#F5F7FA"
  // 表格-错行背景色
  @Trace private tableInterleaveBackgroundColor: ResourceColor = "#80f5f7fa"
  // 表格-圆角
  @Trace private tableBorderRadius: ResourceStr | number = 14
  // 表格-外边框颜色
  @Trace private tableOuterBorderColor: ResourceColor = Color.Transparent
  // 表格-外边框宽度
  @Trace private tableOuterBorderWidth: ResourceStr | number = 1
  // 表格-内边框颜色
  @Trace private tableInnerBorderColor: ResourceColor = Color.Transparent
  // 表格-内边框宽度
  @Trace private tableInnerBorderWidth: ResourceStr | number = 1
  // 表格-对齐方式
  @Trace private tableAlign: FlexAlign = FlexAlign.Start
  // ** ================================================= 任务列表 ==================================================== **
  // 任务列表-选中颜色
  @Trace private todoSelectedColor: ResourceColor = "#0A59F7"
  // 任务列表-选项大小
  @Trace private todoSelectSize: ResourceStr | number = 16
  // 无序列表-指示点大小
  @Trace private ulPointSize: ResourceStr | number = 5
  // 无序列表-指示点颜色
  @Trace private ulPointColor: ResourceColor | null = null
  // ** ================================================= 脚注 ==================================================== **
  // 脚注-文字颜色
  @Trace private footnoteTextColor: ResourceColor = "#fffa460d"
  // ** ================================================= 分割线 ==================================================== **
  // 分割线-颜色
  @Trace private lineColor: ResourceColor = "#EEE"
  // ** ================================================= 数学公式 ==================================================== **
  // 数学公式-字体大小
  @Trace private latexMathTextSize: number = 24
  // 数学公式-字体颜色（十六进制）
  @Trace private latexMathTextColor: number = 0xFF000000
  // 数学公式-点击监听回调
  @Trace private latexClickListener: (text: string, pixelMap: image.PixelMap) => boolean =
    (_text: string, _pixelMap: image.PixelMap) => {
      return false
    }
  // ** ================================================= 线程模式 ==================================================== **
  // 设置是否开启线程加载模式
  @Trace private threadRenderEnable: boolean = true
  // ** ================================================= 剪贴板复制范围选项 ==================================================== **
  // 设置剪贴板复制范围选项
  @Trace private copyOption: CopyOptions = CopyOptions.None
  // 跨 Text 选区开关
  @Trace private textSelectionEnable: boolean = false
  // 跨 Text 选区复制监听
  @Trace private textSelectionCopyListener: (text: string) => void = (_text: string) => {
    if (this.uiContext) {
      this.uiContext.getPromptAction().showToast({ message: "复制失败，请检查 setTextSelectionCopyListener 接口实现" });
    }
  }
  // ** ================================================= 块级元素间距 ==================================================== **
  // 块级元素间距
  @Trace private blockSpacing: number | ResourceStr = 10

  // function list

  constructor() {
    this.union = generateRandomString()
    MDBaseController.setMarkdownController(this)
  }

  getUnion() {
    return this.union
  }

  setUIContext(uiContext: UIContext): void {
    this.uiContext = uiContext;
  }

  getUIContext(): UIContext | null {
    return this.uiContext;
  }

  // ** ================================================= 标题 ==================================================== **
  /**
   * 设置标题-颜色
   * @param color
   * @version 3.2.2
   */
  setTitleColor(color: ResourceColor | [ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor]) {
    this.titleColor = color
    return this
  }

  getTitleColor(): ResourceColor | [ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor, ResourceColor] {
    return this.titleColor
  }

  /**
   * 设置标题-字号（1-6级）
   * @param titleSize
   */
  setTitleSize(titleSize: [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number]) {
    this.titleSize = titleSize
    return this
  }

  getTitleSize(): [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number] {
    return this.titleSize
  }

  /**
   * 设置标题-行高（1-6级）
   * @param lineHeights
   */
  setTitleLineHeight(lineHeights: [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number]) {
    this.titleLineHeight = lineHeights
    return this
  }

  getTitleLineHeight(): [ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number, ResourceStr | number] {
    return this.titleLineHeight
  }

  /**
   * 设置标题-字体粗细
   * @param fontWeight
   * @version 3.2.2
   */
  setTitleFontWeight(fontWeight: FontWeight | [FontWeight, FontWeight, FontWeight, FontWeight, FontWeight, FontWeight]) {
    this.titleFontWeight = fontWeight
    return this
  }

  getTitleFontWeight(): FontWeight | [FontWeight, FontWeight, FontWeight, FontWeight, FontWeight, FontWeight] {
    return this.titleFontWeight
  }

  /**
   * 设置标题-字体样式
   * @param fontStyle
   * @version 3.2.2
   */
  setTitleFontStyle(fontStyle: FontStyle | [FontStyle, FontStyle, FontStyle, FontStyle, FontStyle, FontStyle]) {
    this.titleFontStyle = fontStyle
    return this
  }

  getTitleFontStyle(): FontStyle | [FontStyle, FontStyle, FontStyle, FontStyle, FontStyle, FontStyle] {
    return this.titleFontStyle
  }

  /**
   * 设置标题-字体族（自定义字体）
   * @description 支持给指定级别的标题设置自定义字体。设置数组格式则为指定级别的标题设置自定义字体，设置唯一自定义字体，则1-6级标题全部生效。
   * @param fontFamily
   * @version 3.2.4
   */
  setTitleFontFamily(fontFamily: ResourceStr | [ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr]) {
    this.titleFontFamily = fontFamily
    return this
  }

  getTitleFontFamily(): ResourceStr | [ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr] {
    return this.titleFontFamily
  }

  // ** ================================================= 普通文本 ==================================================== **
  /**
   * 设置普通文本-颜色
   * @param textColor
   */
  setTextColor(textColor: ResourceColor) {
    this.textColor = textColor
    return this
  }

  getTextColor() {
    return this.textColor
  }

  /**
   * 设置普通文本-行高
   * @param textLineHeight
   */
  setTextLineHeight(textLineHeight: ResourceStr | number) {
    this.textLineHeight = textLineHeight
    return this
  }

  getTextLineHeight() {
    return this.textLineHeight
  }

  /**
   * 设置普通文本-字号
   * @param textSize
   */
  setTextSize(textSize: ResourceStr | number) {
    this.textSize = textSize
    return this
  }

  getTextSize() {
    return this.textSize
  }

  /**
   * 设置普通文本-字体族（自定义字体）
   * @param textSize
   */
  setTextFontFamily(fontFamily: ResourceStr) {
    this.textFontFamily = fontFamily
    return this
  }

  getTextFontFamily() {
    return this.textFontFamily
  }

  // ** ================================================= 行内代码 ==================================================== **
  /**
   * 设置行内代码-颜色
   * @param inlineCodeColor
   */
  setInlineCodeColor(inlineCodeColor: ResourceColor) {
    this.inlineCodeColor = inlineCodeColor
    return this
  }

  getInlineCodeColor(): ResourceColor {
    return this.inlineCodeColor
  }

  /**
   * 设置行内代码-背景颜色
   * @param inlineCodeBackgroundColor
   */
  setInlineCodeBackgroundColor(inlineCodeBackgroundColor: ResourceColor) {
    this.inlineCodeBackgroundColor = inlineCodeBackgroundColor
    return this
  }

  getInlineCodeBackgroundColor(): ResourceColor {
    return this.inlineCodeBackgroundColor
  }

  /**
   * 设置行内代码-背景圆角
   * @param inlineCodeBackgroundRadius
   */
  setInlineCodeBackgroundRadius(radius: Dimension) {
    this.inlineCodeBackgroundRadius = radius
    return this
  }

  getInlineCodeBackgroundRadius(): Dimension {
    return this.inlineCodeBackgroundRadius
  }

  // ** ================================================= 引用块 ==================================================== **
  /**
   * 设置引用块-左边颜色
   * @param quoteBorderColor
   * @returns
   */
  setQuoteBorderColor(quoteBorderColor: ResourceColor) {
    this.quoteBorderColor = quoteBorderColor
    return this
  }

  getQuoteBorderColor() {
    return this.quoteBorderColor
  }

  /**
   * 设置引用块-背景颜色
   * @param quoteBackgroundColor
   */
  setQuoteBackgroundColor(quoteBackgroundColor: ResourceColor) {
    this.quoteBackgroundColor = quoteBackgroundColor
    return this
  }

  getQuoteBackgroundColor() {
    return this.quoteBackgroundColor
  }

  /**
   * 设置引用块-圆角
   * @param radius
   * @version 3.2.2
   */
  setQuoteBorderRadius(radius: ResourceStr | number) {
    this.quoteBorderRadius = radius
    return this
  }

  getQuoteBorderRadius() {
    return this.quoteBorderRadius
  }

  /**
   * 设置引用块-左边宽度
   * @param size
   * @version 3.2.2
   */
  setQuoteBorderWidth(size: ResourceStr | number) {
    this.quoteBorderWidth = size
    return this
  }

  getQuoteBorderWidth() {
    return this.quoteBorderWidth
  }

  /**
   * 设置引用块-内边距
   * @param radius
   * @version 3.3.0
   */
  setQuotePadding(padding: Padding | Length | LocalizedPadding) {
    this.quotePadding = padding
    return this
  }

  getQuotePadding() {
    return this.quotePadding
  }

  // ** ================================================= 代码块 ==================================================== **
  /**
   * 设置代码块-主题
   * @param codeBlockTheme
   */
  setCodeBlockTheme(codeBlockTheme: CodeTheme) {
    this.codeBlockTheme = codeBlockTheme
    CodeBlockImpl.handleThemeChange(this.union, codeBlockTheme)
    return this
  }

  getCodeBlockTheme() {
    return this.codeBlockTheme
  }

  /**
   * 设置代码块-索引展示状态
   * @param codeBlockIdxState
   */
  setCodeBlockIdxState(codeBlockIdxState: boolean) {
    if (this.uiContext) {
      this.uiContext.animateTo({ duration: 200 }, () => {
        this.codeBlockIdxState = codeBlockIdxState
      })
    } else {
      this.codeBlockIdxState = codeBlockIdxState
    }
    return this
  }

  getCodeBlockIdxState() {
    return this.codeBlockIdxState
  }

  /**
   * 设置代码块-圆角
   * @param radius
   * @version 3.2.2
   */
  setCodeBlockBorderRadius(radius: number | ResourceStr) {
    this.codeBlockBorderRadius = radius
    return this
  }

  getCodeBlockBorderRadius() {
    return this.codeBlockBorderRadius
  }

  /**
   * 设置代码高亮着色
   * @param codeHighlight
   */
  setCodeHighlight(codeHighlight: CodeHighlight) {
    this.codeHighlight = codeHighlight
    return this
  }

  getCodeHighlight() {
    return this.codeHighlight
  }

  /**
   * 设置代码块-点击复制监听
   * @param event
   * @returns
   */
  setCodeCopyListener(event: (text: string) => void) {
    this.codeCopyListener = event
    return this
  }

  getCodeCopyListener(text: string) {
    return this.codeCopyListener(text)
  }

  // ** ================================================= 图片 ==================================================== **
  /**
   * 获取图片-宽度
   * @param imageWidth
   */
  setImageWidth(imageWidth: ResourceStr | number | null) {
    this.imageWidth = imageWidth
    return this
  }

  getImageWidth() {
    return this.imageWidth
  }

  /**
   * 设置图片-最大宽度
   * @param imageMaxWidth
   */
  setImageMaxWidth(imageMaxWidth: ResourceStr | number | null) {
    this.imageMaxWidth = imageMaxWidth
    return this
  }

  getImageMaxWidth() {
    return this.imageMaxWidth
  }

  /**
   * 获取图片-高度
   * @param imageWidth
   */
  setImageHeight(imageHeight: ResourceStr | number | null) {
    this.imageHeight = imageHeight
    return this
  }

  getImageHeight() {
    return this.imageHeight
  }

  /**
   * 设置图片-最大高度
   * @param imageMaxWidth
   */
  setImageMaxHeight(imageMaxHeight: ResourceStr | number | null) {
    this.imageMaxHeight = imageMaxHeight
    return this
  }

  getImageMaxHeight() {
    return this.imageMaxHeight
  }

  /**
   * 设置图片-圆角
   * @param radius
   * @version 3.2.2
   */
  setImageBorderRadius(radius: ResourceStr | number) {
    this.imageBorderRadius = radius
    return this
  }

  getImageBorderRadius() {
    return this.imageBorderRadius
  }

  /**
   * 设置图片-点击监听
   * @param event
   * @returns
   */
  setImageClickListener(event: (src: string) => boolean) {
    this.imageClickListener = event
    return this
  }

  getImageClickListener() {
    return this.imageClickListener
  }

  /**
   * 设置图片加载代理
   * @param event
   * @returns
   */
  setImageLoadProxy(event: (src: string) => string) {
    this.imageLoadProxy = event
    return this
  }

  getImageLoadProxy(src: string) {
    return this.imageLoadProxy(src)
  }

  // ** ================================================= 超链接 ==================================================== **
  /**
   * 设置超链接-文字颜色
   * @param hyperlinkTextColor
   */
  setHyperlinkTextColor(hyperlinkTextColor: ResourceColor) {
    this.hyperlinkTextColor = hyperlinkTextColor
    return this
  }

  getHyperlinkTextColor() {
    return this.hyperlinkTextColor
  }

  /**
   * 设置超链接-文字字号
   * @param size
   * @version 3.2.2
   */
  setHyperlinkTextSize(size: ResourceStr | number) {
    this.hyperlinkTextSize = size
    return this
  }

  getHyperlinkTextSize() {
    return this.hyperlinkTextSize
  }

  /**
   * 设置超链接-背景颜色
   * @param inlineCodeBackgroundColor
   */
  setHyperlinkBackgroundColor(bgcolor: ResourceColor) {
    this.hyperlinkBackgroundColor = bgcolor
    return this
  }

  getHyperlinkBackgroundColor(): ResourceColor {
    return this.hyperlinkBackgroundColor
  }

  /**
   * 设置超链接-背景圆角
   * @param radius
   */
  setHyperlinkBackgroundRadius(radius: Dimension) {
    this.hyperlinkBackgroundRadius = radius
    return this
  }

  getHyperlinkBackgroundRadius(): Dimension {
    return this.hyperlinkBackgroundRadius
  }

  /**
   * 设置超链接-下划线展示状态
   * @param hyperlinkUnderlineState
   */
  setHyperlinkUnderlineState(hyperlinkUnderlineState: boolean) {
    this.hyperlinkUnderlineState = hyperlinkUnderlineState
    return this
  }

  getHyperlinkUnderlineState() {
    return this.hyperlinkUnderlineState
  }

  /**
   * 设置超链接-点击监听
   * @param event
   * @returns
   */
  setHyperlinkClickListener(event: (title: string, src: string, anchorInfo?: componentUtils.ComponentInfo) => boolean) {
    this.hyperlinkClickListener = event
    return this
  }

  getHyperlinkClickListener() {
    return this.hyperlinkClickListener
  }

  // ** ================================================= 表格 ==================================================== **
  /**
   * 设置表格背景色
   * @param tableBackgroundColor
   */
  setTableBackgroundColor(tableBackgroundColor: ResourceColor) {
    this.tableBackgroundColor = tableBackgroundColor
    return this
  }

  getTableBackgroundColor() {
    return this.tableBackgroundColor
  }

  /**
   * 设置表格-表头背景色
   * @param tableTitleBackgroundColor
   */
  setTableTitleBackgroundColor(tableTitleBackgroundColor: ResourceColor) {
    this.tableTitleBackgroundColor = tableTitleBackgroundColor
    return this
  }

  getTableTitleBackgroundColor() {
    return this.tableTitleBackgroundColor
  }

  /**
   * 设置表格-错行背景色
   * @param tableInterleaveBackgroundColor
   */
  setTableInterleaveBackgroundColor(tableInterleaveBackgroundColor: ResourceColor) {
    this.tableInterleaveBackgroundColor = tableInterleaveBackgroundColor
    return this
  }

  getTableInterleaveBackgroundColor() {
    return this.tableInterleaveBackgroundColor
  }

  /**
   * 设置表格-圆角
   * @param radius
   * @version 3.2.2
   */
  setTableBorderRadius(radius: ResourceStr | number) {
    this.tableBorderRadius = radius
    return this
  }

  getTableBorderRadius() {
    return this.tableBorderRadius
  }

  /**
   * 设置表格-外边框颜色
   * @param color
   * @version 3.2.2
   */
  setTableOuterBorderColor(color: ResourceColor) {
    this.tableOuterBorderColor = color
    return this
  }

  getTableOuterBorderColor() {
    return this.tableOuterBorderColor
  }

  /**
   * 设置表格-外边框宽度
   * @param width
   * @version 3.2.2
   */
  setTableOuterBorderWidth(width: ResourceStr | number) {
    this.tableOuterBorderWidth = width
    return this
  }

  getTableOuterBorderWidth() {
    return this.tableOuterBorderWidth
  }

  /**
   * 设置表格-内边框颜色
   * @param color
   * @version 3.2.2
   */
  setTableInnerBorderColor(color: ResourceColor) {
    this.tableInnerBorderColor = color
    return this
  }

  getTableInnerBorderColor() {
    return this.tableInnerBorderColor
  }

  /**
   * 设置表格-内边框宽度
   * @param width
   * @version 3.2.2
   */
  setTableInnerBorderWidth(width: ResourceStr | number) {
    this.tableInnerBorderWidth = width
    return this
  }

  getTableInnerBorderWidth() {
    return this.tableInnerBorderWidth
  }

  /**
   * 设置表格-屏幕对齐方式
   * @param flexAlign 对齐方式
   * @version 3.2.2
   */
  setTableAlign(flexAlign: FlexAlign) {
    this.tableAlign = flexAlign
    return this
  }

  getTableAlign() {
    return this.tableAlign
  }

  // ** ================================================= 任务列表 ==================================================== **
  /**
   * 设置任务列表-选中颜色
   * @param todoSelectedColor
   */
  setTodoSelectedColor(todoSelectedColor: ResourceColor) {
    this.todoSelectedColor = todoSelectedColor
    return this
  }

  getTodoSelectedColor() {
    return this.todoSelectedColor
  }

  /**
   * 设置任务列表-选项大小
   * @param todoSelectSize
   */
  setTodoSelectSize(todoSelectSize: ResourceStr | number) {
    this.todoSelectSize = todoSelectSize
    return this
  }

  getTodoSelectSize() {
    return this.todoSelectSize
  }

  /**
   * 设置无序列表-指示点大小
   * @param size
   * @version 3.2.2
   */
  setUlPointSize(size: ResourceStr | number) {
    this.ulPointSize = size
    return this
  }

  getUlPointSize() {
    return this.ulPointSize
  }

  /**
   * 设置无序列表-指示点颜色
   * @param color
   * @version 3.2.2
   */
  setUlPointColor(color: ResourceColor) {
    this.ulPointColor = color
    return this
  }

  getUlPointColor() {
    return this.ulPointColor
  }

  // ** ================================================= 脚注 ==================================================== **
  /**
   * 设置脚注-文字颜色
   * @param footnoteTextColor
   */
  setFootnoteTextColor(footnoteTextColor: ResourceColor) {
    this.footnoteTextColor = footnoteTextColor
    return this
  }

  getFootnoteTextColor() {
    return this.footnoteTextColor
  }

  // ** ================================================= 分割线 ==================================================== **
  /**
   * 设置分割线-颜色
   * @param lineColor
   * @returns
   */
  setLineColor(lineColor: ResourceColor) {
    this.lineColor = lineColor
    return this
  }

  getLineColor() {
    return this.lineColor
  }

  // ** ================================================= 数学公式 ==================================================== **
  /**
   * 设置数学公式-字体大小
   * @param size
   * @returns
   */
  setLatexMathTextSize(size: number) {
    this.latexMathTextSize = size
    return this
  }

  getLatexMathTextSize() {
    return this.latexMathTextSize
  }

  /**
   * 数学公式-字体颜色（十六进制）
   * @param color
   * @returns
   */
  setLatexMathTextColor(color: number) {
    this.latexMathTextColor = color
    return this
  }

  getLatexMathTextColor() {
    return this.latexMathTextColor
  }

  /**
   * 设置数学公式-点击监听
   * @param event
   * @returns
   */
  setLatexClickListener(event: (text: string, pixelMap: image.PixelMap) => boolean) {
    this.latexClickListener = event
    return this
  }

  getLatexClickListener() {
    return this.latexClickListener
  }

  /**
   * 设置是否开启线程加载模式（默认开启）
   * @param enable
   */
  setThreadRenderEnable(enable: boolean) {
    this.threadRenderEnable = enable
    return this
  }

  getThreadRenderEnable() {
    return this.threadRenderEnable
  }

  // ** ================================================= 剪贴板复制范围选项 ==================================================== **
  /**
   * 设置剪贴板复制范围选项
   * @description 默认 CopyOptions.LocalDevice（支持复制后在所有应用内粘贴）。从 3.3.1 版本开始，该接口不再维护，调用后不再生效，请使用 setTextSelectionEnable() 与 setTextSelectionEnable() 实现文本选择复制功能。
   * @param copyOption
   * @deprecated 3.3.1
   */
  setCopyOption(copyOption: CopyOptions) {
    // this.copyOption = copyOption
  }

  getCopyOption() {
    return this.copyOption
  }

  /**
   * 设置是否开启跨 Text 文本选择能力
   * @description 默认 false
   * @param enable
   * @version 3.3.2
   */
  setTextSelectionEnable(enable: boolean) {
    this.textSelectionEnable = enable
    return this
  }

  getTextSelectionEnable() {
    return this.textSelectionEnable
  }

  /**
   * 设置跨 Text 文本选择复制监听
   * @param event
   * @version 3.3.2
   */
  setTextSelectionCopyListener(event: (text: string) => void) {
    this.textSelectionCopyListener = event
    return this
  }

  getTextSelectionCopyListener() {
    return this.textSelectionCopyListener
  }

  // ** ================================================= 块级元素间距 ==================================================== **
  /**
   * 设置块级元素间距
   * @description 默认 10vp。
   * @param copyOption
   * @version 3.3.0
   */
  setBlockSpacing(spacing: number | ResourceStr) {
    this.blockSpacing = spacing
  }

  getBlockSpacing() {
    return this.blockSpacing
  }
}
