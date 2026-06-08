# 平台能力参考

## 文件系统访问

File System Access API（`showSaveFilePicker`、`showOpenFilePicker`、`showDirectoryPicker`）已由系统透明代理，直接使用标准浏览器 API 即可。两个平台（Windows / Android）行为一致，底层通过 Flutter 的 `file_picker` 包实现。

### 保存文件

```javascript
const handle = await window.showSaveFilePicker({
  suggestedName: 'data.json',
  types: [{
    description: 'JSON 文件',
    accept: { 'application/json': ['.json'] }
  }]
});
const writable = await handle.createWritable();
await writable.write(JSON.stringify(data, null, 2));
await writable.close();
```

### 打开文件

```javascript
// 选择单个文件
const [handle] = await window.showOpenFilePicker({
  types: [{
    description: '图片',
    accept: { 'image/*': ['.png', '.jpg', '.jpeg', '.gif', '.webp'] }
  }]
});
const file = await handle.getFile();
const text = await file.text();
// 或读取为 ArrayBuffer
const buffer = await file.arrayBuffer();

// 选择多个文件
const handles = await window.showOpenFilePicker({ multiple: true });
for (const h of handles) {
  const f = await h.getFile();
  console.log(f.name, f.size);
}
```

### 选择目录

```javascript
const dirHandle = await window.showDirectoryPicker();

// 遍历目录
for await (const [name, handle] of dirHandle.entries()) {
  console.log(name, handle.kind); // 'file' 或 'directory'
}

// 获取子文件
const fileHandle = await dirHandle.getFileHandle('config.json');
const file = await fileHandle.getFile();

// 创建子文件
const newFile = await dirHandle.getFileHandle('output.txt', { create: true });
const w = await newFile.createWritable();
await w.write('Hello');
await w.close();

// 创建子目录
const subDir = await dirHandle.getDirectoryHandle('subdir', { create: true });

// 删除条目
await dirHandle.removeEntry('temp.txt');
await dirHandle.removeEntry('old_dir', { recursive: true });
```

### 注意事项

- 用户取消选择器时，会抛出 `DOMException`（name = `'AbortError'`），需用 try/catch 捕获
- `FileSystemWritableFileStream.write()` 支持 `string`、`Blob`、`ArrayBuffer`、`TypedArray` 和 `WriteParams` 对象
- 所有文件内容通过 base64 在 JS↔Flutter 间传输，超大文件（>100MB）可能有性能影响
- `queryPermission()` 和 `requestPermission()` 始终返回 `'granted'`

---

## 宿主通信

插件已内置以下 polyfill，直接使用浏览器 API：

```javascript
// 通知 API（已 polyfill）
new Notification("标题", { body: "内容" });

// 剪贴板 API（已 polyfill）
await navigator.clipboard.writeText("文本");
const text = await navigator.clipboard.readText();

// 自定义宿主通信（高级用法）
window.flutter_inappwebview.callHandler("handlerName", data);
```

---

## 已放行的浏览器权限

以下高级权限无需用户授权即可直接调用：

- 摄像头 (`navigator.mediaDevices.getUserMedia()`)
- 麦克风
- 地理位置 (`navigator.geolocation.getCurrentPosition()`)
- 剪贴板 (`navigator.clipboard`)
- 通知 (`new Notification()`)
- 文件系统访问 (`window.showOpenFilePicker()` / `window.showSaveFilePicker()` / `window.showDirectoryPicker()`) — 已由系统透明代理，直接使用标准 API 即可，两个平台行为一致
- USB、串口、MIDI、传感器、字体枚举

---

## 屏幕方向控制

插件可以通过 `RainCurtain.orientation` API 控制屏幕方向。调用后 **Android 系统真正旋转屏幕**（状态栏、键盘、输入法等全部跟随），属于系统级旋转。此 API 仅在插件页面生效，插件页面关闭时自动恢复为自由旋转。Windows 平台调用无副作用。

### 切换为横屏

```javascript
// 系统级横屏：状态栏到侧边，键盘横向弹出
const result = await RainCurtain.orientation.lock('landscape');
// result = { success: true }
```

### 恢复竖屏

```javascript
// 锁定为竖屏
const result = await RainCurtain.orientation.lock('portrait');

// 或解锁为自由旋转（跟随系统自动旋转设置）
const result = await RainCurtain.orientation.unlock();
// result = { success: true }
```

### 查询当前状态

```javascript
const info = await RainCurtain.orientation.get();
// 横屏锁定时:
// info = { mode: 'landscape', locked: true }

// 未锁定时（默认）:
// info = { mode: 'portrait', locked: false }
```

### 错误处理

```javascript
const result = await RainCurtain.orientation.lock('invalid');
if (!result.success) {
  console.error(result.error);
  // "mode must be 'landscape' or 'portrait'"
}
```

### 完整示例：视频播放器横屏

```javascript
// 进入全屏播放时横屏
async function enterFullscreen() {
  await RainCurtain.orientation.lock('landscape');
  document.querySelector('.video-player').classList.add('fullscreen');
}

// 退出全屏时恢复
async function exitFullscreen() {
  await RainCurtain.orientation.unlock();
  document.querySelector('.video-player').classList.remove('fullscreen');
}
```

### 注意事项

- **系统级旋转**：通过 `SystemChrome.setPreferredOrientations` 实现，Android 系统真正切换屏幕方向，键盘、输入法、状态栏等全部跟随旋转
- **插件级生效**：方向锁定仅在当前插件页面有效，插件页面关闭（dispose）时自动恢复为自由旋转
- **Windows 兼容**：Windows 平台调用 API 返回 success 但无视觉效果（桌面端无旋转概念）
- **两种模式**：`'landscape'`（横屏，含左旋和右旋）和 `'portrait'`（竖屏，含正向和反向）
- **`unlock()` vs `lock('portrait')`**：`unlock()` 恢复为自由旋转（跟随系统自动旋转设置），`lock('portrait')` 强制锁定竖屏（禁止旋转到横屏）
