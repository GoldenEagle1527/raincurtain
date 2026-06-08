# 结构化存储 API 参考

插件的存储表结构需在 `manifest.yml` 的 `storage` 字段中声明。

插件通过 `RainCurtain.storage` 对 manifest 中声明的表执行 CRUD 操作。每个表自动包含 `_id` 自增主键。

```javascript
// 插入（单行或多行）
await RainCurtain.storage.insert(table, rows)
// rows: { col: val } 或 [{ col: val }, ...]
// 返回: { insertedCount: N }

// 查询
await RainCurtain.storage.query(table, options)
// options: { where: { col: val }, orderBy: 'col DESC', limit: 10, offset: 0 }
// 返回: [{ _id: 1, col: val, ... }, ...]

// 更新
await RainCurtain.storage.update(table, values, where)
// values: { col: newVal }
// where: { _id: 1 }  可选，为空则更新全部
// 返回: { updatedCount: N }

// 删除
await RainCurtain.storage.delete(table, where)
// where: { _id: 1 }  可选，为空则删除全部
// 返回: { deletedCount: N }

// 计数
await RainCurtain.storage.count(table, where)
// 返回: N

// 清空表
await RainCurtain.storage.clear(table)
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

```javascript
// 插入一条记录
const result = await RainCurtain.storage.insert('records', {
  item: '午饭',
  amount: 18.5,
  created_at: new Date().toISOString()
});
// result: { insertedCount: 1 }

// 批量插入
await RainCurtain.storage.insert('records', [
  { item: '午饭', amount: 18 },
  { item: '晚饭', amount: 25 }
]);

// 查询（带条件和排序）
const rows = await RainCurtain.storage.query('records', {
  where: { type: 'expense' },
  orderBy: 'created_at DESC',
  limit: 20
});

// 按 _id 更新
await RainCurtain.storage.update('records', { amount: 20 }, { _id: 1 });

// 按条件删除
await RainCurtain.storage.delete('records', { _id: 1 });

// 计数
const total = await RainCurtain.storage.count('records');
const expenses = await RainCurtain.storage.count('records', { type: 'expense' });

// 清空表
await RainCurtain.storage.clear('records');
```

## 初始化模式

```javascript
async function init() {
  // 查询已有数据
  const records = await RainCurtain.storage.query('records', {
    orderBy: 'created_at DESC',
    limit: 50
  });
  
  if (records.length > 0) {
    renderRecords(records);
  }
  
  // 统计
  const count = await RainCurtain.storage.count('records');
  updateStats(count);
}
```

## 查询限制

**`where` 参数仅支持等值匹配**（如 `{ type: 'expense' }`），不支持范围比较（`>`、`<`、`>=`、`<=`）、模糊匹配（`LIKE`）或逻辑组合（`OR`）。

需要范围或模糊查询时，应全量查询后在 JS 内存中筛选：

```javascript
// 错误：where 不支持范围查询
// await RainCurtain.storage.query('records', { where: { amount: { gt: 100 } } });

// 正确：全量查询后内存筛选
const all = await RainCurtain.storage.query('records', {
  orderBy: 'created_at DESC'
});
const filtered = all.filter(r => r.amount > 100);
```

## Upsert 模式

Storage API 不提供原生 upsert 操作，需手动实现"存在则更新，不存在则插入"：

```javascript
async function upsert(table, where, values) {
  const rows = await RainCurtain.storage.query(table, { where, limit: 1 });
  if (rows.length > 0) {
    await RainCurtain.storage.update(table, values, where);
  } else {
    await RainCurtain.storage.insert(table, { ...where, ...values });
  }
}

// 使用示例：保存设置项
await upsert('settings', { key: 'theme' }, { key: 'theme', value: 'dark' });
```

## 存储特点

- 每个插件独立的结构化表，按列存储
- 支持 text / integer / real / boolean 四种列类型
- boolean 列在 JS 层自动转换（true/false ↔ 0/1）
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
