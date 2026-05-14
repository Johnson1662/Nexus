const fs = require('fs');
const path = require('path');

function replaceInFile(file, replacements) {
    const fullPath = path.join(__dirname, file);
    let content = fs.readFileSync(fullPath, 'utf8');
    for (let [oldStr, newStr] of replacements) {
        if (!content.includes(oldStr)) {
            console.log(`Could not find in ${file}:\n${oldStr}`);
        }
        content = content.replace(oldStr, newStr);
    }
    fs.writeFileSync(fullPath, content);
}

replaceInFile('Anywhere_harmony/entry/src/main/ets/pages/Index.ets', [
    [`Path().commands('M0 0 M24 24 M19 3h-4.18C14.4 1.84 13.3 1 12 1c-1.3 0-2.4.84-2.82 2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1z').fill('transparent').stroke(Colors.foreground).strokeWidth(1.5).width(24).height(24).margin({ right: Spacing.md })`,
     `Image($r('app.media.ic_paste')).fillColor(Colors.foreground).width(20).height(20).margin({ right: Spacing.md })`],
    [`Path().commands('M0 0 M24 24 M4 6 h16 M4 12 h16 M4 18 h16').stroke(Colors.foreground).strokeWidth(1.5).fill('transparent').width(24).height(24)`,
     `Image($r('app.media.ic_menu')).fillColor(Colors.foreground).width(24).height(24)`],
    [`Path().commands('M0 0 M24 24 M3 6 h18 M3 12 h18 M3 18 h18').stroke(Colors.foreground).strokeWidth(1.5).fill('transparent').width(24).height(24)`,
     `Image($r('app.media.ic_menu')).fillColor(Colors.foreground).width(24).height(24)`],
    [`Path().commands('M0 0 M24 24 M12 6 a1.5 1.5 0 1 1 0 -3 a1.5 1.5 0 0 1 0 3 M12 13.5 a1.5 1.5 0 1 1 0 -3 a1.5 1.5 0 0 1 0 3 M12 21 a1.5 1.5 0 1 1 0 -3 a1.5 1.5 0 0 1 0 3').fill(Colors.foreground).width(20).height(20)`,
     `Image($r('app.media.ic_dots')).fillColor(Colors.foreground).width(24).height(24)`],
    [`Path().commands('M0 0 M24 24 M4 4 h16 v16 h-16 z M12 4 v16').stroke(Colors.foregroundMuted).strokeWidth(1.5).fill('transparent').width(24).height(24)`,
     `Image($r('app.media.ic_tool')).fillColor(Colors.foregroundMuted).width(24).height(24)`],
    [`Path().commands('M0 0 M24 24 M4 4 h12 v12 h-12 z M8 4 v12 M4 8 h12').stroke(Colors.foreground).strokeWidth(1.5).fill('transparent').width(20).height(20).margin({ right: Spacing.sm })`,
     `Image($r('app.media.ic_panel')).fillColor(Colors.foreground).width(20).height(20).margin({ right: Spacing.sm })`],
    [`Path().commands('M0 0 M24 24 M6 9 l6 6 l6 -6').stroke(Colors.foregroundMuted).strokeWidth(1.5).fill('transparent').width(20).height(20)`,
     `Image($r('app.media.ic_chevron_down')).fillColor(Colors.foregroundMuted).width(20).height(20)`]
]);

replaceInFile('Anywhere_harmony/entry/src/main/ets/feature/workspace/WorkspaceDrawer.ets', [
    [`Path().commands('M0 0 M24 24 M6 6 l12 12 M18 6 l-12 12').stroke(Colors.foregroundMuted).strokeWidth(1.5).fill('transparent')\n            .width(20).height(20)`,
     `Image($r('app.media.ic_close')).fillColor(Colors.foregroundMuted).width(24).height(24)`]
]);

replaceInFile('Anywhere_harmony/entry/src/main/ets/common/ui/ToolCallCard.ets', [
    [`Path().commands('M0 0 M24 24 M6 12 l4 4 l8 -8').stroke(Colors.success).strokeWidth(1.5).fill('transparent')\n          .width(18).height(18).margin({ right: Spacing.sm })`,
     `Image($r('app.media.ic_check')).fillColor(Colors.success).width(16).height(16).margin({ right: Spacing.sm })`],
    [`Path().commands('M0 0 M24 24 M7 7 l10 10 M17 7 l-10 10').stroke(Colors.error).strokeWidth(1.5).fill('transparent')\n          .width(18).height(18).margin({ right: Spacing.sm })`,
     `Image($r('app.media.ic_error')).fillColor(Colors.error).width(16).height(16).margin({ right: Spacing.sm })`]
]);

replaceInFile('Anywhere_harmony/entry/src/main/ets/common/ui/PlanView.ets', [
    [`Path().commands('M0 0 M24 24 M6 12 l4 4 l8 -8').stroke(Colors.success).strokeWidth(1.5).fill('transparent').width(16).height(16).margin({ left: Spacing.sm, top: 2 })`,
     `Image($r('app.media.ic_check')).fillColor(Colors.success).width(16).height(16).margin({ left: Spacing.sm, top: 4 })`],
    [`Path().commands('M0 0 M24 24 M6 12 a1.5 1.5 0 1 1 0 -3 a1.5 1.5 0 0 1 0 3 M12 12 a1.5 1.5 0 1 1 0 -3 a1.5 1.5 0 0 1 0 3 M18 12 a1.5 1.5 0 1 1 0 -3 a1.5 1.5 0 0 1 0 3').fill(Colors.warning).width(16).height(16).margin({ left: Spacing.sm, top: 2 })`,
     `Image($r('app.media.ic_dots')).fillColor(Colors.warning).width(16).height(16).margin({ left: Spacing.sm, top: 4 })`],
    [`Path().commands('M0 0 M24 24 M12 5 a7 7 0 1 1 0 14 a7 7 0 0 1 0 -14').stroke(Colors.foregroundLight).strokeWidth(1.5).fill('transparent').width(16).height(16).margin({ left: Spacing.sm, top: 2 })`,
     `Image($r('app.media.ic_circle')).fillColor(Colors.foregroundLight).width(16).height(16).margin({ left: Spacing.sm, top: 4 })`]
]);

replaceInFile('Anywhere_harmony/entry/src/main/ets/common/ui/ThinkingSection.ets', [
    [`Path().commands('M0 0 M24 24 M12 3 L14.5 8.5 L20 11 L14.5 13.5 L12 19 L9.5 13.5 L4 11 L9.5 8.5 Z')\n          .stroke(Colors.foregroundMuted).strokeWidth(1.5).fill('transparent')\n          .width(20).height(20).margin({ right: Spacing.sm })`,
     `Image($r('app.media.ic_thinking')).fillColor(Colors.foregroundMuted).width(20).height(20).margin({ right: Spacing.sm })`]
]);

replaceInFile('Anywhere_harmony/entry/src/main/ets/common/ui/MessageCard.ets', [
    [`Path().commands('M0 0 M24 24 M16 1 H4 c-1.1 0-2 .9-2 2 v14 h2 V3 h12 V1 z M15 5 H8 c-1.1 0-2 .9-2 2 v14 c0 1.1 .9 2 2 2 h7 c1.1 0 2-.9 2-2 V7 c0-1.1-.9-2-2-2 z m0 16 H8 V7 h7 v14 z')\n            .fill(Colors.foregroundLight).width(20).height(20)`,
     `Image($r('app.media.ic_copy')).fillColor(Colors.foregroundLight).width(20).height(20)`],
    [`Path().commands('M0 0 M24 24 M16 1 H4 c-1.1 0-2 .9-2 2 v14 h2 V3 h12 V1 z M15 5 H8 c-1.1 0-2 .9-2 2 v14 c0 1.1 .9 2 2 2 h7 c1.1 0 2-.9 2-2 V7 c0-1.1-.9-2-2-2 z m0 16 H8 V7 h7 v14 z')\n                  .fill(Colors.foregroundLight).width(20).height(20)`,
     `Image($r('app.media.ic_copy')).fillColor(Colors.foregroundLight).width(20).height(20)`]
]);

console.log("Done");
