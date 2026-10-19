import 'package:flutter/material.dart';

import 'brand_paths.dart';
import 'svg_path.dart';
import 'tokens.dart';

/// 一笔线稿图标库 —— 路径数据从原型 `记账App/index.html` 原样照搬，
/// 未经任何改动，保证图形与设计稿 1:1 一致。
///
/// 统一参数：24×24 视图框、1.5 线宽（视图框单位）、圆头圆角、**无填充**。
const Map<String, String> kIcons = {
  // ---- 支出分类 ----
  'food': r'<path d="M5 13h14a7 7 0 0 1-14 0z"/><path d="M9.5 9.6V6.4M12 9.6V5.4M14.5 9.6V6.4"/>',
  'transport': r'<rect x="5" y="3.6" width="14" height="13" rx="3"/><path d="M5 11h14"/><circle cx="9" cy="13.6" r="1"/><circle cx="15" cy="13.6" r="1"/><path d="M8.6 16.6L7 20.2M15.4 16.6L17 20.2"/>',
  'shopping': r'<path d="M5.6 8h12.8l-1.1 11.4a1.5 1.5 0 0 1-1.5 1.4H8.2a1.5 1.5 0 0 1-1.5-1.4z"/><path d="M9 8V6.3a3 3 0 0 1 6 0V8"/>',
  'home': r'<path d="M4 10.8L12 4.4l8 6.4"/><path d="M6.4 9.7V20h11.2V9.7"/><path d="M10.2 20v-5.2h3.6V20"/>',
  'fun': r'<path d="M9.5 17.2V5.9l8.5-1.9v10.8"/><circle cx="7" cy="17.2" r="2.5"/><circle cx="15.5" cy="14.8" r="2.5"/>',
  'medical': r'<rect x="3.5" y="7.5" width="17" height="12" rx="2.5"/><path d="M9 7.5V6a1.8 1.8 0 0 1 1.8-1.8h2.4A1.8 1.8 0 0 1 15 6v1.5"/><path d="M12 11.2v5.4M9.3 13.9h5.4"/>',
  'study': r'<path d="M12 7.4S9.8 5.2 5 5.2v11.2c4.8 0 7 2.2 7 2.2s2.2-2.2 7-2.2V5.2c-4.8 0-7 2.2-7 2.2z"/><path d="M12 7.4v11.2"/>',
  'comm': r'<rect x="7" y="2.9" width="10" height="18.2" rx="2.6"/><path d="M10.8 18.1h2.4"/>',
  'gift': r'<rect x="4" y="8.6" width="16" height="11.9" rx="1.6"/><path d="M3 8.6h18M12 8.6v11.9"/><path d="M12 8.6C11 5.9 9.3 4.4 7.8 5.3 6.3 6.2 7.6 8.6 12 8.6zM12 8.6c1-2.7 2.7-4.2 4.2-3.3 1.5.9.2 3.3-4.2 3.3z"/>',
  'more': r'<circle cx="6" cy="12" r="1.25"/><circle cx="12" cy="12" r="1.25"/><circle cx="18" cy="12" r="1.25"/>',

  // ---- 收入分类 ----
  'salary': r'<rect x="2.8" y="6.6" width="18.4" height="10.8" rx="2"/><circle cx="12" cy="12" r="2.6"/><path d="M6.4 9.9v.01M17.6 14.1v.01"/>',
  'bonus': r'<circle cx="12" cy="9.3" r="5.5"/><path d="M8.6 13.8L7 20.5l5-2.6 5 2.6-1.6-6.7"/>',
  'parttime': r'<rect x="3" y="7.2" width="18" height="12.3" rx="2"/><path d="M9 7.2V5.8a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v1.4"/><path d="M3 12.3h18"/>',
  'invest': r'<path d="M3.5 16.6l5-5 3.5 3.5 8-8"/><path d="M15 7.1h5v5"/>',
  'redpacket': r'<rect x="5" y="3.6" width="14" height="16.8" rx="2.4"/><path d="M5 3.6a7 7 0 0 1 14 0"/><circle cx="12" cy="11.2" r="1.8"/>',

  // ---- 设置 / 功能 ----
  'upload': r'<path d="M12 15.5V4.6"/><path d="M7.6 8.6L12 4.2l4.4 4.4"/><path d="M4.4 15.4v2.8a2 2 0 0 0 2 2h11.2a2 2 0 0 0 2-2v-2.8"/>',
  'download': r'<path d="M12 4.5v10.9"/><path d="M7.6 11.2L12 15.6l4.4-4.4"/><path d="M4.4 15.4v2.8a2 2 0 0 0 2 2h11.2a2 2 0 0 0 2-2v-2.8"/>',
  'lock': r'<rect x="4.6" y="10.4" width="14.8" height="9.8" rx="2.2"/><path d="M8.2 10.4V7.6a3.8 3.8 0 0 1 7.6 0v2.8"/>',
  'tag': r'<path d="M11.4 3.6H20v8.6l-8.6 8.6-8.6-8.6z"/><circle cx="16" cy="7.6" r="1.4"/>',
  'bell': r'<path d="M6.4 10.2a5.6 5.6 0 1 1 11.2 0c0 4 1.6 5.4 1.6 5.4H4.8s1.6-1.4 1.6-5.4z"/><path d="M10.2 18.6a2 2 0 0 0 3.6 0"/>',
  'coin': r'<circle cx="12" cy="12" r="8.4"/><path d="M12 7.4v9.2M14.6 9.4H10.3a1.9 1.9 0 0 0 0 3.8h3.4a1.9 1.9 0 0 1 0 3.8H9.4"/>',
  'moon':
      r'<path d="M20.2 14.2A8.6 8.6 0 0 1 9.8 3.8a8.8 8.8 0 1 0 10.4 10.4z"/>',
  'doc': r'<path d="M6.4 4.6a2 2 0 0 1 2-2h5.4l4.8 4.8v11.6a2 2 0 0 1-2 2H8.4a2 2 0 0 1-2-2z"/><path d="M13.6 2.6v5h5"/><path d="M9.6 12.6h6M9.6 16h4"/>',
  'info':
      r'<circle cx="12" cy="12" r="8.6"/><path d="M12 11.2v5.2M12 7.9v.01"/>',

  // ---- 计划页与储蓄目标 ----
  'target': r'<circle cx="12" cy="12" r="8.4"/><circle cx="12" cy="12" r="4.2"/><circle cx="12" cy="12" r=".9"/>',
  'plane': r'<path d="M20.8 3.2L2.8 10.9l6.6 2.6 2.6 6.6z"/><path d="M20.8 3.2l-11.4 10.3"/>',
  'laptop': r'<rect x="4.2" y="5.2" width="15.6" height="10.6" rx="2"/><path d="M2.6 19h18.8"/>',
  'flag': r'<path d="M6 20.6V3.6"/><path d="M6 4.3h11.4l-2.2 4 2.2 4H6"/>',
  'car': r'<rect x="3.6" y="9.6" width="16.8" height="6.8" rx="2.4"/><path d="M6.2 9.6l1.5-3a1.5 1.5 0 011.3-.8h6a1.5 1.5 0 011.3.8l1.5 3"/><circle cx="7.6" cy="16.4" r="1.2"/><circle cx="16.4" cy="16.4" r="1.2"/>',
  'wallet': r'<path d="M3.6 8.4a2 2 0 012-2h11.4a2 2 0 012 2v8.2a2 2 0 01-2 2H5.6a2 2 0 01-2-2z"/><path d="M3.6 11.6h16.8"/><circle cx="15.6" cy="15" r="1"/>',

  // ---- 设置区 ----
  'book': r'<rect x="4.5" y="3" width="15" height="18" rx="2"/><path d="M8.5 3v18"/><path d="M12 8h4M12 12h4"/>',
  'card': r'<rect x="2.8" y="5.5" width="18.4" height="13" rx="2.5"/><path d="M2.8 10h18.4"/><path d="M6.5 14.5h3"/>',
  'tpl': r'<rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/><path d="M3.5 9.5h17M9.5 9.5v10"/>',
  'rec': r'<path d="M20.5 12a8.5 8.5 0 11-2.6-6.1"/><path d="M20.5 3.4v5.2h-5.2"/><path d="M12 7.6V12l3 1.9"/>',

  // ---- 底部导航（原型里是内联 SVG，不在 ICONS 表中，此处补齐）----
  'list': r'<path d="M4 6h16M4 12h16M4 18h10"/>',
  'pie': r'<path d="M12 3.2a8.8 8.8 0 108.8 8.8H12z"/><path d="M14.3 3.6a8.4 8.4 0 016.4 6.4h-6.4z"/>',
  'person': r'<circle cx="12" cy="8.5" r="3.6"/><path d="M4.8 20a7.2 7.2 0 0114.4 0"/>',
  'plus': r'<path d="M12 5.5v13M5.5 12h13"/>',

  // ---- 子分类图标（2026-10 两级分类新增）----
  // 原型里没有子分类这一层，以下 41 个是按同一套规格新画的：
  // 24×24 视图框、1.5 线宽、圆头圆角、无填充、四周留 3 以上的安全边。
  // 画法刻意保持简单几何（矩形 + 直线 + 圆弧），避免细节在 20dp 下糊成一团。

  // 餐饮
  // 用户指定：餐饮用勺叉组合、正餐用单把勺子（原来两个都是「碗 + 筷子」，
  // 一级和子级长得一模一样，看起来像没配图标）
  'basket': r'<path d="M4.2 9.2h15.6l-1.7 9a2 2 0 0 1-2 1.6H7.9a2 2 0 0 1-2-1.6z"/><path d="M8.8 9.2L10.6 4.6M15.2 9.2L13.4 4.6"/><path d="M9.4 13v3.2M14.6 13v3.2"/>',
  'utensils': r'<path d="M5.6 3.4v4.2M8 3.4v4.2M10.4 3.4v4.2"/><path d="M5.6 7.6a2.4 2.4 0 0 0 4.8 0"/><path d="M8 10.2V20.6"/><path d="M16.6 4.2c1.7 0 3 1.6 3 3.8s-1.3 3.8-3 3.8-3-1.6-3-3.8 1.3-3.8 3-3.8z"/><path d="M16.6 11.8V20.6"/>',
  'spoon': r'<path d="M12 3.8c1.8 0 3.2 1.7 3.2 3.9S13.8 11.6 12 11.6 8.8 9.9 8.8 7.7 10.2 3.8 12 3.8z"/><path d="M12 11.6V20.4"/>',
  'cup': r'<path d="M6.8 8h10.4l-.9 10.6a2.2 2.2 0 0 1-2.2 2H9.9a2.2 2.2 0 0 1-2.2-2z"/><path d="M13.6 8l1.4-4.4"/><path d="M7.6 12.4h8.8"/>',
  'snack': r'<path d="M6.6 7.4h10.8l-.9 11.8a2 2 0 0 1-2 1.8H9.5a2 2 0 0 1-2-1.8z"/><path d="M6.6 7.4l1.9-2.6 1.9 2.6 1.9-2.6 1.9 2.6 1.9-2.6 1.3 2.6"/>',
  'wine': r'<path d="M10.2 3.6h3.6v3.2c0 1.1.5 1.7 1.1 2.5.6.8 1 1.9 1 3.1v8.4a2.2 2.2 0 0 1-2.2 2.2h-3.4a2.2 2.2 0 0 1-2.2-2.2v-8.4c0-1.2.4-2.3 1-3.1.6-.8 1.1-1.4 1.1-2.5z"/><path d="M9.6 14.4h4.8"/>',
  'group': r'<circle cx="9" cy="8.6" r="2.9"/><path d="M3.4 19.6a5.6 5.6 0 0 1 11.2 0"/><circle cx="17" cy="9.8" r="2.2"/><path d="M15.2 14.9a4.8 4.8 0 0 1 5.6 4.7"/>',
  'toast': r'<circle cx="12" cy="12" r="8.2"/><circle cx="12" cy="12" r="4.6"/>',

  // 出行
  'taxi': r'<rect x="4" y="10.4" width="16" height="6" rx="2"/><path d="M6.4 10.4l1.4-2.8a1.6 1.6 0 0 1 1.4-.9h5.6a1.6 1.6 0 0 1 1.4.9l1.4 2.8"/><circle cx="8" cy="16.6" r="1.1"/><circle cx="16" cy="16.6" r="1.1"/><rect x="10.2" y="3.8" width="3.6" height="2.2" rx=".7"/>',
  'fuel': r'<path d="M5.6 20V6.6a2 2 0 0 1 2-2h4.2a2 2 0 0 1 2 2V20"/><path d="M4 20h10.4"/><path d="M7.4 9.6h4.6"/><path d="M13.8 8.4h2l1.8 2.2v5.4a1.6 1.6 0 0 0 3.2 0v-6l-1.6-1.6"/>',
  'parking': r'<rect x="3.6" y="3.6" width="16.8" height="16.8" rx="3.6"/><path d="M10 16.8V7.2h3a2.6 2.6 0 0 1 0 5.2h-3"/>',
  'bike': r'<circle cx="6.2" cy="16.4" r="3.2"/><circle cx="17.8" cy="16.4" r="3.2"/><path d="M6.2 16.4l3.4-6h5.4l2.8 6"/><path d="M9.6 10.4H7.2M14.8 10.4l-1.2-3h-2.4"/>',
  'key': r'<circle cx="8.4" cy="8.4" r="4"/><path d="M11.2 11.2L20 20"/><path d="M16.6 16.6l-1.8 1.8M18.8 18.8l-1.8 1.8"/>',

  // 居家
  'drop': r'<path d="M12 3.4s5.6 6 5.6 9.6a5.6 5.6 0 0 1-11.2 0C6.4 9.4 12 3.4 12 3.4z"/>',
  'building': r'<rect x="5.4" y="3.4" width="13.2" height="17.2" rx="1.8"/><path d="M9 7.4h1.8M13.2 7.4H15M9 10.8h1.8M13.2 10.8H15M9 14.2h1.8M13.2 14.2H15"/><path d="M10.4 20.6v-3.4h3.2v3.4"/>',
  'sofa': r'<path d="M4.6 12V9.4a2.2 2.2 0 0 1 2.2-2.2h10.4a2.2 2.2 0 0 1 2.2 2.2V12"/><path d="M4.2 12.4a1.9 1.9 0 0 1 3.5 0v2.4h8.6v-2.4a1.9 1.9 0 0 1 3.5 0v4.4a1.9 1.9 0 0 1-1.9 1.9H6.1a1.9 1.9 0 0 1-1.9-1.9z"/>',
  'wrench': r'<path d="M15.2 3.6l-2.2 4.4 1.4 1.4 4.4-2.2a4.8 4.8 0 0 1-6.2 6.2L6.2 20 4 17.8l6.6-6.6a4.8 4.8 0 0 1 4.6-7.6z"/>',

  // 购物
  'shirt': r'<path d="M9.2 4.4L5 6.6l1.6 4.2 1.6-.8V19.6h7.6V10l1.6.8L19 6.6l-4.2-2.2a3.6 3.6 0 0 1-5.6 0z"/>',
  'cosmetic': r'<rect x="9.4" y="10.4" width="5.2" height="10" rx="1.2"/><path d="M9.8 10.4V6.2h4.4v4.2"/><path d="M10.6 6.2V3.6h2.8v2.6"/>',
  'baby': r'<path d="M8.6 8.4h6.8v10.4a2 2 0 0 1-2 2h-2.8a2 2 0 0 1-2-2z"/><path d="M10.4 8.4V6.8h3.2v1.6"/><path d="M11.2 6.8V4.6a1.4 1.4 0 0 1 2.8 0v2.2"/><path d="M8.6 12.4h6.8M8.6 15.8h6.8"/>',
  'paw': r'<circle cx="8.2" cy="8.6" r="1.9"/><circle cx="12" cy="6.8" r="1.9"/><circle cx="15.8" cy="8.6" r="1.9"/><circle cx="5.8" cy="12.6" r="1.7"/><path d="M12 11.4c2.9 0 5.2 2.1 5.2 4.4 0 1.8-1.4 2.7-3 2.3-1.4-.4-3-.4-4.4 0-1.6.4-3-.5-3-2.3 0-2.3 2.3-4.4 5.2-4.4z"/>',

  // 健康
  // 药瓶而不是「圆 + 斜线」：后者在 20dp 下会被读成禁止标志
  'pill': r'<rect x="8.4" y="7.2" width="7.2" height="11.4" rx="1.8"/><path d="M8.4 11.2h7.2"/><path d="M10.2 7.2V4.4h3.6v2.8"/><path d="M10.4 14.4h3.2"/>',
  'pulse': r'<path d="M3.2 12h4.2l2-4.4 3.4 9.2 2.2-4.8h5.8"/>',
  'heart': r'<path d="M12 20.4S3.6 14.8 3.6 9.4a4.4 4.4 0 0 1 8.4-1.8 4.4 4.4 0 0 1 8.4 1.8c0 5.4-8.4 11-8.4 11z"/>',
  'eye': r'<path d="M2.8 12S6.4 6.6 12 6.6 21.2 12 21.2 12 17.6 17.4 12 17.4 2.8 12 2.8 12z"/><circle cx="12" cy="12" r="2.6"/>',
  'dumbbell': r'<path d="M5.4 12h13.2"/><rect x="2.6" y="8.8" width="2.8" height="6.4" rx="1.2"/><rect x="18.6" y="8.8" width="2.8" height="6.4" rx="1.2"/><rect x="6.2" y="7.6" width="3" height="8.8" rx="1.2"/><rect x="14.8" y="7.6" width="3" height="8.8" rx="1.2"/>',
  'chat': r'<path d="M4.2 6.6a2.4 2.4 0 0 1 2.4-2.4h10.8a2.4 2.4 0 0 1 2.4 2.4v7.2a2.4 2.4 0 0 1-2.4 2.4H9.6l-4.2 3.4z"/>',

  // 娱乐
  'film': r'<rect x="3.4" y="5.4" width="17.2" height="13.2" rx="2"/><path d="M7.8 5.4v13.2M16.2 5.4v13.2M3.4 12h17.2"/>',
  'gamepad': r'<path d="M7.8 8.4h8.4a4.6 4.6 0 0 1 4.5 5.6l-.6 3a2 2 0 0 1-3.4 1.1l-1.8-1.8H8.1l-1.8 1.8a2 2 0 0 1-3.4-1.1l-.6-3a4.6 4.6 0 0 1 4.5-5.6z"/><path d="M8.6 11.4v2.6M7.3 12.7h2.6"/><circle cx="15.8" cy="12.4" r=".9"/>',
  'crown': r'<path d="M3.8 8.6l3.2 3 5-6.2 5 6.2 3.2-3-1.6 9.2H5.4z"/>',

  // 人情
  'elder': r'<circle cx="10" cy="7.2" r="2.8"/><path d="M5.8 20v-3.2A4.2 4.2 0 0 1 10 12.6h.8"/><path d="M16.8 20V9.4a2.4 2.4 0 0 0-4.8 0"/>',
  'envelope': r'<rect x="3.4" y="6" width="17.2" height="12" rx="2"/><path d="M3.8 7.2l8.2 6 8.2-6"/>',

  // 成长
  'certificate': r'<rect x="3.4" y="3.8" width="17.2" height="11.4" rx="1.8"/><path d="M6.6 7.6h10M6.6 10.8h6"/><circle cx="16.2" cy="16.4" r="2.2"/><path d="M14.9 18.2l-.9 2.2 2.2-1 2.2 1-.9-2.2"/>',
  'bulb': r'<path d="M9 16.4a1 1 0 0 1-1-1v-.9a5.6 5.6 0 1 1 8 0v.9a1 1 0 0 1-1 1z"/><path d="M9.8 18.8h4.4M10.6 21h2.8"/>',
  'pen': r'<path d="M4 20l1.2-4.2L15.6 5.4l3 3L8.2 18.8z"/><path d="M14.2 6.8l3 3"/>',
  'board': r'<rect x="3.4" y="4.6" width="17.2" height="11.4" rx="2"/><path d="M12 16v3.6M8.4 20.4h7.2"/><path d="M7 8.4h4.4M7 11.6h6.4"/>',
  'gear': r'<circle cx="12" cy="12" r="3.2"/><path d="M12 3.2v2.6M12 18.2v2.6M20.8 12h-2.6M5.8 12H3.2M18.2 5.8l-1.8 1.8M7.6 16.4l-1.8 1.8M18.2 18.2l-1.8-1.8M7.6 7.6L5.8 5.8"/>',

  // 其他 + 收入补充
  'shield': r'<path d="M12 3.4l7.2 2.8v6c0 4.4-3 7.4-7.2 8.8-4.2-1.4-7.2-4.4-7.2-8.8v-6z"/>',
  'percent': r'<path d="M5.8 18.2L18.2 5.8"/><circle cx="7.4" cy="7.4" r="2.2"/><circle cx="16.6" cy="16.6" r="2.2"/>',
  'alert': r'<path d="M12 4.4l8.4 15H3.6z"/><path d="M12 10v4.4M12 17.2v.01"/>',
  'calendar': r'<rect x="3.6" y="5.4" width="16.8" height="15" rx="2"/><path d="M3.6 10h16.8M8.4 3.2v4.2M15.6 3.2v4.2"/>',
  'chart': r'<path d="M4 4v16h16"/><rect x="7" y="12" width="2.8" height="5"/><rect x="11.6" y="8.6" width="2.8" height="8.4"/><rect x="16.2" y="14.4" width="2.8" height="2.6"/>',
  'receipt': r'<path d="M6.2 3.6h11.6v16.8l-1.9-1.4-2 1.4-1.9-1.4-2 1.4-1.9-1.4-1.9 1.4z"/><path d="M9 8h6M9 11.4h6"/>',
  'star': r'<path d="M12 3.6l2.6 5.6 6 .8-4.4 4.2 1.1 6-5.3-2.9-5.3 2.9 1.1-6-4.4-4.2 6-.8z"/>',
};

/// 已解析路径的缓存。图标会在列表里被反复构建，解析一次即可。
final Map<String, Path> _pathCache = {};

Path lineIconPath(String name) => _pathCache.putIfAbsent(
  name,
  () => parseSvgFragment(kIcons[name] ?? kIcons['more']!),
);

/// 线稿图标。
///
/// [size] 是渲染尺寸；[strokeWidth] 是**视图框单位**下的线宽（默认 1.5）。
/// [scaleStroke] 为 true 时线宽随 size 等比缩放 —— 这与原型里
/// `<svg width="20" viewBox="0 0 24 24" stroke-width="1.5">` 的表现完全一致。
/// 需要「大图标但线不变粗」时传 false。
class LineIcon extends StatelessWidget {
  const LineIcon(
    this.name, {
    super.key,
    this.size = 20,
    required this.color,
    this.strokeWidth = 1.5,
    this.scaleStroke = true,
  });

  final String name;
  final double size;
  final Color color;
  final double strokeWidth;
  final bool scaleStroke;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _LineIconPainter(
          path: lineIconPath(name),
          color: color,
          strokeWidth: scaleStroke ? strokeWidth : strokeWidth * 24.0 / size,
        ),
      ),
    );
  }
}

class _LineIconPainter extends CustomPainter {
  _LineIconPainter({
    required this.path,
    required this.color,
    required this.strokeWidth,
  });

  final Path path;
  final Color color;

  /// **视图框单位**下的线宽：画布已按 size/24 缩放，这里直接就是该值。
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24.0;
    canvas.save();
    canvas.scale(s);
    // 原型里 svg 根元素默认 overflow:hidden，超出 24×24 视图框的部分会被裁掉
    // （例如 redpacket 的顶部半圆）。这里保持同样行为，保证图形不走样。
    canvas.clipRect(const Rect.fromLTWH(0, 0, 24, 24));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LineIconPainter old) =>
      old.path != path || old.color != color || old.strokeWidth != strokeWidth;
}

/// 品牌标志。视图框 455×944，主体实心、火焰叠红。
///
/// ⚠️ 必须用 [PathFillType.evenOdd]：眼睛处嵌套了 4 层轮廓
/// （外杏仁 → 白区 → 眼环 → 环内白区），nonzero 会把眼内白区填实。
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    required this.height,
    this.fg = C.ink,
    this.flameColor = C.over,
  });

  final double height;
  final Color fg;
  final Color flameColor;

  @override
  Widget build(BuildContext context) {
    const w = 455.0, h = 944.0;
    return SizedBox(
      width: height * w / h,
      height: height,
      child: CustomPaint(
        painter: _BrandMarkPainter(fg: fg, flameColor: flameColor),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter({required this.fg, required this.flameColor});

  final Color fg;
  final Color flameColor;

  static final Path _body = parseSvgPath(
    kMarkPath,
    fillType: PathFillType.evenOdd,
  );
  static final Path _flame = parseSvgPath(
    kFlamePath,
    fillType: PathFillType.evenOdd,
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // 视图框 9,5,437,932 → 缩放到目标尺寸
    canvas.scale(size.width / 455.0, size.height / 944.0);
    canvas.translate(-9, -5);
    canvas.drawPath(
      _body,
      Paint()
        ..color = fg
        ..isAntiAlias = true,
    );
    canvas.drawPath(
      _flame,
      Paint()
        ..color = flameColor
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandMarkPainter old) =>
      old.fg != fg || old.flameColor != flameColor;
}
