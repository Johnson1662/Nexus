import { Colors, FontSize, Spacing, Duration, Radius } from '../../constants/DesignTokens';

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
    if (!this.name) return getContext().resourceManager.getStringSync($r('app.string.tool_default_name'));
    let formatted = this.name.replace(/_/g, ' ');
    return formatted.charAt(0).toUpperCase() + formatted.slice(1);
  }

  getIconResource(): Resource {
    const n = this.name.toLowerCase();
    
    // Web / Browser / Fetch / Search
    if (n.includes('web') || n.includes('fetch') || n.includes('browser') || n.includes('url') ||
        n.includes('search') || n.includes('find') || n.includes('glob') || n.includes('grep')) {
      return $r('sys.symbol.magnifyingglass');
    }
    
    // Command Line / Shell / Tools
    if (n.includes('bash') || n.includes('cmd') || n.includes('shell') || n.includes('terminal') ||
        n.includes('tool') || n.includes('exec') || n.includes('run') || n.includes('deploy')) {
      return $r('sys.symbol.gearshape');
    }
    
    // Edit / Write / Modify
    if (n.includes('edit') || n.includes('write') || n.includes('modify')) {
      return $r('sys.symbol.pencil_waveform');
    }
    
    // Read / View
    if (n.includes('read') || n.includes('cat')) {
      return $r('sys.symbol.doc_text');
    }
    
    // Create / New
    if (n.includes('create') || n.includes('new') || n.includes('add') || n.includes('make')) {
      return $r('sys.symbol.ohos_folder_badge_plus');
    }
    
    // Delete / Remove
    if (n.includes('delete') || n.includes('remove') || n.includes('rm')) {
      return $r('sys.symbol.ohos_trash');
    }
    
    // Folders / Directory
    if (n.includes('folder') || n.includes('dir') || n.includes('ls')) {
      return $r('sys.symbol.folder');
    }
    
    // Fallback
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
          .fontColor('#E5E7EB')
          .fontFamily('monospace')
          .lineHeight(18)
      }
      .layoutWeight(1)
      .padding(Spacing.sm)
      .backgroundColor('#111827')
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
          .backgroundColor(Colors.surface1)
          .border({ width: { bottom: 1 }, color: { bottom: Colors.borderLight } })
          
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
        .backgroundColor(Colors.surface0)
        .border({ width: 1, color: Colors.borderLight })
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
      .backgroundColor(Colors.surface1)
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
      Row() {
        SymbolGlyph(this.getIconResource())
          .fontSize(FontSize.md)
          .fontColor([Colors.foregroundMuted])
          .margin({ right: Spacing.sm })

        Text(this.getFormattedName())
          .fontSize(FontSize.sm)
          .fontColor(Colors.foregroundMuted)
          .fontWeight(FontWeight.Medium)

        Blank()

        if (this.hasDetail()) {
          Text(getContext().resourceManager.getStringSync(this.expanded ? $r('app.string.tool_hide_detail') : $r('app.string.tool_show_detail')))
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundLight)
            .margin({ right: Spacing.xs })

          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(FontSize.sm)
            .fontColor([Colors.foregroundMuted])
            .rotate({ angle: this.expanded ? 180 : 0 })
            .animation({ duration: Duration.fast, curve: Curve.EaseOut })
        }

        if (this.status === 'in_progress') {
          SymbolGlyph($r('sys.symbol.clock'))
            .fontSize(FontSize.sm)
            .fontColor([Colors.foregroundMuted])
            .opacity(this.breathFlag ? 0.3 : 1.0)
            .animation({
              duration: 800,
              curve: Curve.EaseInOut,
              playMode: PlayMode.Alternate,
              iterations: -1
            })
        } else if (this.status === 'completed' || this.status === 'success') {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(FontSize.sm)
            .fontColor([Colors.foregroundMuted])
        } else if (this.status === 'failed' || this.status === 'error') {
          SymbolGlyph($r('sys.symbol.xmark_circle'))
            .fontSize(FontSize.sm)
            .fontColor(['#EF4444']) // error red
        }
      }
      .width('100%')
      .height(32)
      .alignItems(VerticalAlign.Center)
      .enabled(this.hasDetail())
      .onClick(() => {
        if (this.hasDetail()) {
          this.expanded = !this.expanded;
        }
      })

      if (this.expanded && this.hasDetail()) {
        Row() {
          Column().width(24) // offset for icon + margin

          this.DetailContent()
        }
        .width('100%')
        .padding({ bottom: Spacing.xs })
        .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -5 })))
      }
    }
    .width('100%')
    .animation({ duration: Duration.fast, curve: Curve.EaseOut })
  }
}
