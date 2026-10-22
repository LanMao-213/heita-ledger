// 从定稿的 黑塔图标.svg 生成 Android 各密度图标资源。
// 形状完全照搬源路径，本脚本只做「缩放 / 居中 / 换色」，不改任何几何形状。
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const SRC = process.env.HEITA_ICON_SVG || 'prototype/记账App/黑塔图标.svg';
const RES = process.env.HEITA_RES_DIR || 'android/app/src/main/res';

const src = fs.readFileSync(SRC, 'utf8');
const ds = [...src.matchAll(/\sd="([^"]+)"/g)].map((m) => m[1]);
if (ds.length < 2) throw new Error('未能从源 SVG 提取到两段路径');
const [markD, flameD] = ds;

// 源 viewBox
const VX = 9, VY = 5, VW = 437, VH = 932;

// 深色底配色（与启动页深色版一致）
const INK_ON_DARK = '#FFFFFF';
const FLAME_ON_DARK = '#E8493A';
const BG_DARK = '#14161A';

/** 在 size×size 画布上居中放置标志，返回 transform 字符串 */
function fit(size, targetRatio) {
  // targetRatio = 标志高度 / 画布边长
  const h = size * targetRatio;
  const s = h / VH;
  const w = VW * s;
  const x = (size - w) / 2;
  const y = (size - h) / 2;
  return { transform: `translate(${(x - VX * s).toFixed(4)},${(y - VY * s).toFixed(4)}) scale(${s.toFixed(6)})`, s, w, h };
}

/** 自适应图标前景：透明底，白色标志 + 亮红火焰 */
function foregroundSvg() {
  const size = 108;
  const { transform } = fit(size, 0.65); // 70dp / 108dp，贴合 72dp 安全区
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <g transform="${transform}">
    <path d="${markD}" fill="${INK_ON_DARK}" fill-rule="evenodd"/>
    <path d="${flameD}" fill="${FLAME_ON_DARK}" fill-rule="evenodd"/>
  </g>
</svg>`;
}

/** Android 13+ 主题图标（单色层）：整体纯白剪影，由系统着色 */
function monochromeSvg() {
  const size = 108;
  const { transform } = fit(size, 0.65);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <g transform="${transform}">
    <path d="${markD}" fill="#FFFFFF" fill-rule="evenodd"/>
    <path d="${flameD}" fill="#FFFFFF" fill-rule="evenodd"/>
  </g>
</svg>`;
}

/** 传统图标（Android 7 及以下 / 桌面兜底）：深底 + 白标志 */
function legacySvg() {
  const size = 48;
  const { transform } = fit(size, 0.60);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <rect width="${size}" height="${size}" fill="${BG_DARK}"/>
  <g transform="${transform}">
    <path d="${markD}" fill="${INK_ON_DARK}" fill-rule="evenodd"/>
    <path d="${flameD}" fill="${FLAME_ON_DARK}" fill-rule="evenodd"/>
  </g>
</svg>`;
}

const DENSITIES = [
  ['mdpi', 1],
  ['hdpi', 1.5],
  ['xhdpi', 2],
  ['xxhdpi', 3],
  ['xxxhdpi', 4],
];

(async () => {
  const fg = foregroundSvg();
  const lg = legacySvg();
  const mono = monochromeSvg();

  for (const [dpi, mul] of DENSITIES) {
    const dir = path.join(RES, `mipmap-${dpi}`);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    // 前景层：108dp
    await sharp(Buffer.from(fg), { density: 600 })
      .resize(Math.round(108 * mul), Math.round(108 * mul))
      .png()
      .toFile(path.join(dir, 'ic_launcher_foreground.png'));

    // 单色层（Android 13+ 主题图标）：108dp
    await sharp(Buffer.from(mono), { density: 600 })
      .resize(Math.round(108 * mul), Math.round(108 * mul))
      .png()
      .toFile(path.join(dir, 'ic_launcher_monochrome.png'));

    // 传统图标：48dp
    await sharp(Buffer.from(lg), { density: 600 })
      .resize(Math.round(48 * mul), Math.round(48 * mul))
      .png()
      .toFile(path.join(dir, 'ic_launcher.png'));

    console.log(`${dpi}: foreground ${Math.round(108 * mul)}px, legacy ${Math.round(48 * mul)}px`);
  }

  // 中间产物：留一张 432 供人工核对
  await sharp(Buffer.from(fg), { density: 600 }).resize(432, 432).png()
    .toFile(path.join('build', 'visual', 'icon_fg_preview.png'));
  await sharp(Buffer.from(lg), { density: 600 }).resize(432, 432).png()
    .toFile(path.join('build', 'visual', 'icon_legacy_preview.png'));
  console.log('已生成预览图');
})();
