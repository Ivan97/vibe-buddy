# Phase 3 · Plugins 编排与 Marketplace

**状态**：📋 计划中
**预计工作量**：约 1 周
**依赖**：Phase 1（md+frontmatter 操作 skills/commands/agents）、Phase 2（JSON 编辑 mcpServers/hooks/settings）

## 目标

Plugins 是 Claude Code 的"打包扩展"——一个插件可以同时贡献 skills / commands / agents / mcpServers / hooks，装上后这些内容分散写进 `~/.claude/` 下多个文件。VibeBuddy 的 Phase 3 要让用户能：

1. **浏览** 已安装的插件 + 它们的 marketplace
2. **安装 / 卸载 / 更新** 插件
3. **看清影响面**：某个插件具体在本机动了哪些 skill / command / agent / mcp / hook

这是唯一会跨前三个 phase 的模块，实现起来是"读写各模块 store + 叠一层元数据解析"。

## 技术方案（计划）

### 数据源

**Plugin 清单**

- `~/.claude/plugins/` 下每个子目录是一个安装点
- 每个插件有自己的 `.claude-plugin/plugin.json`，里面声明 `name`, `version`, `description`, 提供的 `skills / commands / agents / mcpServers / hooks`
- Marketplace 元数据：`.claude-plugin/marketplace.json`，列出可选插件清单

**安装位置**

观察到的路径：`~/.claude/plugins/cache/<plugin-slug>/...`（Phase 1 已经在 Skills 的 plugin-provided section 见过）

### 模块组成

**PluginStore**

- 扫描 `~/.claude/plugins/` 子目录，解析 plugin.json / marketplace.json
- 每个 plugin → `InstalledPlugin` struct，包含：安装路径、version、manifest、贡献的资源列表
- 反向索引：每个 skill/command/agent/mcp/hook 到它来自哪个 plugin（供 Phase 1/2 的列表做 "来源" 标签）

**MarketplaceService**

- 读 marketplace.json 列表（来源可能是 git URL / 本地目录 / Anthropic 官方 registry）
- 缓存策略：本地磁盘缓存 + 按需刷新
- 不自动拉取：手动点击 "Refresh marketplaces" 才 fetch

**InstallerService**

- 安装 = git clone / 下载 tarball 到 `plugins/cache/<slug>/`，执行插件的 "install" 动作（如果声明了）
- 卸载 = 删除目录 + 清理它曾经写入的文件（依赖 manifest 记录的贡献清单）
- 更新 = git pull / 重下载，然后 diff 比较哪些资源发生变化
- 所有动作都通过 Phase 1/2 的 SafeTextWriter / SafeJSONStore，不直接 mv/rm

**EffectGraphView**

- 对单个插件渲染 "这个插件写了/修改了哪些本地文件" 的图
- 左列：插件 → skills, commands, agents, mcpServers, hooks 的资源节点
- 右列：资源 → 落盘位置（`~/.claude/skills/<name>`, `settings.json` 的某 key 等）
- 点击资源 → 跳到对应模块视图聚焦那一条

### UI 结构

```
Plugins 路由
├── Installed tab
│   ├── 已安装列表（version / enabled toggle / update available 徽章）
│   └── 选中 → 右侧详情：manifest + EffectGraph + Update / Uninstall
├── Marketplace tab
│   ├── marketplaces 列表（可添加 / 移除 marketplace 源）
│   └── 选中 marketplace → 可安装插件列表
└── Activity tab（可选）
    └── 最近的安装/卸载/更新历史
```

### 安装安全

- 插件安装本质是 "执行任意代码" + "写配置文件"。VibeBuddy 在执行前要：
  - 展示 manifest 里声明的**所有**改动（要装的 skill 名、要注入的 mcp server、要加的 hook command 等）
  - 展示 diff 预览（复用 Phase 2 的 diff 流水线）
  - 强确认（"这会修改 3 个文件，点下方按钮确认"）
- 卸载时同理：展示要删的所有文件和要回滚的所有 JSON key
- 所有可逆操作通过 `.bak` 保留一次回滚能力

## 交付内容（计划）

### 基础设施

- `Features/Plugins/PluginStore.swift`
- `Features/Plugins/MarketplaceService.swift`
- `Features/Plugins/InstallerService.swift`
- `Features/Plugins/ManifestParser.swift`（plugin.json / marketplace.json）

### UI

- `Features/Plugins/PluginsRoot.swift`
- `Features/Plugins/InstalledListView.swift`
- `Features/Plugins/MarketplaceListView.swift`
- `Features/Plugins/EffectGraphView.swift`
- `Features/Plugins/PluginDetailView.swift`

### 跨模块改动

- Phase 1 的三个模块（Prompts / Skills / Subagents）在列表项上加 "来源" 徽章（Global / Project / Plugin: <name>）
- Phase 2 的 MCP / Hooks 同样加来源徽章
- 点击来源徽章 → 跳转到 Plugins 模块聚焦该插件

## 里程碑（计划草案）

| # | 任务 | 预估 | 状态 |
|---|---|---|---|
| P3-1 | Manifest 解析器（plugin.json / marketplace.json）+ 测试 | 1 天 | 📋 |
| P3-2 | PluginStore（扫描 + 反向索引） | 1 天 | 📋 |
| P3-3 | Installed tab + 详情视图 | 1-2 天 | 📋 |
| P3-4 | Marketplace tab + 安装流水线 | 2 天 | 📋 |
| P3-5 | EffectGraphView | 1-2 天 | 📋 |
| P3-6 | 各模块列表项"来源"徽章 + 跳转 | 1 天 | 📋 |
| P3-7 | 卸载 / 更新流水线 | 2 天 | 📋 |

## 风险 / 未决

- **Marketplace 源格式**：Anthropic 官方是否有正式 registry？目前市面上多是 git 仓库直接 clone。Phase 3 开工前需要把当前主流做法盘一遍，决定支持几种源
- **插件能运行任意代码**：安装流程是否允许执行 `postinstall` 脚本？倾向于 "不允许，只做文件拷贝 + JSON 合并"，脚本执行改由用户手动触发（避免 supply chain 风险）
- **回滚精度**：JSON 合并能精准回滚（记录具体新增的 key），但如果插件注入的内容被用户又手工改过，怎么回滚？需要 diff 取交集 / 只删没被用户改过的部分
- **更新策略**：plugins 有没有 semver 约束？`plugin.json` 里能不能声明最低 VibeBuddy 版本？

## 对后续的影响

Phase 3 结束后，8 个模块全部落地。再之后的工作属于增强型：

- 会话导出 / 分享
- 配置方案管理（多套 settings.json 切换，像 git branch）
- 插件发布工具链（作为插件作者的辅助工具）
- 多语言 UI（i18n）
- App icon 设计、markdown 编辑器升级为语法高亮
