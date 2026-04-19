# Phase 2 · JSON 配置三件套（Statusline / MCP / Hooks / Settings）

**状态**：✅ 完成（四个 JSON 驱动模块全部上线，共享 `SafeJSONStore` 基础设施）
**时间窗**：2026-04-18
**Git 范围**：`0537071` → `d1bc90e`
**依赖**：Phase 1 的 `SafeTextWriter`、`AuthoringScope`、`LabeledRow` / `MultilineTextField` 等表单原子组件

## 目标

把 Claude Code 的 JSON 驱动配置全部纳入图形编辑：Statusline（`settings.json` 的 `statusLine` 字段）、MCP servers（`~/.claude.json` / settings 的 `mcpServers`）、Hooks（settings 的 `hooks` 字段），外加一个 **Settings** 模块做全量 schema-aware 编辑。四者共用一层"安全 JSON 写入"基础设施，各模块在顶层加自己的特色功能（live preview / plugin server 合并 / 事件分 tab / 全字段 diff）。

和 Phase 1 最大的不同：**写入风险更高**。这些 JSON 一旦写坏，正在跑的 Claude Code 会立刻受影响。因此本 phase 首要任务是把"写入安全层"做扎实，再让 UI 调用它。

## 技术方案

### 共享基础设施

**SafeJSONStore**（`Infrastructure/SafeJSONStore.swift`，7 个单测）

- 读：`~/.claude/settings.json` 和 `~/.claude.json`，用 `JSONSerialization` 解析，`JSONSerialization.WritingOptions.sortedKeys + prettyPrinted` 稳定输出
- 单字段更新：`update(path:)` 走路径表达式（`["hooks", "SessionStart"]`）只改目标 key，不重写无关字段
- 原子写：复用 `SafeTextWriter`，附带 `.bak`
- 写前 diff 预览：生成 "before / after" 的 JSON 字符串对比，弹 sheet 确认才落盘
- 写入失败时自动回滚 `.bak`

**SettingsCodec**（`Features/Settings/SettingsCodec.swift`，7 个单测）

- 全量 schema-aware 编解码：把 `settings.json` / `~/.claude.json` 里的已知字段落成强类型结构，未知字段放 `extras` 透传
- 覆盖字段：`model` / `env` / `statusLine` / `mcpServers` / `hooks` / `permissions` / `apiKeyHelper` / `includeCoAuthoredBy` 等
- 把 Statusline / MCP / Hooks / Settings 四个模块的读写统一到同一条 codec 链路

**AuthoringScope 覆盖**

- Statusline：只有 global（user settings）
- MCP：global（user settings）+ project（project settings）+ plugin-provided（只读）
- Hooks：global + project
- Settings：global（`~/.claude/settings.json`）+ `~/.claude.json`（运行时配置）

### 各模块特色功能

**Statusline**（`Features/Statusline/`，3 文件 ~495 行）

- 字段结构：`{ type: "command", command: "..." }`
- UI：shell 命令输入框 + 实时预览面板（`StatuslinePreview.swift`）
- 实时预览：app 内部用 `Process` 跑用户输入的命令，stdin 喂一段模拟的 Claude Code context（`session_id` / `cwd` / `model` / `workspace`），stdout 直接渲染到预览
- 未落地：常用模板库（`cwd` / `git branch` / `time` / `token usage` 等）—— 预览 + 手写覆盖了 90% 场景，模板库留给后续

**MCP servers**（`Features/MCP/`，7 文件 ~949 行）

- 字段结构：`mcpServers: { "<name>": { command, args, env, type, ... } }`
- UI：servers 列表 + 每个 server 的详细表单（type / command / args / env key-value）
- 三种 transport：stdio / sse / http
- Plugin-provided MCP server 独立 section 只读展示；来源徽章点击 → 跳转 Plugins 模块聚焦该插件
- 未落地：连通性测试（`Process` spawn + `initialize` JSON-RPC）和 MCP registry 浏览 —— 连通性测试存在沙箱与权限风险，v0.1.0 先保证编辑链路；registry 生态 2026 年上半年仍不统一，留到 v0.2.x 再追

**Hooks**（`Features/Hooks/`，7 文件 ~740 行）

- 字段结构：`hooks: { "SessionStart": [...], "UserPromptSubmit": [...], ... }`
- 事件类型：`PreToolUse` / `PostToolUse` / `UserPromptSubmit` / `SessionStart` / `Stop` / `SubagentStop` / `Notification` / `PreCompact` / `SessionEnd`
- UI：`EventSidebar` 按事件类型分组 + `EventEditorView` 每个 hook 一行 `{ matcher, hooks: [{ type, command, timeout }] }`
- `HooksCodec` 7 个单测覆盖新增 / 删除 / 嵌套数组的路径级更新
- 未落地：Matcher 可视化 & 运行日志回放（依赖 session jsonl 的 `attachment.hook_*` 反向索引）—— 需求验证后再做，避免过度设计

**Settings**（`Features/Settings/`，7 文件 ~1035 行）

- 第 9 个模块，`settings.json` + `~/.claude.json` 全量 schema-aware 编辑
- 已知字段有表单（`model` / `env` / `permissions` / `includeCoAuthoredBy` 等），未知字段放 `extras` 透传保留原顺序
- 两个目标文件切 tab 展示，保存共用 diff 预览 sheet
- `SettingsTarget.swift` 抽象"改哪个文件"；`SettingsStore.swift` 持有两份状态 + 独立 watcher

### 写入安全层的 UX

```
用户修改 → [显式 Save] → [diff 预览 sheet] → [确认] → 原子写 → 更新 store
                                ↓
                         [取消] → 回到 UI，不落盘
```

- 每次保存生成 `.bak`
- 如果目标文件外部变动（watcher 检测到），UI 显示 "外部已修改" 横幅，提供 "重载 / 强制覆盖" 选项
- 任何 schema 校验失败 → 红色表单提示，Save 按钮禁用

## 交付内容

### 基础设施

- `Infrastructure/SafeJSONStore.swift` + 7 个单测
- `Features/Authoring/DiffPreviewSheet.swift` —— 和 Phase 1 的 P1-9 合并到同一个组件，四个 JSON 模块共用

### 模块

- `Features/Statusline/` —— store + live preview（`Process` + 模拟 context）
- `Features/MCP/` —— store + list / editor + plugin server 合并 + 来源徽章
- `Features/Hooks/` —— store + event sidebar + per-event editor + codec 单测
- `Features/Settings/` —— 全量 schema-aware 编辑，覆盖 `settings.json` + `~/.claude.json`

## 里程碑

| # | 任务 | Commit | 状态 |
|---|---|---|---|
| P2-H1 | SafeJSONStore + 单测 | `0537071` | ✅ |
| P2-H2 | Hooks typed model + JSON codec | `b0912c8` | ✅ |
| P2-H3 | HooksStore + preview + commit + FSEvents | `395e681` | ✅ |
| P2-H4 | Hooks editor UI（event sidebar + per-event editor） | `27650e3` | ✅ |
| P2-S / P2-M | Statusline + MCP 端到端 | `c9d181e` | ✅ |
| P2-Plugin | MCP 加载 plugin-declared server + 跨模块跳转 | `bb3992e` | ✅ |
| P2-Settings | 第 9 个 Settings 模块：schema-aware 全字段编辑 | `d1bc90e` | ✅ |
| — | MCP connectivity test | — | ⏭ 延后（沙箱 + 权限风险） |
| — | MCP registry 浏览 | — | ⏭ 延后（生态未统一） |
| — | Hooks matcher 可视化 / 运行日志回放 | — | ⏭ 延后（需求待验证） |

## 风险 / 未决（已处理）

- **`settings.json` 字段完整清单**：`SettingsCodec` 采用"已知字段强类型 + `extras` 透传"两段式，新增字段无需升级 codec 即可保留
- **MCP 连通性测试**：v0.1.0 决定不在 app 内 spawn 用户进程，规避 supply-chain / sandbox 干扰；后续若补，走独立的 helper 进程 + 权限确认 sheet
- **Hooks 匹配回放**：未实现，留给 v0.2.x；前提是先收集真实使用反馈，避免做一个没人看的面板
- **外部并发修改**：所有 store 走同一套 debounced FSEvents + "外部已修改" 横幅；用户编辑时外部变更会红字提示"重载 / 强制覆盖"

## 对 Phase 3 的影响

- Plugins 安装会触碰 `mcpServers` / `hooks` / `settings.json`，所以 Phase 2 的 `SafeJSONStore` 会被 Phase 3 复用
- 插件影响可视化需要能读 "插件写了哪些 key 到哪些文件"，这又依赖 Phase 2 的字段级更新 API
