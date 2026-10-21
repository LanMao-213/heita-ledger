import 'package:flutter/material.dart';

/// 图标名 → `IconData` 的**唯一映射**。
///
/// 分类种子里存的是**字符串**图标名（`utensils` / `transport` / `salary`…），
/// 好处是数据层不认识 Flutter；代价是要有这一张表。
///
/// 规矩：**认不出的名字一律回落 `more`**，不许抛异常也不许留空 ——
/// 用户改了图标名 / 老备份带进来一个没见过的名字，界面必须照常渲染。
abstract final class IconMap {
  static const Map<String, IconData> _map = <String, IconData>{
    // 支出
    'utensils': Icons.restaurant_outlined,
    'spoon': Icons.ramen_dining_outlined,
    'basket': Icons.shopping_basket_outlined,
    'cup': Icons.local_cafe_outlined,
    'snack': Icons.icecream_outlined,
    'wine': Icons.local_bar_outlined,
    'group': Icons.groups_outlined,
    'transport': Icons.directions_subway_outlined,
    'taxi': Icons.local_taxi_outlined,
    'fuel': Icons.local_gas_station_outlined,
    'parking': Icons.local_parking_outlined,
    'bike': Icons.pedal_bike_outlined,
    'car': Icons.directions_car_outlined,
    'home': Icons.home_outlined,
    'key': Icons.key_outlined,
    'drop': Icons.water_drop_outlined,
    'building': Icons.apartment_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'sofa': Icons.chair_outlined,
    'wrench': Icons.build_outlined,
    'comm': Icons.wifi_outlined,
    'shirt': Icons.checkroom_outlined,
    'cosmetic': Icons.spa_outlined,
    'laptop': Icons.laptop_mac_outlined,
    'baby': Icons.child_friendly_outlined,
    'paw': Icons.pets_outlined,
    'medical': Icons.local_hospital_outlined,
    'pill': Icons.medication_outlined,
    'pulse': Icons.monitor_heart_outlined,
    'eye': Icons.visibility_outlined,
    'dumbbell': Icons.fitness_center_outlined,
    'chat': Icons.psychology_outlined,
    'fun': Icons.celebration_outlined,
    'film': Icons.movie_outlined,
    'plane': Icons.flight_takeoff_outlined,
    'gamepad': Icons.sports_esports_outlined,
    'crown': Icons.workspace_premium_outlined,
    'gift': Icons.card_giftcard_outlined,
    'redpacket': Icons.redeem_outlined,
    'toast': Icons.emoji_food_beverage_outlined,
    'elder': Icons.elderly_outlined,
    'heart': Icons.volunteer_activism_outlined,
    'study': Icons.school_outlined,
    'certificate': Icons.workspace_premium_outlined,
    'book': Icons.menu_book_outlined,
    'doc': Icons.description_outlined,
    'bulb': Icons.lightbulb_outline,
    'gear': Icons.settings_outlined,
    'more': Icons.more_horiz,
    'shield': Icons.shield_outlined,
    'percent': Icons.percent,
    'alert': Icons.error_outline,
    // 收入
    'salary': Icons.account_balance_wallet_outlined,
    'bonus': Icons.redeem_outlined,
    'moon': Icons.nightlight_outlined,
    'coin': Icons.paid_outlined,
    'rec': Icons.replay_outlined,
    'calendar': Icons.calendar_month_outlined,
    'chart': Icons.bar_chart_outlined,
    'parttime': Icons.work_outline,
    'pen': Icons.edit_outlined,
    'board': Icons.school_outlined,
    'invest': Icons.trending_up_outlined,
    'pie': Icons.pie_chart_outline,
    'envelope': Icons.mail_outline,
    'receipt': Icons.receipt_long_outlined,
    'tag': Icons.sell_outlined,
    'star': Icons.star_outline,
    // 其它
    'target': Icons.flag_outlined,
    'tpl': Icons.bolt_outlined,
    'cash': Icons.payments_outlined,
    'debit': Icons.credit_card_outlined,
    'credit': Icons.credit_score_outlined,
    'alipay': Icons.account_balance_outlined,
    'wechat': Icons.chat_bubble_outline,
    'other': Icons.more_horiz,
  };

  /// 取图标；认不出回落 `more`。
  static IconData of(String? name) {
    if (name == null || name.isEmpty) return Icons.more_horiz;
    return _map[name] ?? Icons.more_horiz;
  }

  /// 表里有的名字（测试用：断言种子里的图标名都在映射表内）。
  static Set<String> get known => _map.keys.toSet();
}
