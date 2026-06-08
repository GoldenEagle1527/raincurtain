# 核心 API 参考

所有插件通过 `window.RainCurtain` API 进行数据操作和输入获取。

## 元数据

```javascript
RainCurtain.pluginId    // string - 插件 ID
```

## 输入获取

```javascript
const value = await RainCurtain.getInput(name)
// name: manifest.yml 中 inputs 定义的名称
// 返回: 输入值（可能来自外部动态提供，也可能是 manifest default）
//       未找到时返回 null
```

输入值的来源由宿主自动管理，插件不需要关心。

## 输出设置

```javascript
await RainCurtain.setOutput(name, value)
// name: manifest.yml 中 outputs 定义的名称
// value: 要输出的值
// 宿主自动持久化并可能将此值传递给其他组件
```

声明了 outputs 的插件，应在产出结果时调用此 API。
