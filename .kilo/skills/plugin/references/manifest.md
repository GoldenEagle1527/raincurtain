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
| `default` | 默认值（仅 inputs 有效，且必须提供）。当本地存储和变量池均无值时，`storage.get(key)` 自动回退到此默认值 |
| `schema` | 结构定义（仅 `object` 类型必需）。基础 JSON Schema 子集，支持 `properties`（属性名 → `{type, description}`）和 `required`（必需属性列表） |
| `items` | 元素类型定义（仅 `array` 类型必需）。包含 `type` 字段，若元素为 `object` 则递归定义 `properties`/`required`，若元素为 `array` 则递归定义 `items` |

类型嵌套最大深度为 5 层。

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
```
