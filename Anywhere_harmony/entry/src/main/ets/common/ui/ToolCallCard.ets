import { Colors, FontSize, Spacing, Duration, Radius, AnimationPresets } from '../../constants/DesignTokens';

@Component
export struct ToolCallCard {
  @Prop name: string = '';
  @Prop status: string = 'pending';
  @Prop kind: string = '';
  @Prop content: string = '';
  @Prop contentType: string = '';
  @Prop path: string = '';
  @Prop oldText: string = '';
  @Prop newText: string = '';
  @Prop terminalId: string = '';
  @StorageLink('pref_toolcall_expanded') prefToolcallExpanded: boolean = true;
  @State breathFlag: boolean = false;
  @State expanded: boolean = false;

  aboutToAppear(): void {
    if (this.status === 'in_progress') {
      setTimeout(() => {
        this.breathFlag = true;
      }, 50);
    }
    if (this.hasDetail()) {
      this.expanded = this.prefToolcallExpanded;
    }
  }

  getFormattedName(): string {
    if (!this.name) return getContext(this).resourceManager.getStringSync($r('app.string.tool_default_name').id);
    let formatted = this.name.replace(/_/g, ' ');
    return formatted.charAt(0).toUpperCase() + formatted.slice(1);
  }

  getIconResource(): Resource {
    const n = this.name.toLowerCase();

    if (n.includes('web') || n.includes('fetch') || n.includes('browser') || n.includes('url') ||
        n.includes('search') || n.includes('find') || n.includes('glob') || n.includes('grep')) {
      return $r('sys.symbol.magnifyingglass');
    }

    if (n.includes('bash') || n.includes('cmd') || n.includes('shell') || n.includes('terminal') ||
        n.includes('tool') || n.includes('exec') || n.includes('run') || n.includes('deploy')) {
      return $r('sys.symbol.gearshape');
    }

    if (n.includes('edit') || n.includes('write') || n.includes('modify')) {
      return $r('sys.symbol.pencil_waveform');
    }

    if (n.includes('read') || n.includes('cat')) {
      return $r('sys.symbol.doc_text');
    }

    if (n.includes('create') || n.includes('new') || n.includes('add') || n.includes('make')) {
      return $r('sys.symbol.folder_badge_plus');
    }

    if (n.includes('delete') || n.includes('remove') || n.includes('rm')) {
      return $r('sys.symbol.trash');
    }

    if (n.includes('folder') || n.includes('dir') || n.includes('ls')) {
      return $r('sys.symbol.folder');
    }

    return $r('sys.symbol.paperclip');
  }

  getPathLabel(): string {
    if (this.path.length === 0) return '';
    let slash = this.path.lastIndexOf('/');
    let backslash = this.path.lastIndexOf('\\');
    let idx = slash > backslash ? slash : backslash;
    if (idx >= 0 && idx + 1 < this.path.length) return this.path.substring(idx + 1);
    return this.path;
  }

  getPreviewText(text: string): string {
    if (text.length <= 8000) return text;
    return text.substring(0, 8000) + '\n… truncated';
  }

  getDiffLines(): string[] {
    if (this.oldText.length === 0 && this.newText.length === 0) return [];
    if (this.oldText === this.newText) return [' no changes'];

    let oldLines = this.oldText.split('\n');
    let newLines = this.newText.split('\n');

    let prefix = 0;
    while (prefix < oldLines.length && prefix < newLines.length && oldLines[prefix] === newLines[prefix]) {
      prefix++;
    }

    let suffix = 0;
    while (suffix < oldLines.length - prefix && suffix < newLines.length - prefix &&
           oldLines[oldLines.length - 1 - suffix] === newLines[newLines.length - 1 - suffix]) {
      suffix++;
    }

    let result: string[] = [];

    let contextBefore = prefix > 3 ? prefix - 3 : 0;
    if (contextBefore > 0) result.push('@@ ... @@');
    for (let i = contextBefore; i < prefix; i++) {
      result.push(' ' + oldLines[i]);
    }

    let oldEnd = oldLines.length - suffix;
    for (let i = prefix; i < oldEnd; i++) {
      result.push('-' + oldLines[i]);
    }

    let newEnd = newLines.length - suffix;
    for (let i = prefix; i < newEnd; i++) {
      result.push('+' + newLines[i]);
    }

    let contextAfter = (newEnd + 3 < newLines.length) ? newEnd + 3 : newLines.length;
    for (let i = newEnd; i < contextAfter; i++) {
      result.push(' ' + newLines[i]);
    }
    if (contextAfter < newLines.length) result.push('@@ ... @@');

    if (result.length > 200) {
      result = result.slice(0, 200);
      result.push('… truncated');
    }

    return result;
  }

  getDiffColor(line: string): Resource {
    if (line.startsWith('+') && !line.startsWith('+++')) return Colors.success;
    if (line.startsWith('-') && !line.startsWith('---')) return Colors.error;
    if (line.startsWith('@@')) return Colors.foregroundLight;
    return Colors.foregroundMuted;
  }

  getDiffBgColor(line: string): ResourceStr {
    if (line.startsWith('+') && !line.startsWith('+++')) return Colors.successLight;
    if (line.startsWith('-') && !line.startsWith('---')) return Colors.errorLight;
    return 'transparent';
  }

  hasDetail(): boolean {
    return this.content.length > 0 || this.contentType === 'diff';
  }

  @Builder
  DetailContent() {
    if (this.contentType === 'terminal') {
      Column() {
        Text(this.getPreviewText(this.content))
          .fontSize(FontSize.xs)
          .fontColor(Colors.terminalFg)
          .fontFamily('monospace')
          .lineHeight(18)
      }
      .layoutWeight(1)
      .padding(Spacing.sm)
      .backgroundColor(Colors.terminalBg)
      .borderRadius(Radius.sm)
    } else if (this.contentType === 'diff') {
        Column() {
          if (this.content.length > 0) {
            Text(this.content)
              .fontSize(FontSize.xs)
              .fontColor(Colors.foregroundMuted)
              .fontFamily('monospace')
              .lineHeight(18)
              .margin({ bottom: Spacing.sm })
          }

          Column() {
            Row() {
              SymbolGlyph($r('sys.symbol.doc_text'))
                .fontSize(FontSize.sm)
                .fontColor([Colors.foregroundMuted])
                .margin({ right: Spacing.xs })
              Text(this.getPathLabel())
                .fontSize(FontSize.xs)
                .fontColor(Colors.foregroundMuted)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .padding({ left: Spacing.sm, right: Spacing.sm, top: Spacing.xs, bottom: Spacing.xs })

            Column() {
              ForEach(this.getDiffLines(), (line: string, index: number) => {
                Row() {
                  Text(line)
                    .fontSize(FontSize.xs)
                    .fontColor(this.getDiffColor(line))
                    .fontFamily('monospace')
                    .lineHeight(18)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .maxLines(1)
                }
                .width('100%')
                .padding({ left: Spacing.sm, right: Spacing.sm })
                .backgroundColor(this.getDiffBgColor(line))
              }, (line: string, index: number) => index + '_' + line)
            }
            .width('100%')
            .padding({ top: Spacing.xs, bottom: Spacing.xs })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .clip(true)
          .backgroundColor(Colors.surface2)
          .borderRadius(Radius.sm)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
    } else if (this.contentType === 'content') {
      Column() {
        Text(this.getPreviewText(this.content))
          .fontSize(FontSize.xs)
          .fontColor(Colors.foregroundMuted)
          .fontFamily('monospace')
          .lineHeight(18)
      }
      .layoutWeight(1)
      .padding(Spacing.sm)
      .backgroundColor(Colors.surface2)
      .borderRadius(Radius.sm)
    } else {
      Text(this.content)
        .fontSize(FontSize.xs)
        .fontColor(Colors.foregroundLight)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
  }

  build() {
    Column() {
      Button() {
        Row() {
          SymbolGlyph(this.getIconResource())
            .fontSize(FontSize.sm)
            .fontColor([Colors.foregroundMuted])
            .margin({ right: Spacing.sm })

          Column() {
            Text(this.getFormattedName())
              .fontSize(FontSize.sm)
              .fontColor(Colors.foreground)
              .fontWeight(FontWeight.Medium)
              .lineHeight(18)

            Row({ space: Spacing.xs }) {
              if (this.status === 'in_progress') {
                LoadingProgress()
                  .width(12)
                  .height(12)
                  .color(Colors.accent)
                Text(getContext(this).resourceManager.getStringSync($r('app.string.common_running').id))
                  .fontSize(FontSize.xs)
                  .fontColor(Colors.foregroundMuted)
              } else if (this.status === 'completed' || this.status === 'success') {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(10)
                  .fontColor([Colors.success])
                Text(getContext(this).resourceManager.getStringSync($r('app.string.common_done').id))
                  .fontSize(FontSize.xs)
                  .fontColor(Colors.success)
              } else if (this.status === 'failed' || this.status === 'error') {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(10)
                  .fontColor([Colors.error])
                Text(getContext(this).resourceManager.getStringSync($r('app.string.common_failed').id))
                  .fontSize(FontSize.xs)
                  .fontColor(Colors.error)
              }

              if (this.path.length > 0) {
                Text('·')
                  .fontSize(FontSize.xs)
                  .fontColor(Colors.foregroundLight)
                Text(this.getPathLabel())
                  .fontSize(FontSize.xs)
                  .fontColor(Colors.foregroundMuted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Blank()

          if (this.hasDetail()) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(FontSize.sm)
              .fontColor([Colors.foregroundMuted])
              .rotate({ angle: this.expanded ? 180 : 0 })
              .animation({ duration: Duration.normal, curve: AnimationPresets.spring })
          }
        }
        .width('100%')
        .padding({ left: Spacing.lg, right: Spacing.lg, top: Spacing.md, bottom: Spacing.md })
        .alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal)
      .width('100%')
      .backgroundColor(Color.Transparent)
      .padding(0)
      .enabled(this.hasDetail())
      .stateStyles({
        pressed: { .backgroundColor(Colors.surface2) },
        normal: { .backgroundColor(Color.Transparent) }
      })
      .onClick(() => {
        if (this.hasDetail()) {
          this.expanded = !this.expanded;
        }
      })

      if (this.expanded && this.hasDetail()) {
        Column() {
          this.DetailContent()
        }
        .width('100%')
        .padding({ left: Spacing.xl, right: Spacing.lg, bottom: Spacing.md })
        .transition(AnimationPresets.fadeIn)
      }
    }
    .width('100%')
    .backgroundColor(Colors.surface1)
    .borderRadius(12)
    .border({ width: 0 })
    .animation({ duration: Duration.normal, curve: AnimationPresets.spring })
  }
}
