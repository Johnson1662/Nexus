const fs = require('fs');
const path = require('path');

const svgDir = path.join(__dirname, 'Anywhere_harmony/entry/src/main/resources/base/media');

const svgs = {
  'ic_knot.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M8.5 15.5 C 5 15.5, 4 11, 7 7 C 10 3, 16 3, 19 8 C 22 13, 17 18, 12 18 C 7 18, 5 15, 5 15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  'ic_scan.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M3 3v8h8V3H3zm6 6H5V5h4v4zm-6 4v8h8v-8H3zm6 6H5v-4h4v4zm4-16v8h8V3h-8zm6 6h-4V5h4v4zm-6 4h2v2h-2zm2 2h2v2h-2zm-2 2h2v2h-2zm2 2h2v2h-2zm2-2h2v2h-2zm0-4h2v2h-2zm2 2h2v2h-2z" fill="currentColor"/></svg>`,
  'ic_link.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z" fill="currentColor"/></svg>`,
  'ic_paste.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M19 3h-4.18C14.4 1.84 13.3 1 12 1c-1.3 0-2.4.84-2.82 2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1z" fill="currentColor"/></svg>`,
  'ic_menu.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M4 6h16M4 12h16M4 18h16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`,
  'ic_close.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M6 6l12 12M18 6L6 18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`,
  'ic_copy.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M16 1 H4 c-1.1 0-2 .9-2 2 v14 h2 V3 h12 V1 z M15 5 H8 c-1.1 0-2 .9-2 2 v14 c0 1.1 .9 2 2 2 h7 c1.1 0 2-.9 2-2 V7 c0-1.1-.9-2-2-2 z m0 16 H8 V7 h7 v14 z" fill="currentColor"/></svg>`,
  'ic_attachment.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M16.5 6 v11.5 c0 2.21 -1.79 4 -4 4 s -4 -1.79 -4 -4 V5 a2.5 2.5 0 0 1 5 0 v10.5 c0 .55 -.45 1 -1 1 s -1 -.45 -1 -1 V6 H10 v9.5 a2.5 2.5 0 0 0 5 0 V5 c0 -2.21 -1.79 -4 -4 -4 S7 2.79 7 5 v12.5 c0 3.04 2.46 5.5 5.5 5.5 s5.5 -2.46 5.5 -5.5 V6 h-1.5 z" fill="currentColor"/></svg>`,
  'ic_model.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M4 4 h5 v5 h-5 z M15 4 h5 v5 h-5 z M4 15 h5 v5 h-5 z M15 15 h5 v5 h-5 z" fill="currentColor"/></svg>`,
  'ic_send_active.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M2 21 l21 -9 L2 3 v7 l15 2 l-15 2 z" fill="currentColor"/></svg>`,
  'ic_send_disabled.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12 14 c1.66 0 2.99-1.34 2.99-3 L15 5 c0-1.66-1.34-3-3-3 S9 3.34 9 5 v6 c0 1.66 1.34 3 3 3 z m5.3-3 c0 3-2.54 5.1-5.3 5.1 S6.7 14 6.7 11 H5 c0 3.41 2.72 6.23 6 6.72 V21 h2 v-3.28 c3.28-.48 6-3.3 6-6.72 h-1.7 z" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M4 10 v4 M9 6 v12 M14 8 v8 M19 11 v2" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`,
  'ic_thinking.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M12 3 L14.5 8.5 L20 11 L14.5 13.5 L12 19 L9.5 13.5 L4 11 L9.5 8.5 Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>`,
  'ic_check.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M5 12l4 4 10-10" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
  'ic_dots.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle cx="5" cy="12" r="2" fill="currentColor"/><circle cx="12" cy="12" r="2" fill="currentColor"/><circle cx="19" cy="12" r="2" fill="currentColor"/></svg>`,
  'ic_circle.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><circle cx="12" cy="12" r="7" fill="none" stroke="currentColor" stroke-width="2"/></svg>`,
  'ic_error.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M18 6L6 18M6 6l12 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>`,
  'ic_tool.svg': `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path d="M4 4 h16 v16 h-16 z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M12 4 v16" fill="none" stroke="currentColor" stroke-width="2"/></svg>`
};

if (!fs.existsSync(svgDir)) {
  fs.mkdirSync(svgDir, { recursive: true });
}

for (const [name, content] of Object.entries(svgs)) {
  fs.writeFileSync(path.join(svgDir, name), content);
  console.log('Created:', name);
}
