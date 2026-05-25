// 从网络磁盘拉取 skills 到本地
// 使用方式: node pull_skills.js

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const SOURCE = path.join("S:", "AI组", "雨幕", "skills");
const DEST = path.join("H:", "Projects", "raincurtain", ".kilo", "skills");
const NET_ROOT = path.join("S:", "AI组", "雨幕");

console.log("========================================");
console.log("  从网络磁盘拉取 Skills 到本地");
console.log("========================================\n");
console.log("源(网络):", SOURCE);
console.log("目标(本地):", DEST, "\n");

if (!fs.existsSync(NET_ROOT)) {
  console.error("[错误] 网络磁盘不可访问:", NET_ROOT);
  console.error("       请确认 S:\\ 已连接，并能访问 AI组\\雨幕 目录");
  process.exit(1);
}

if (!fs.existsSync(SOURCE)) {
  console.error("[错误] 网络磁盘上的 skills 目录不存在:", SOURCE);
  process.exit(1);
}

// 确保目标父目录存在
const destParent = path.dirname(DEST);
if (!fs.existsSync(destParent)) {
  fs.mkdirSync(destParent, { recursive: true });
}

console.log("正在同步...\n");

try {
  execSync(
    `robocopy "${SOURCE}" "${DEST}" /MIR /NJH /NP /NDL /NFL`,
    { encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] }
  );
} catch (e) {
  // robocopy 返回值 0-7 都算正常 (0-3 成功, 4-7 有警告但完成)
  if (e.status > 7) {
    console.error("[错误] 同步失败 (robocopy code:", e.status + ")");
    if (e.stdout) console.log(e.stdout.toString());
    if (e.stderr) console.error(e.stderr.toString());
    process.exit(1);
  }
}

// 列出同步后的文件
function listFiles(dir, prefix = "") {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      console.log(`  ${prefix}${entry.name}/`);
      listFiles(fullPath, prefix + "  ");
    } else {
      const size = fs.statSync(fullPath).size;
      console.log(`  ${prefix}${entry.name}  (${size} bytes)`);
    }
  }
}

console.log("[完成] 已拉取到本地:\n");
listFiles(DEST);
