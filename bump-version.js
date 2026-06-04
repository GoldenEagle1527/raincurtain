/**
 * 一键更新版本号 — 修改下面的 VERSION 后执行即可
 *
 * 用法: node bump-version.js
 */

const fs = require("fs");
const path = require("path");

// ★★★ 在这里修改版本号 ★★★
const VERSION = "1.2.1";
const BUILD = 1; // pubspec.yaml 的 build number (+N)

// ========================================

const root = __dirname;

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
