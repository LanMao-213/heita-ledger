import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// 「本地存储」说明的正文。
///
/// 这是全 App 唯一解释「数据存在哪、会怎么消失」的地方，所以措辞必须与实现
/// 一致。当前实现对应的四件事：
/// - 数据库是 SQLite、落在应用私有目录，**未加密**（所以只说"私有目录"，
///   不说"加密存储"）；
/// - `android:allowBackup` 未显式关闭（默认 true），系统备份**可能**带回一份
///   —— 所以宁可说"可能留副本"，也不能写"卸载即清空"；
/// - 导出/备份是明文文件，分享出去就脱离 App 保护；
/// - 清单里没有 `INTERNET` 权限，这是"不联网"的硬证据。
///
/// **改其中任何一条实现，都要回来改这里。** 文案和实现对不上，比不写更糟。
class StorageNote extends StatelessWidget {
  const StorageNote({super.key});

  static const _lines = <String>[
    '只存在这台手机的应用私有目录里：一个 SQLite 数据库，外加几份自动快照。不经过任何服务器。',
    '没有账号，也就没有云端同步。换机只能先导出备份、再在新机上导入。',
    '卸载会删掉本机数据；但安卓的系统备份可能给你留一份副本。换机或重装前，先「导出账单」存到电脑。',
    '导出的 Excel / 备份文件一旦通过微信或网盘发出去，就不再受这个 App 保护 —— 里面有备注、对象、名称这些你手写的内容。',
    'App 没有申请联网权限，系统设置里能查到。',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _lines.length; i++) ...[
          if (i > 0) const SizedBox(height: S.sm),
          Text(
            _lines[i],
            style: T.body2.copyWith(color: C.ink2, height: 1.5),
          ),
        ],
      ],
    );
  }
}
