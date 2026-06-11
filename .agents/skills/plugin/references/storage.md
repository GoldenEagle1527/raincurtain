# 结构化存储 API 参考

插件的存储表结构需在 `manifest.yml` 的 `storage` 字段中声明。

插件通过 `RainCurtain.storage.sql()` 对 manifest 中声明的表执行 SQL 操作（包括查询与更新）。每个表自动包含 `_id` 自增主键。

```javascript
// 原生 SQL 查询与更新
await RainCurtain.storage.sql(sqlString, params)
// sqlString: SQL 语句，表名使用 manifest 中声明的逻辑名（系统自动改写为物理隔离表名）
// params: 参数化绑定数组，对应 SQL 中的 ? 占位符
// SELECT 返回: [{ col: val, ... }, ...]  
// DML (INSERT/UPDATE/DELETE) 返回: { changes: N }
// 错误返回: { error: '错误信息' }
```

## manifest.yml 中的表声明

```yaml
storage:
  - name: "records"         # 表名（插件内唯一）
    columns:
      - name: "item"
        type: "text"        # 支持: text, integer, real, boolean
      - name: "amount"
        type: "real"
      - name: "created_at"
        type: "text"
```

支持的列类型：

| 类型 | SQLite | JS 值 | 说明 |
|------|--------|-------|------|
| `text` | TEXT | string | 字符串 |
| `integer` | INTEGER | number | 整数 |
| `real` | REAL | number | 浮点数 |
| `boolean` | INTEGER (0/1) | boolean | 布尔值，JS 侧自动转换 |

## 使用示例

### 1. 插入数据
```javascript
// 插入单条记录
const result = await RainCurtain.storage.sql(
  'INSERT INTO records (item, amount, created_at) VALUES (?, ?, ?)',
  ['午饭', 18.5, new Date().toISOString()]
);
// result: { changes: 1 }
```

### 2. 查询数据
```javascript
// 带条件和排序的查询
const rows = await RainCurtain.storage.sql(
  'SELECT * FROM records WHERE amount > ? ORDER BY created_at DESC LIMIT 20',
  [10]
);
// rows: [{ _id: 1, item: '午饭', amount: 18.5, created_at: '...' }]
```

### 3. 更新数据
```javascript
// 更新记录
const result = await RainCurtain.storage.sql(
  'UPDATE records SET amount = ? WHERE _id = ?',
  [20.0, 1]
);
// result: { changes: 1 }
```

### 4. 删除数据
```javascript
// 删除记录
const result = await RainCurtain.storage.sql(
  'DELETE FROM records WHERE _id = ?',
  [1]
);
// result: { changes: 1 }
```

### 5. 计数与清空表
```javascript
// 获取总数
const stats = await RainCurtain.storage.sql(
  'SELECT COUNT(*) as count FROM records',
  []
);
const total = stats[0].count;

// 清空表
await RainCurtain.storage.sql(
  'DELETE FROM records',
  []
);
```

## 存储特点

- 每个插件独立的结构化表，按列存储
- 支持 text / integer / real / boolean 四种列类型
- boolean 列在 JS 层与 SQLite 存储层（0/1）之间自动转换（true/false ↔ 0/1）
- 每个表自动包含 `_id` 自增主键
- 表结构由 manifest.yml 声明，安装时自动建表
- 卸载插件时自动清理所有表

## 表结构变更行为

插件更新版本时，如果 `storage` 中的表结构发生变化，系统会尝试兼容迁移以保留用户数据：

| 变更类型 | 处理方式 | 用户数据 |
|---|---|---|
| **新增列** | 自动 `ALTER TABLE ADD COLUMN` | 已有数据保留，新列值为 `null` |
| **删除列** | 不做处理，旧列保留在表中 | 已有数据保留，旧列对 API 不可见 |
| **修改列类型** | 删除并重建整个表 | **数据丢失** |

简单来说：只要不改变已有列的类型，用户数据就不会丢失。如果需要变更列类型，应当通知用户数据会被清除。

## SQL 执行注意事项

### 表名自动改写
SQL 中直接使用 manifest 中声明的**逻辑表名**（如 `records`），系统会自动将其改写为插件隔离的物理表名。无需关心实际的表名前缀。

### 参数化绑定
**必须使用参数化绑定**（`?` 占位符 + params 数组），防止 SQL 注入。

### 错误处理
```javascript
const result = await RainCurtain.storage.sql('INVALID SQL', []);
if (result && result.error) {
  console.error('SQL 执行失败:', result.error);
}
```

## 专属文件存储 (personalStorage)

为满足插件往本地写入各种非结构化文件（如配置文件、临时生成的图片、导出的文本等）的需求，雨幕提供了 `RainCurtain.personalStorage` 接口。

### 特点
- **插件强隔离**：系统会自动为每个插件分配专属物理沙箱文件夹，目录位于 `<ApplicationSupportDirectory>/RainCurtainPersonalStorage/<pluginId>`。
- **安全路径校验**：所有路径操作均会在 Dart 原生侧规范化后，强制检查其是否处于该插件的专属沙箱文件夹中，任何利用 `..` 等进行的路径遍历越界操作均会被直接拒绝并抛出异常。
- **物理自动清理**：当用户卸载插件或清空插件数据时，该插件的专属物理文件存储目录将被一并物理删除。

### API 列表及调用示例

#### 1. 写入文本文件 (`writeText`)
```javascript
// 写入文本或 JSON 内容（父目录不存在时会自动创建）
const result = await RainCurtain.personalStorage.writeText("configs/user_config.json", JSON.stringify(configData));
// 返回: { success: true } 或 { success: false, error: "错误信息" }
```

#### 2. 写入二进制文件 (`writeBinary`)
```javascript
// 写入 Base64 编码 of 二进制数据（常用于图片、音频等流式或大文件缓存）
const base64Data = "iVBORw0KGgoAAAANSUhEUgAA..."; // Base64 编码的 PNG
const result = await RainCurtain.personalStorage.writeBinary("assets/logo.png", base64Data);
// 返回: { success: true } 或 { success: false, error: "错误信息" }
```

#### 3. 读取文本文件 (`readText`)
```javascript
const text = await RainCurtain.personalStorage.readText("configs/user_config.json");
// 返回: string (文件内容)。如果文件不存在或读取失败，则返回 null
```

#### 4. 读取二进制文件 (`readBinary`)
```javascript
const base64 = await RainCurtain.personalStorage.readBinary("assets/logo.png");
// 返回: Base64 编码的字符串。如果文件不存在，则返回 null
```

#### 5. 检查文件或目录是否存在 (`exists`)
```javascript
const isExist = await RainCurtain.personalStorage.exists("configs/user_config.json");
// 返回: boolean (true 或 false)
```

#### 6. 列出目录内容 (`list`)
```javascript
const entries = await RainCurtain.personalStorage.list("configs");
// 返回: [{ name: "user_config.json", kind: "file", path: "configs/user_config.json" }, ...]
// 其中 path 是相对于专属存储根目录的相对路径。
```

#### 7. 删除文件或目录 (`delete`)
```javascript
const result = await RainCurtain.personalStorage.delete("configs");
// 会递归删除整个 "configs" 文件夹及其包含的所有内容
// 返回: { success: true } 或 { success: false, error: "错误信息" }
```
