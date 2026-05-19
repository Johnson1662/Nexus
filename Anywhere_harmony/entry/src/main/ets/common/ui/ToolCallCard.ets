import { Colors, FontSize, Spacing, Duration } from '../../constants/DesignTokens';

@Component
export struct ToolCallCard {
  @Prop name: string = '';
  @Prop status: string = 'pending';
  @Prop kind: string = '';
  @Prop content: string = '';
  @State breathFlag: boolean = false;

  aboutToAppear(): void {
    if (this.status === 'in_progress') {
      setTimeout(() => {
        this.breathFlag = true;
      }, 50);
    }
  }

  getFormattedName(): string {
    if (!this.name) return 'Tool call';
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

      if (this.content.length > 0) {
        Row() {
          Column().width(24) // offset for icon + margin
          
          Text(this.content)
            .fontSize(FontSize.xs)
            .fontColor(Colors.foregroundLight)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
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
