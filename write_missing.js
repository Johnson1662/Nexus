const fs = require('fs');
const path = require('path');

const svgDir = path.join(__dirname, 'Anywhere_harmony/entry/src/main/resources/base/media');
const svgs = {
  'ic_chevron_down.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  'ic_panel.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M4 4h12v12H4zM8 4v12M4 8h12" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>`,
  'ic_mic.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12 14c1.66 0 2.99-1.34 2.99-3L15 5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm5.3-3c0 3-2.54 5.1-5.3 5.1S6.7 14 6.7 11H5c0 3.41 2.72 6.23 6 6.72V21h2v-3.28c3.28-.48 6-3.3 6-6.72h-1.7z" fill="currentColor"/></svg>`,
  'ic_waveform.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M4 10v4M9 6v12M14 8v8M19 11v2" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`
};

for (const [name, content] of Object.entries(svgs)) {
  fs.writeFileSync(path.join(svgDir, name), content);
  console.log('Wrote', name);
}
