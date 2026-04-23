import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import '../models/plugin_manager.dart';
import '../models/plugin_icon.dart';

/// 插件图标显示组件
class PluginIconWidget extends StatelessWidget {
  const PluginIconWidget({
    super.key,
    required this.plugin,
    this.size = 32.0,
  });

  final LocalPlugin plugin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = plugin.manifest.icon;

    return Container(
      width: size + 16,
      height: size + 16,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _getBackgroundColor(colorScheme, icon),
        borderRadius: BorderRadius.circular(8),
      ),
      child: switch (icon) {
        DefaultIcon() => _buildDefaultIcon(colorScheme),
        MaterialIcon(:final iconName, :final variant) =>
          _buildMaterialIcon(iconName, variant, colorScheme),
        PluginImageIcon(:final relativePath) =>
          _buildImageIcon(plugin, relativePath, colorScheme),
      },
    );
  }

  Color _getBackgroundColor(ColorScheme colorScheme, PluginIcon icon) {
    return switch (icon) {
      DefaultIcon() => colorScheme.primaryContainer,
      _ => colorScheme.primaryContainer.withValues(alpha: 0.3),
    };
  }

  Widget _buildDefaultIcon(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        Icons.apps,
        size: size,
        color: colorScheme.onPrimaryContainer,
      ),
    );
  }

  /// 构建 Material Icons 图标
  Widget _buildMaterialIcon(
    String iconName,
    MaterialIconVariant variant,
    ColorScheme colorScheme,
  ) {
    // 尝试从 Flutter Icons 类获取图标
    final iconData = _getFlutterIcon(iconName, variant);

    if (iconData != null) {
      return Center(
        child: Icon(
          iconData,
          size: size,
          color: colorScheme.onPrimaryContainer,
        ),
      );
    } else {
      // 回退方案: 显示图标名称的首字母或缩写
      return Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text(
            _getIconAbbreviation(iconName),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size * 0.5,
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
  }

  /// 获取图标名称的缩写
  String _getIconAbbreviation(String iconName) {
    final parts = iconName.split('_');
    if (parts.length == 1) {
      return parts[0].substring(0, parts[0].length > 2 ? 2 : parts[0].length).toUpperCase();
    }
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  /// 从 Flutter Icons 类获取图标
  IconData? _getFlutterIcon(String name, MaterialIconVariant variant) {
    // 常用图标映射表
    final iconMap = <String, IconData>{
      'home': Icons.home,
      'settings': Icons.settings,
      'search': Icons.search,
      'favorite': Icons.favorite,
      'star': Icons.star,
      'account_circle': Icons.account_circle,
      'add': Icons.add,
      'delete': Icons.delete,
      'edit': Icons.edit,
      'share': Icons.share,
      'download': Icons.download,
      'upload': Icons.upload,
      'close': Icons.close,
      'check': Icons.check,
      'arrow_back': Icons.arrow_back,
      'arrow_forward': Icons.arrow_forward,
      'menu': Icons.menu,
      'more_vert': Icons.more_vert,
      'info': Icons.info,
      'warning': Icons.warning,
      'error': Icons.error,
      'help': Icons.help,
      'notifications': Icons.notifications,
      'email': Icons.email,
      'phone': Icons.phone,
      'location_on': Icons.location_on,
      'calendar_today': Icons.calendar_today,
      'access_time': Icons.access_time,
      'lock': Icons.lock,
      'visibility': Icons.visibility,
      'visibility_off': Icons.visibility_off,
      'refresh': Icons.refresh,
      'sync': Icons.sync,
      'cloud': Icons.cloud,
      'folder': Icons.folder,
      'file_copy': Icons.file_copy,
      'image': Icons.image,
      'video_library': Icons.video_library,
      'music_note': Icons.music_note,
      'attach_file': Icons.attach_file,
      'link': Icons.link,
      'code': Icons.code,
      'bug_report': Icons.bug_report,
      'build': Icons.build,
      'extension': Icons.extension,
      'dashboard': Icons.dashboard,
      'analytics': Icons.analytics,
      'language': Icons.language,
      'public': Icons.public,
      'wifi': Icons.wifi,
      'bluetooth': Icons.bluetooth,
      'battery_full': Icons.battery_full,
      'brightness_high': Icons.brightness_high,
      'volume_up': Icons.volume_up,
      'mic': Icons.mic,
      'camera': Icons.camera,
      'photo_camera': Icons.photo_camera,
      'videocam': Icons.videocam,
      'play_arrow': Icons.play_arrow,
      'pause': Icons.pause,
      'stop': Icons.stop,
      'skip_next': Icons.skip_next,
      'skip_previous': Icons.skip_previous,
      'fast_forward': Icons.fast_forward,
      'fast_rewind': Icons.fast_rewind,
      'shopping_cart': Icons.shopping_cart,
      'payment': Icons.payment,
      'credit_card': Icons.credit_card,
      'local_offer': Icons.local_offer,
      'person': Icons.person,
      'people': Icons.people,
      'group': Icons.group,
      'chat': Icons.chat,
      'message': Icons.message,
      'send': Icons.send,
      'thumb_up': Icons.thumb_up,
      'thumb_down': Icons.thumb_down,
      'bookmark': Icons.bookmark,
      'flag': Icons.flag,
      'print': Icons.print,
      'save': Icons.save,
      'undo': Icons.undo,
      'redo': Icons.redo,
      'content_copy': Icons.content_copy,
      'content_cut': Icons.content_cut,
      'content_paste': Icons.content_paste,
    };

    // 根据变体选择图标
    if (variant == MaterialIconVariant.outlined) {
      final outlinedMap = <String, IconData>{
        'home': Icons.home_outlined,
        'settings': Icons.settings_outlined,
        'search': Icons.search_outlined,
        'favorite': Icons.favorite_outline,
        'star': Icons.star_outline,
        'account_circle': Icons.account_circle_outlined,
        'delete': Icons.delete_outline,
        'edit': Icons.edit_outlined,
        'notifications': Icons.notifications_outlined,
        'email': Icons.email_outlined,
        'folder': Icons.folder_outlined,
        'image': Icons.image_outlined,
        'bookmark': Icons.bookmark_outline,
        'info': Icons.info_outlined,
        'warning': Icons.warning_outlined,
        'error': Icons.error_outlined,
        'help': Icons.help_outline,
        'lock': Icons.lock_outlined,
        'cloud': Icons.cloud_outlined,
        'extension': Icons.extension_outlined,
        'dashboard': Icons.dashboard_outlined,
        'person': Icons.person_outlined,
        'chat': Icons.chat_outlined,
        'message': Icons.message_outlined,
        'flag': Icons.flag_outlined,
        'save': Icons.save_outlined,
      };
      return outlinedMap[name] ?? iconMap[name];
    } else if (variant == MaterialIconVariant.rounded) {
      final roundedMap = <String, IconData>{
        'home': Icons.home_rounded,
        'settings': Icons.settings_rounded,
        'search': Icons.search_rounded,
        'favorite': Icons.favorite_rounded,
        'star': Icons.star_rounded,
        'account_circle': Icons.account_circle_rounded,
        'delete': Icons.delete_rounded,
        'edit': Icons.edit_rounded,
        'add': Icons.add_rounded,
        'close': Icons.close_rounded,
        'check': Icons.check_rounded,
        'arrow_back': Icons.arrow_back_rounded,
        'arrow_forward': Icons.arrow_forward_rounded,
        'menu': Icons.menu_rounded,
        'more_vert': Icons.more_vert_rounded,
        'info': Icons.info_rounded,
        'warning': Icons.warning_rounded,
        'error': Icons.error_rounded,
        'help': Icons.help_rounded,
      };
      return roundedMap[name] ?? iconMap[name];
    } else if (variant == MaterialIconVariant.sharp) {
      final sharpMap = <String, IconData>{
        'home': Icons.home_sharp,
        'settings': Icons.settings_sharp,
        'search': Icons.search_sharp,
        'favorite': Icons.favorite_sharp,
        'star': Icons.star_sharp,
        'add': Icons.add_sharp,
        'delete': Icons.delete_sharp,
        'edit': Icons.edit_sharp,
        'close': Icons.close_sharp,
        'check': Icons.check_sharp,
      };
      return sharpMap[name] ?? iconMap[name];
    }

    // 默认返回 filled 样式
    return iconMap[name];
  }

  Widget _buildImageIcon(
    LocalPlugin plugin,
    String relativePath,
    ColorScheme colorScheme,
  ) {
    final absolutePath = p.join(plugin.entryPath, relativePath);
    final file = File(absolutePath);
    final lowerPath = relativePath.toLowerCase();
    final isSvg = lowerPath.endsWith('.svg');

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: size,
          height: size,
          child: isSvg
              ? _buildSvgIcon(file, colorScheme)
              : Image.file(
                  file,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  errorBuilder: (_, _, _) => _buildDefaultIcon(colorScheme),
                ),
        ),
      ),
    );
  }

  /// SVG 图标渲染
  Widget _buildSvgIcon(File file, ColorScheme colorScheme) {
    return SvgPicture.file(
      file,
      width: size,
      height: size,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      placeholderBuilder: (_) => _buildDefaultIcon(colorScheme),
    );
  }
}
