#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const sourceDir = process.argv[2] ? path.resolve(process.argv[2]) : path.resolve('/Users/matpool/Downloads/svg2');
const mediaOutputDir = path.join(repoRoot, 'AiraBrowser/entry/src/main/resources/base/media');

const iconNames = new Map([
  ['主题.svg', 'app_reader_theme'],
  ['切换行距.svg', 'app_reader_line_height'],
  ['增大字号.svg', 'app_reader_increase_font'],
  ['朗读.svg', 'app_reader_read_aloud'],
  ['阅读区域宽度.svg', 'app_reader_page_width'],
  ['减小字号.svg', 'app_reader_decrease_font']
]);

const chromeColors = {
  light: '#383838',
  dark: '#ECE8E9'
};
const chromeStrokeWidth = '2';

function normalizeReaderSvg(svg, strokeColor, fileName) {
  let output = svg.replace(/\r\n/g, '\n').trim();
  output = output.replace(/<!--[\s\S]*?-->/g, '');
  output = output.replace(/\s+stroke="(?:#[0-9A-Fa-f]{6}|currentColor)"/g, ` stroke="${strokeColor}"`);
  output = output.replace(/\s+stroke-width="[^"]+"/g, ` stroke-width="${chromeStrokeWidth}"`);
  output = output.replace(/\s+fill="(?:#[0-9A-Fa-f]{6}|currentColor)"/g, ` fill="${strokeColor}"`);

  if (fileName === '切换行距.svg') {
    output = output.replace(
      /<path d="M8\.99776 7\.99835[\s\S]*?Z" fill="[^"]+"\/>/,
      [
        `<path d="M7.99776 7.99835V17.0021" stroke="${strokeColor}" stroke-width="${chromeStrokeWidth}" stroke-linecap="round" stroke-linejoin="round"/>`,
        `<path d="M3.99609 7.99835H11.9994" stroke="${strokeColor}" stroke-width="${chromeStrokeWidth}" stroke-linecap="round" stroke-linejoin="round"/>`
      ].join('\n')
    );
  }

  output = output.replace(/>\s+</g, '>\n<');
  output = output.replace(/\n{2,}/g, '\n').trim();
  return `${output}\n`;
}

function writeReaderSvgResources() {
  fs.mkdirSync(mediaOutputDir, { recursive: true });
  let written = 0;
  Array.from(iconNames.entries()).forEach(([fileName, mediaName]) => {
    const sourcePath = path.join(sourceDir, fileName);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`Missing SVG source: ${sourcePath}`);
    }
    const source = fs.readFileSync(sourcePath, 'utf8');
    fs.writeFileSync(
      path.join(mediaOutputDir, `${mediaName}_chrome_light.svg`),
      normalizeReaderSvg(source, chromeColors.light, fileName)
    );
    fs.writeFileSync(
      path.join(mediaOutputDir, `${mediaName}_chrome_dark.svg`),
      normalizeReaderSvg(source, chromeColors.dark, fileName)
    );
    written += 2;
  });
  console.log(`Generated ${written} reader SVG resources at ${path.relative(repoRoot, mediaOutputDir)}`);
}

writeReaderSvgResources();
