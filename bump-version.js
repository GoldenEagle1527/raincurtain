/**
 * 一键更新版本号 — 修改下面的 VERSION 后执行即可
 *
 * 用法: node bump-version.js
 */

const fs = require("fs");
const path = require("path");

const root = __dirname;

// 自动获取 pubspec.yaml 中当前的 build 号并自增
let currentBuild = 1;
try {
  const pubspecPath = path.join(root, "pubspec.yaml");
  if (fs.existsSync(pubspecPath)) {
    const pubspecText = fs.readFileSync(pubspecPath, "utf-8");
    const match = pubspecText.match(/^version:\s*\S+\+(\d+)$/m);
    if (match) {
      currentBuild = parseInt(match[1], 10);
    }
  }
} catch (e) {
  console.log("  [提示] 读取当前 build 号失败，将使用默认值 1");
}

// ★★★ 在这里修改版本号 ★★★
const VERSION = "1.3.5";
const BUILD = currentBuild + 1; // 自动在当前版本基础上自增

// ========================================

function patchFile(relPath, replacements) {
  const filePath = path.join(root, relPath);
  if (!fs.existsSync(filePath)) {
    console.log(`  [跳过] ${relPath} (不存在)`);
    return;
  }
  const buf = fs.readFileSync(filePath);
  let text = buf.toString("utf-8");
  let changed = false;
  for (const [regex, replacement] of replacements) {
    const newText = text.replace(regex, replacement);
    if (newText !== text) {
      text = newText;
      changed = true;
    }
  }
  if (changed) {
    fs.writeFileSync(filePath, Buffer.from(text, "utf-8"));
    console.log(`  [已更新] ${relPath}`);
  } else {
    console.log(`  [无变化] ${relPath}`);
  }
}

const V = VERSION;
const parts = V.split(".");

console.log(`目标版本: ${V}+${BUILD}\n`);

patchFile("pubspec.yaml", [[/^(version:\s*)\S+$/m, `$1${V}+${BUILD}`]]);

patchFile("installer.iss", [
  [/(#define\s+MyAppVersion\s+")\S+(")/, `$1${V}$2`],
]);

patchFile("windows/runner/Runner.rc", [
  [
    /(#define VERSION_AS_NUMBER\s+)\d+,\d+,\d+,\d+/,
    `$1${parts[0]},${parts[1]},${parts[2]},0`,
  ],
  [/(#define VERSION_AS_STRING\s+")\d[\d.]+(")/, `$1${V}$2`],
]);

patchFile("tools/electron-app/package.json", [
  [/("version"\s*:\s*")\S+(")/, `$1${V}$2`],
]);

patchFile("lib/plugin_api_server.dart", [
  [/(static const String kAppVersion = ')\S+(';)/, `$1${V}+${BUILD}$2`],
]);

console.log("\n完成!");
