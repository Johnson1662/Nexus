const fs = require('fs');
const path = require('path');
const svgDir = path.join(__dirname, 'Anywhere_harmony/entry/src/main/resources/base/media');

const svgs = {
  'ic_terminal.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z" fill="none" stroke="currentColor" stroke-width="2"/><path d="M6 9l4 3-4 3M12 15h6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  'ic_clear.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M3 6h18M8 6V4c0-1.1.9-2 2-2h4c1.1 0 2 .9 2 2v2M10 11v6M14 11v6M5 6l1 14c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2l1-14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`
};

for (const [name, content] of Object.entries(svgs)) {
  fs.writeFileSync(path.join(svgDir, name), content);
  console.log('Created:', name);
}
