# RainCurtain 首个正式版发布前隐性 Bug 与隐患深度分析报告

在对 `RainCurtain` (雨幕插件系统) 的核心代码进行深度审阅和静态分析后，我们发现并梳理了以下 **1 个潜在的隐性 Bug 和体验隐患**。这些问题主要集中在插件安装流程等关键区域，直接关系到首个正式版的发布质量和稳定性。

---

## 一、 性能与体验瓶颈 (Low Risk / UX Impact)

### 4. 插件解压重命名 (rename) 时序问题导致安装失败产生"残存垃圾插件"
- **定位文件**: [plugin_manager.dart](file:///h:/Projects/raincurtain/lib/models/plugin_manager.dart#L298-L318)
- **隐患分析**:
  在 `installPluginFromZip` 方法中，代码在解压完成后直接将临时目录重命名移入了沙箱目录 `tempDir.rename(pluginDir.path)`，之后才去进行 `_findEntryPath` 查询、清单读取以及注册数据库等步骤：
  ```dart
  await tempDir.rename(pluginDir.path);
  final entryPath = await _findEntryPath(pluginDir, pluginId); // 可能会抛出异常
  ...
  await _savePlugins(); // 数据库交互，可能出现超时或失败
  ```
  如果在执行 `rename` 之后但在数据库保存结束前发生了任何异常（例如未能在目录里找到 `index.html` 导致 `_findEntryPath` 抛错），代码会抛出异常退出。此时沙箱中已经生成了物理插件文件夹，但该文件夹没有被注册进数据库。
  当下次应用重新启动执行 `reloadPlugins()` 时，`_scanAndRegisterNewPlugins` 会扫描并读取这个残缺的半成品插件目录，由于入口文件缺失或其他异常，将导致应用报错或引发后续异常。
- **优化建议**:
  应当先在 `tempDir` 临时工作区中执行完所有的校验和配置工作（例如查找入口文件、读取 Manifest 等），一切准备妥当后，在 `try` 块的最后再执行 `await tempDir.rename(pluginDir.path)`，保证目录创建和数据库记录的强一致性。
