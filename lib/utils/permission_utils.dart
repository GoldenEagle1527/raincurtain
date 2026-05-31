import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android 运行时权限工具类
///
/// 将 WebView 的 [PermissionResourceType] 映射为 Android 原生权限，
/// 在插件真正使用某功能时按需请求系统权限。
class PermissionUtils {
  PermissionUtils._();

  /// 根据 WebView 请求的资源类型，逐项请求对应的 Android 原生权限。
  /// 返回实际被授予的资源列表。
  ///
  /// 非 Android 平台直接返回全部资源（不做限制）。
  static Future<List<PermissionResourceType>> requestForWebViewResources(
    List<PermissionResourceType> resources,
  ) async {
    if (!Platform.isAndroid) {
      return resources;
    }

    final granted = <PermissionResourceType>[];

    for (final resource in resources) {
      final permissions = _mapResourceToPermissions(resource);

      if (permissions.isEmpty) {
        // 无对应原生权限的资源类型（如 PROTECTED_MEDIA_ID 等），直接放行
        granted.add(resource);
        continue;
      }

      // 请求所有映射到的权限
      final statuses = await permissions.request();
      final allGranted =
          statuses.values.every((status) => status.isGranted);

      if (allGranted) {
        granted.add(resource);
      } else {
        debugPrint(
          'Permission denied for WebView resource: $resource '
          '(statuses: $statuses)',
        );
      }
    }

    return granted;
  }

  /// 请求位置权限（供地理位置回调使用）。
  /// 返回是否成功获取权限。
  static Future<bool> requestLocationPermission() async {
    if (!Platform.isAndroid) return true;

    final status = await Permission.locationWhenInUse.request();
    if (status.isGranted) return true;

    debugPrint('Location permission denied: $status');
    return false;
  }

  /// 请求存储权限（供文件下载等场景使用）。
  /// Android 13+ (API 33) 使用 MediaStore 不需要额外存储权限，直接返回 true。
  /// Android 12 及以下需要 READ/WRITE_EXTERNAL_STORAGE。
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Android 13+ 不需要传统存储权限
    // permission_handler 会根据 SDK 版本自动处理
    final status = await Permission.storage.request();
    if (status.isGranted || status.isLimited) return true;

    // 如果是 permanentlyDenied，用户需要去系统设置中手动开启
    if (status.isPermanentlyDenied) {
      debugPrint(
        'Storage permission permanently denied. '
        'User needs to enable it in system settings.',
      );
    }

    return false;
  }

  /// 将 WebView [PermissionResourceType] 映射为需要请求的 Android [Permission] 列表
  static List<Permission> _mapResourceToPermissions(
    PermissionResourceType resource,
  ) {
    if (resource == PermissionResourceType.CAMERA) {
      return [Permission.camera];
    } else if (resource == PermissionResourceType.MICROPHONE) {
      return [Permission.microphone];
    } else if (resource == PermissionResourceType.CAMERA_AND_MICROPHONE) {
      return [Permission.camera, Permission.microphone];
    } else {
      // 其他类型（如 MIDI_SYSEX、PROTECTED_MEDIA_ID 等）无需额外原生权限
      return [];
    }
  }
}
