# Phase 3 · Plugins 编排与 Marketplace

**状态**：✅ 完成（扫描 / 启用开关 / 跨模块跳转 / 自动更新检测均已上线）
**时间窗**：2026-04-18
**Git 范围**：`66b6ee2` → `c46ebee`
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

## 交付内容

### 基础设施

- `Features/Plugins/PluginModels.swift` + `PluginManifestParser.swift` —— plugin.json / marketplace.json 类型化 + 解析；`PluginManifestTests` 5 个测试
- `Features/Plugins/PluginScanner.swift` —— 扫 `~/.claude/plugins/cache/<marketplace>/<plugin>/`，按最新 mtime 去重同名插件
- `Features/Plugins/PluginsStore.swift` —— 已安装插件 list / 启用开关 / diff 落盘
- `Features/Plugins/MarketplacesStore.swift` + `MarketplaceModels.swift` + `MarketplacesStoreTests` 5 个测试 —— marketplace 源管理与插件清单聚合

### UI

- `Features/Plugins/PluginsRoot.swift`
- `Features/Plugins/PluginsListView.swift` —— 已安装插件列表 + 启用 toggle + 更新徽章
- `Features/Plugins/PluginDetailView.swift` —— manifest + 贡献资源清单 + 启用 / 卸载 / 重新扫描

### 跨模块改动（✅ 全部落地）

- Phase 1 的 Prompts / Skills / Subagents 列表项加 "来源" 徽章（Global / Project / Plugin: <name>）
- Phase 2 的 MCP 同样加来源徽章；plugin-declared server 自动合并进 MCP 列表
- 点击来源徽章 → `Navigator.focus(plugin:)` → 跳转到 Plugins 模块聚焦该插件
- 反向跳转：Plugins 详情页里列出贡献的 skills / commands / agents / mcpServers，点击 → 跳到对应模块的该资源

### 自动更新（✅ `c46ebee`）

- `GitUpdateChecker`（+ 4 个单测）— 定期 `git ls-remote` 比较 marketplace 源的最新 commit 与本地 cache
- Plugins 详情页显示 "Update available" 徽章；marketplace 级别可选 "auto-update" toggle
- 更新走重新 clone → swap → 再通过 diff 预览落盘

## 里程碑

| # | 任务 | Commit | 状态 |
|---|---|---|---|
| P3-1 | Manifest 解析器（plugin.json / marketplace.json）+ 测试 | `66b6ee2` | ✅ |
| P3-2 | PluginsStore（扫描 + 启用开关） | `cebfae9` | ✅ |
| P3-3 | Plugins UI + 详情视图（enable toggle + diff save） | `c8f31a0` | ✅ |
| P3-4 | wire Hooks + Plugins routes end-to-end | `665f994` | ✅ |
| P3-5 | 跨模块跳转（Prompts / Skills / Subagents） | `42d1c0c` | ✅ |
| P3-5a | 跨模块跳转扩展至 Agents + MCP | `fb5f4e4` | ✅ |
| P3-5b | MCP 加载 plugin-declared servers | `bb3992e` | ✅ |
| P3-6 | dedupe cache by latest-mtime per marketplace+plugin | `4863e02` | ✅ |
| P3-7 | 检测 + 应用更新 + marketplace auto-update toggle | `c46ebee` | ✅ |
| — | EffectGraphView（独立图视图） | — | ⏭ 未落地：已被"来源徽章 + 跨模块跳转"替代；复杂图视图需求未验证 |
| — | 安装流水线（gh clone / git pull） | — | ⏭ 未落地：v0.1.0 仅管理已安装的 plugin，安装仍靠 CC CLI；后续迭代补 |

## 风险 / 未决（已处理）

- **Marketplace 源格式**：决定只读 `~/.claude/plugins/cache/<marketplace>/` 下已由 Claude Code CLI 拉下来的清单，不自己做 clone；避免和 CC 的 plugin 管理机制冲突
- **插件能运行任意代码**：v0.1.0 完全不执行任何插件脚本，只做"展示 + 启用 toggle + diff"；安装 / 卸载仍由 CC CLI 负责
- **回滚精度**：所有 JSON 改动走 `SafeJSONStore` 的 diff sheet，用户能在落盘前看到 "本次启用这个 plugin 会加进哪几行" 的精确 diff
- **更新策略**：`GitUpdateChecker` 定期检查 marketplace 的 git 源 `HEAD`，有新 commit 就提示；auto-update 只更新本地 cache，不自动启用变更

## 后续工作（v0.2+）

Phase 3 结束后 9 个模块全部落地，v0.1.0 已发版。后续增强型方向：

- Plugin 安装流水线（直接在 app 内 clone / 装 marketplace + plugin）
- EffectGraphView：可视化 "本机所有 plugin × 所有资源" 的二分图
- 会话导出 / 分享
- 配置方案管理（多套 settings.json 切换，像 git branch）
- 插件发布工具链（作为插件作者的辅助工具）
- 多语言 UI（i18n）
- Markdown 编辑器升级为语法高亮
