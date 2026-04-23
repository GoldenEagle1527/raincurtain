import 'package:flutter/material.dart';

/// 主题色配置文件数据模型
class AppColorProfile {
  final String id;
  final String name;
  final Color seed;
  final IconData icon;

  const AppColorProfile({
    required this.id,
    required this.name,
    required this.seed,
    required this.icon,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is AppColorProfile &&
      other.id == id &&
      other.name == name &&
      other.seed == seed &&
      other.icon == icon;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      name.hashCode ^
      seed.hashCode ^
      icon.hashCode;
  }
}

/// 预设主题配置列表
const List<AppColorProfile> kBuiltinProfiles = [
  AppColorProfile(
    id: 'blue',
    name: '天蓝',
    seed: Color(0xFF1976D2),
    icon: Icons.water_drop,
  ),
  AppColorProfile(
    id: 'purple',
    name: '深紫',
    seed: Color(0xFF6750A4),
    icon: Icons.auto_awesome,
  ),
  AppColorProfile(
    id: 'green',
    name: '翠绿',
    seed: Color(0xFF2E7D32),
    icon: Icons.eco,
  ),
  AppColorProfile(
    id: 'orange',
    name: '珊瑚橙',
    seed: Color(0xFFE65100),
    icon: Icons.local_fire_department,
  ),
  AppColorProfile(
    id: 'rose',
    name: '玫瑰红',
    seed: Color(0xFFC2185B),
    icon: Icons.favorite,
  ),
  AppColorProfile(
    id: 'cyan',
    name: '青金石',
    seed: Color(0xFF006064),
    icon: Icons.diamond,
  ),
];
