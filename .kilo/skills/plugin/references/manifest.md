# manifest.yml 完整格式参考

## 基本结构

```yaml
name: "插件名称"
description: "插件描述"
version: "1.0.0"          # 语义化版本 X.Y.Z
author: "作者名"
icon: "material:extension" # Material Icons 或图片路径

inputs:                     # 必需：声明输入接口（无接口时写空列表 []）
  - name: "input_name"
    type: "string"
    description: "描述"
    default: "默认值"       # 必需：所有 input 都须提供默认值

outputs:                    # 必需：声明输出接口（无接口时写空列表 []）
  - name: "output_name"
    type: "object"
    description: "描述"

storage:                    # 可选：声明插件的存储表结构
  - name: "records"         # 表名（在插件内唯一）
    columns:
      - name: "item"
        type: "text"        # 支持: text, integer, real, boolean
      - name: "amount"
        type: "real"
```

## icon 字段

- Material Icons: `material:home` / `material:favorite:outlined`
- 图片文件: `./icon.png` / `./assets/logo.svg`

## 字段说明

| 字段 | 说明 |
|------|------|
| `inputs` / `outputs` | 必需字段，声明插件对外的数据接口，供宿主配置数据流。无接口时写空列表 `[]` |
| `name` | 接口名称，必须唯一，仅支持字母、数字、下划线 |
| `type` | 数据类型：`string`, `number`, `boolean`, `object`, `array` |
| `description` | 接口说明，用于 UI 显示 |
| `required` | 是否必需（仅 inputs 有效），默认 false |
| `default` | 默认值（仅 inputs 有效，且必须提供）。`getInput(name)` 在无外部提供值时返回此默认值 |
| `schema` | 结构定义（仅 `object` 类型必需）。基础 JSON Schema 子集，支持 `properties`（属性名 → `{type, description}`）和 `required`（必需属性列表） |
| `items` | 元素类型定义（仅 `array` 类型必需）。包含 `type` 字段，若元素为 `object` 则递归定义 `properties`/`required`，若元素为 `array` 则递归定义 `items` |

类型嵌套最大深度为 5 层。

## storage 字段

`storage` 是可选字段，用于声明插件的持久化存储表结构。每个插件可以定义多个表，每个表有独立的列定义。

### 结构

```yaml
storage:
  - name: "table_name"      # 表名（插件内唯一），仅允许字母、数字、下划线
    columns:
      - name: "column_name"  # 列名，仅允许字母、数字、下划线，不能为 "_id"
        type: "text"         # 列类型
```

### 支持的列类型

| manifest 类型 | SQLite 类型 | JS 值类型 | 说明 |
|---|---|---|---|
| `text` | TEXT | string | 字符串 |
| `integer` | INTEGER | number | 整数 |
| `real` | REAL | number | 浮点数 |
| `boolean` | INTEGER (0/1) | boolean (true/false) | 布尔值 |

### 自动列

每个表自动添加 `_id INTEGER PRIMARY KEY AUTOINCREMENT` 主键列，不需要在 manifest 中声明。

### 表结构变更规则

插件版本更新时修改 `storage` 表结构，系统会自动处理迁移：

- **新增列** — 自动添加，已有数据保留，新列值为 `null`
- **删除列** — 旧列保留在数据库中但对 API 不可见，已有数据不受影响
- **修改列类型**（如 `text` → `integer`）— 表会被删除并重建，**已有数据丢失**

**最佳实践：** 避免修改已有列的类型。如果需要变更类型，建议新增一个不同名称的列，在插件代码中做数据迁移。

### JS API

声明了 `storage` 后，插件可以通过 `RainCurtain.storage` API 进行 CRUD 操作：

```javascript
// 插入数据（单行或多行）
const result = await RainCurtain.storage.insert('records', { item: '午饭', amount: 18 });
// result: { insertedCount: 1 }

const result2 = await RainCurtain.storage.insert('records', [
  { item: '午饭', amount: 18 },
  { item: '晚饭', amount: 25 }
]);
// result2: { insertedCount: 2 }

// 查询数据
const rows = await RainCurtain.storage.query('records', {
  where: { category: '餐饮' },   // 等值匹配
  orderBy: 'created_at DESC',     // 排序
  limit: 10,                      // 限制
  offset: 0                       // 偏移
});
// rows: [{ _id: 1, item: '午饭', amount: 18, ... }, ...]

// 更新数据
const result3 = await RainCurtain.storage.update('records', { amount: 20 }, { _id: 1 });
// result3: { updatedCount: 1 }

// 删除数据
const result4 = await RainCurtain.storage.delete('records', { _id: 1 });
// result4: { deletedCount: 1 }

// 计数
const n = await RainCurtain.storage.count('records', { category: '餐饮' });
// n: 5

// 清空表
await RainCurtain.storage.clear('records');
```

## 完整示例

```yaml
name: "数据处理器"
description: "处理和转换数据的插件"
version: "1.0.0"
author: "开发者"
icon: "material:data_object"

inputs:
  - name: "message"
    type: "string"
    description: "消息内容"
    default: "hello"

  - name: "count"
    type: "number"
    description: "计数"
    default: 0

  - name: "enabled"
    type: "boolean"
    description: "是否启用"
    default: true

  - name: "config"
    type: "object"
    description: "配置对象"
    default: { theme: "dark", fontSize: 14 }
    schema:
      properties:
        theme:
          type: string
          description: "主题"
        fontSize:
          type: number
          description: "字体大小"
      required:
        - theme

  - name: "tags"
    type: "array"
    description: "标签列表"
    default: ["tag1", "tag2"]
    items:
      type: string

  - name: "users"
    type: "array"
    description: "用户列表"
    default: []
    items:
      type: object
      properties:
        name:
          type: string
        age:
          type: number
      required:
        - name

outputs:
  - name: "result"
    type: "object"
    description: "处理结果"
    schema:
      properties:
        status:
          type: string
        data:
          type: object
          properties:
            id:
              type: number
            value:
              type: string
      required:
        - status

  - name: "logs"
    type: "array"
    description: "日志列表"
    items:
      type: string

storage:
  - name: "records"
    columns:
      - name: "item"
        type: "text"
      - name: "category"
        type: "text"
      - name: "amount"
        type: "real"
      - name: "note"
        type: "text"
      - name: "type"
        type: "text"
      - name: "created_at"
        type: "text"
```
