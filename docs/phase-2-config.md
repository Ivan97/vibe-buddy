# Phase 2 · JSON 配置三件套（Statusline / MCP / Hooks）

**状态**：📋 计划中，等 Phase 1 拉通
**预计工作量**：约 1-2 周
**依赖**：Phase 1 的 `SafeTextWriter`、`AuthoringScope`、`LabeledRow` / `MultilineTextField` 等表单原子组件

## 目标

把 Claude Code 的三种 JSON 驱动配置纳入图形编辑：Statusline（`settings.json` 的 `statusLine` 字段）、MCP servers（`~/.claude.json` / settings 的 `mcpServers`）、Hooks（settings 的 `hooks` 字段）。三者共用一层"安全 JSON 写入"基础设施，各模块在顶层加自己的特色功能（live preview / connectivity test / run log replay）。

和 Phase 1 最大的不同：**写入风险更高**。这些 JSON 一旦写坏，正在跑的 Claude Code 会立刻受影响。因此本 phase 首要任务是把"写入安全层"做扎实，再让 UI 调用它。

## 技术方案（计划）

### 共享基础设施

**SafeJSONStore**

- 读：`~/.claude/settings.json` 和 `~/.claude.json`，都用 `JSONSerialization` 保留字段顺序（`JSONSerialization.ReadingOptions.mutableContainers`）
- 单字段更新：`updateField(path: "statusLine", value: ...)`，不重写无关字段
- 原子写：复用 `SafeTextWriter`，附带 `.bak`
- Schema 校验：每个字段有对应的 `JSONSchema` 描述（用简单 struct，不引入 json-schema 全标准库）
- 写前 diff 预览：生成 "before / after" 的 JSON 字符串对比，弹 sheet 确认才落盘
- 写入失败时自动回滚 `.bak`

**AuthoringScope 扩展**

- Statusline：只有 global（user settings）
- MCP：global（user settings）+ project（project settings）
- Hooks：global + project

### 各模块特色功能

**Statusline**

- 字段结构（参考 Claude Code 文档）：`{ type: "command", command: "..." }`
- UI：shell 命令输入框 + 实时预览窗口
- 实时预览：app 内部 `Process` 跑用户输入的命令，给一个模拟的 stdin context（模拟 Claude Code 传的 session/path 上下文），展示命令输出
- 常用模板：`cwd`、`git branch`、`time`、`token usage`（from session transcript）

**MCP servers**

- 字段结构：`mcpServers: { "<name>": { command, args, env, ... } }`
- UI：servers 列表 + 每个 server 的详细表单（type / command / args / env 变量）
- 连通性测试：直接用 `Process` 以用户填的命令启动一个 server，发一条 `initialize` JSON-RPC 请求，展示返回
- 支持三种 transport：stdio / sse / http
- Marketplace 浏览（轻量）：从已知的 MCP registry（Anthropic 官方 list）抓列表，"一键添加"

**Hooks**

- 字段结构：`hooks: { "SessionStart": [...], "UserPromptSubmit": [...], ... }`
- 事件类型：`PreToolUse` / `PostToolUse` / `UserPromptSubmit` / `SessionStart` / `Stop` / `SubagentStop` / `Notification` / `PreCompact` / `SessionEnd`
- UI：按事件类型分 tab；每个 hook 是一行 `{ matcher, hooks: [{ type, command, timeout }] }`
- Matcher 可视化：当前 session 会触发哪些 hooks（通过扫描最近 session 的 `attachment.hook_*` 记录，反推匹配关系）
- 运行日志回放：从 session jsonl 里抽 `attachment.type = hook_success / hook_system_message` 行，按时间排列显示历史执行结果

### 写入安全层的 UX

```
用户修改 → [显式 Save] → [diff 预览 sheet] → [确认] → 原子写 → 更新 store
                                ↓
                         [取消] → 回到 UI，不落盘
```

- 每次保存生成 `.bak`
- 如果目标文件外部变动（watcher 检测到），UI 显示 "外部已修改" 横幅，提供 "重载 / 强制覆盖" 选项
- 任何 schema 校验失败 → 红色表单提示，Save 按钮禁用

## 交付内容（计划）

### 基础设施

- `Infrastructure/SafeJSONStore.swift`
- `Infrastructure/JSONFieldUpdater.swift`
- `Infrastructure/JSONSchema.swift`（轻量 schema 描述 + 校验）
- `Features/Config/DiffPreviewView.swift`（可与 Phase 1 的 P1-9 合并）

### 模块

- `Features/Statusline/` — store + live preview + template library
- `Features/MCP/` — store + list/editor + connectivity test + registry 浏览
- `Features/Hooks/` — store + event-tab editor + history replay

## 里程碑（计划草案）

| # | 任务 | 预估 | 状态 |
|---|---|---|---|
| P2-1 | SafeJSONStore + schema 轻量校验 + 单测 | 2 天 | 📋 |
| P2-2 | DiffPreviewView + Save 流水线 | 1 天 | 📋 |
| P2-3 | Statusline 模块（含 live preview） | 2 天 | 📋 |
| P2-4 | MCP 模块（含 connectivity test） | 3 天 | 📋 |
| P2-5 | Hooks 模块（含 event tab + history replay） | 3 天 | 📋 |
| P2-6 | MCP registry 浏览（轻量） | 1-2 天 | 📋 |

## 风险 / 未决

- **`settings.json` 字段完整清单**：Claude Code 本身字段数量在增加，Phase 2 开工前需要把当前最新版（动手时查）的完整字段枚举一遍，确定 "已知字段 + 未知字段透传" 的清单
- **MCP 连通性测试的沙箱影响**：我们要不要真的在 VibeBuddy app 内 spawn 用户的 MCP server 进程？如果不，能测的东西很有限。倾向于 "是，但进程生命周期短（只跑一次 handshake）"
- **Hooks 匹配回放**：依赖 Phase 0 的 session jsonl 解析能力；需要确认 `hook_*` attachment 的完整字段映射
- **外部并发修改**：watcher 触发时如果用户正在编辑，UX 怎么处理需要专门设计（横幅 / 自动合并 / 强制选择）

## 对 Phase 3 的影响

- Plugins 安装会触碰 `mcpServers` / `hooks` / `settings.json`，所以 Phase 2 的 `SafeJSONStore` 会被 Phase 3 复用
- 插件影响可视化需要能读 "插件写了哪些 key 到哪些文件"，这又依赖 Phase 2 的字段级更新 API
