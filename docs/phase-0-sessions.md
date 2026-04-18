# Phase 0 · 壳 + Sessions MVP

**状态**：✅ 完成
**时间窗**：2026-04-18
**Git 范围**：`9f9654d` → `3ac6401`

## 目标

一周内交付一个"能用的会话浏览器"，同时把 8 个模块共享的地基（App 骨架 / 数据层抽象 / 双形态协作）立起来。Phase 0 结束时，其他 7 个模块的 UI 入口都存在（点进去是占位空态），只有 Sessions 真正实现。

## 技术方案

### 骨架分层

```
VibeBuddy/
├── App/                # @main + Scene 编排
├── Shell/              # NavigationSplitView chrome + ModuleRoute + Navigator
├── Features/
│   └── Sessions/       # 本 phase 唯一真正的模块
├── Infrastructure/     # ClaudeHome / JSONLReader / JSONLIndex / FileWatcher
├── Observability/      # SentryConfigurator
└── Updater/            # SparkleUpdaterController
```

### 关键设计决策

**双 Scene 共享状态**
`VibeBuddyApp` 持有 `@StateObject` 的 `SessionStore` / `Navigator` / `SparkleUpdaterController`，通过 `.environmentObject` 同时注入主窗口和菜单栏。两个 scene 看到的是同一份 store，菜单栏点击 → 主窗口同步选中，走的是 `Navigator.pendingSessionID` 信号。

**ClaudeHome 抽象**
`ClaudeHome.discover()` 优先读 `$CLAUDE_CONFIG_DIR`，兜底 `~/.claude`。环境和 home 目录都可注入，测试里不碰真实文件系统。子路径（`projectsDir` / `settingsFile` / `commandsDir` / `agentsDir` / `skillsDir` / `pluginsDir`）统一暴露，避免各模块自己拼路径。

**Session jsonl schema 研究先行**
先扫真实 `~/.claude/projects/*/*.jsonl` 总结出 8 种顶层 line type（`user` / `assistant` / `system` / `attachment` / `file-history-snapshot` / `permission-mode` / `last-prompt` / `progress`），确认：
- 目录 slug 是有损编码（`/` 和 `.` 都变 `-`），不可反解；权威项目路径来自行内 `cwd` 字段
- 未知 type 必须优雅降级（`.unknown(type: String)` 兜底），新 CC 版本不会整页崩
- Metadata-only line（permission-mode / last-prompt / file-history-snapshot / progress）在 decode 阶段直接返 `nil`，不进 transcript

完整 schema 记录在 [reference_session_schema.md](../../../.claude/projects/-Users-ivan97-workspace-XCodeWorkspace-vibe-buddy/memory/reference_session_schema.md)。

**类型化 SessionEntry**

```swift
enum SessionEntry.Kind {
    case userText(String)
    case userToolResults([ToolResult])
    case assistantTurn(blocks: [AssistantBlock], model: String?, stopReason: String?, usage: Usage?)
    case systemNote(subtype: String, summary: String)
    case attachment(subtype: String, summary: String)
    case unknown(type: String)
}
```

view 层对 enum 做 pattern match 分派，每一种 kind 有独立的 SwiftUI 子视图（user bubble / assistant card with collapsible thinking+tool_use / meta note）。

**字节偏移索引 + 窗口化分页**

早期一次性 decode 整个 jsonl 会在几万行的会话卡几秒。改造为：

1. `JSONLIndex`：纯数据结构，扫 `\n` 产出 `[Range<Int>]`；`extend(with:)` 支持增量追加
2. `SessionFileBackend`：`actor` 包装 mmap + 索引；正向范围 decode 和反向 batch decode 两个 API
3. `SessionMessageLoader`：`@MainActor` 外观层；首屏只 decode 最后 500 条，滚到顶部哨兵触发 `loadOlderIfNeeded()`
4. `ScrollViewReader.scrollTo(previousFirstID, anchor: .top)` 保持视口不跳
5. 每个 loader 开自己的 `DirectoryWatcher` 监听 session 所在 project 目录；文件追加时只 decode 新增行 append 尾巴

### UI 结构

**主窗口**

```
┌────────────┬─────────────────────────┬──────────────────────┐
│ AppSidebar │ SessionListView         │ SessionDetailView    │
│ 8 路由     │ 按 projectPath 分组     │ LazyVStack + 虚拟化  │
│            │ 搜索 / 刷新 / FS 监听   │ 顶部哨兵自动加载更早  │
└────────────┴─────────────────────────┴──────────────────────┘
```

**菜单栏 popover**（`.menuBarExtraStyle(.window)`）

```
Recent Sessions
  · <first prompt>  <project>  <time ago>
  · ... (top 5)
─────────────
Open VibeBuddy      ⌘O
Check for Updates…
Quit VibeBuddy      ⌘Q
```

## 交付内容

### 功能

- [x] 主窗口 + 菜单栏双形态 App 启动
- [x] sidebar 8 个模块路由（Sessions 真，其余 `ComingSoonView` + phase chip）
- [x] Sessions 列表：按真实 `cwd` 分组、搜索、手动刷新
- [x] Sessions 详情：Markdown 渲染、thinking / tool_use / tool_result 可折叠、usage footer、Reveal in Finder
- [x] FSEvents 增量刷新（500ms debounce，3s 内新会话自动出现）
- [x] 菜单栏最近 5 会话 popover + 点击跳主窗口自动选中
- [x] 窗口化分页（500 条/批，顶部哨兵自动加载更早，锚点保持视口）

### 文件

| 层 | 文件 |
|---|---|
| App | `App/VibeBuddyApp.swift`, `App/AppDelegate.swift`, `App/MainWindowScene.swift`, `App/MenuBarScene.swift` |
| Shell | `Shell/AppShellView.swift`, `Shell/AppSidebar.swift`, `Shell/ComingSoonView.swift`, `Shell/ModuleHost.swift`, `Shell/ModuleRoute.swift`, `Shell/Navigator.swift` |
| Sessions | `Features/Sessions/SessionsRoot.swift`, `SessionListView.swift`, `SessionDetailView.swift`, `SessionModels.swift`, `SessionEntry.swift`, `SessionEntryDecoder.swift`, `SessionMessageLoader.swift`, `SessionFileBackend.swift`, `SessionStore.swift`, `SessionSummaryBuilder.swift` |
| Infra | `Infrastructure/ClaudeHome.swift`, `JSONLReader.swift`, `JSONLIndex.swift`, `FileWatcher.swift` |

### 测试

25 个单测（Phase 0 阶段），全过：

| Suite | 数 | 覆盖面 |
|---|---|---|
| ClaudeHome | 4 | env 覆盖 / 默认 / 空值 / 子路径 |
| SessionSummaryBuilder | 6 | first prompt / tool_result 跳过 / 截断 / 空文件 / 坏行 / slug 兜底 |
| SessionEntryDecoder | 9 | user text / tool_result / assistant 三种 block / attachment / system / metadata drop / unknown / 非 JSON |
| JSONLIndex | 6 | 空 / 两行 / 空行 / partial / extend / 跨 partial |

## 里程碑

| # | 任务 | Commit | 验收 |
|---|---|---|---|
| — | 脚手架 + Sparkle + Sentry + ConfettiSwiftUI | `9f9654d` | XcodeGen 项目生成，三个库链接成功 |
| P0-1 | 拆分 MainWindow + MenuBar 双 scene | `55d5b0d` | 两 scene 同时可启动，共享 updater |
| P0-2 | ClaudeHome + 单测 target | `7a41523` | 4 个单测覆盖 env 覆盖 / 默认 / 空值 / 子路径 |
| P0-3 | NavigationSplitView + 8 路由 | `c73d9a4` | Sessions 真，其余 `ComingSoonView` + phase chip |
| P0-4 | 调研 session schema + 定稿模型 | （无代码 commit，写入记忆） | 产出 `reference_session_schema.md` |
| P0-5 | SessionStore + List 视图 | `c904d3f` | 列表按 projectPath 分组、搜索、刷新、6 个 builder 测试 |
| P0-6 | Detail + Message 渲染 | `7cba0c2` | user bubble / assistant card / thinking / tool_use / usage / 9 个 decoder 测试 |
| P0-7 | FSEvents 增量刷新 | `ea6a072` | 500ms debounce；新会话 3s 内自动出现 |
| P0-8 | 菜单栏 popover + 最近 5 会话 | `e6bea37` | `.window` 风格 popover + Navigator 跨 scene 跳转 |
| — | 窗口化分页（字节偏移索引） | `3ac6401` | 首屏 500 条；顶部哨兵自动加载；锚点保持视口；6 个 index 测试 |

## 遗留 / 可优化

- mmap 在文件被原地替换（rm+重建）时可能失效；Claude Code 只 append，常态下不触发，需要时加 try/catch 兜底即可
- 单会话行数超过百万的场景索引数组本身内存约 24 MB；到达量级时再考虑磁盘持久化
- Sparkle `SUFeedURL` / `SUPublicEDKey` 仍是占位值，发版前补齐
- Sentry DSN 未配置；运行时静默跳过，`export SENTRY_DSN=...` 可随时启用
