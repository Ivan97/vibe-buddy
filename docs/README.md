# VibeBuddy Roadmap

VibeBuddy 是 Claude Code 的 macOS 图形化操控台，把散落在 `~/.claude/` 和项目 `.claude/` 的配置、会话、扩展统一纳入主窗口 + 菜单栏双形态应用。整体拆成 4 个 phase，每个 phase 共享下一层的基础设施。所有 phase 已在 v0.1.0 完成交付。

## 产品范围（9 个模块）

| 模块 | 数据源 | 主模式 |
|---|---|---|
| Sessions | `~/.claude/projects/<slug>/*.jsonl` | 只读 jsonl 浏览 + live 生成指示 |
| Prompts (commands) | `~/.claude/commands/*.md` + 项目 `.claude/commands/*.md` | md + frontmatter CRUD |
| Skills | `~/.claude/skills/<name>/SKILL.md` + plugin-provided | md + frontmatter CRUD |
| Subagents | `~/.claude/agents/*.md` + 项目 `.claude/agents/*.md` | md + frontmatter CRUD |
| Statusline | `settings.json` 的 `statusLine` 字段 | 安全 JSON 编辑 + 实时预览 |
| MCP | `~/.claude.json` / settings 的 `mcpServers` | 安全 JSON 编辑 + plugin server 合并 |
| Hooks | `settings.json` 的 `hooks` 字段 | 安全 JSON 编辑 + 事件分 tab |
| Settings | `settings.json` / `~/.claude.json` 全量字段 | schema-aware 编辑 + diff 预览 |
| Plugins | `.claude-plugin/` + 已安装 plugin 清单 | marketplace + 跨模块跳转 + 自动更新 |

9 个模块底层只有 4 种模式：

1. **只读 jsonl 浏览** → Sessions
2. **Markdown + frontmatter 编辑** → Prompts / Skills / Subagents
3. **JSON 配置字段编辑** → Statusline / MCP / Hooks / Settings
4. **跨模块编排** → Plugins（依赖上面所有）

## Phase 划分

| Phase | 目标 | 状态 | 文档 |
|---|---|---|---|
| 0 | 壳 + 数据层地基 + Sessions MVP | ✅ 完成 | [phase-0-sessions.md](./phase-0-sessions.md) |
| 1 | md + frontmatter 编辑三件套 | ✅ 完成（Subagents / Prompts / Skills + 保存前 diff） | [phase-1-authoring.md](./phase-1-authoring.md) |
| 2 | JSON 配置三件套 | ✅ 完成（Statusline / MCP / Hooks + SafeJSONStore） | [phase-2-config.md](./phase-2-config.md) |
| 3 | Plugins 编排与 marketplace | ✅ 完成（扫描 / 启用开关 / 跨模块跳转 / 自动更新） | [phase-3-plugins.md](./phase-3-plugins.md) |

首个公开版本 `v0.1.0` 已发版，走 Sparkle + GitHub Pages appcast 自动更新；发布流程见 [RELEASING.md](./RELEASING.md)。

## 跨 phase 约定

- **App 形态**：主窗口（`NavigationSplitView`，sidebar + detail）+ 菜单栏 `MenuBarExtra` popover。两个 scene 共享一套 `@StateObject` 状态（`SessionStore` / `AgentStore` / `CommandStore` / `SkillStore` / `StatuslineStore` / `MCPStore` / `HooksStore` / `PluginsStore` / `SettingsStore` / `Navigator` / `SparkleUpdaterController`）。
- **最低 macOS**：14.0 Sonoma。
- **构建工具**：XcodeGen（`project.yml` 驱动，`VibeBuddy.xcodeproj` 不入库）。
- **测试**：Swift Testing，每个基础设施模块必须带单测；UI 层不强求。截至 v0.1.0：20 个 suite / 122 个 test，全过。
- **写入安全**：所有写盘先原子（`Data.write(options: .atomic)`），需要时附带 `.bak` 兜底；`settings.json` / `~/.claude.json` 类生产配置统一经过 `SafeJSONStore` 的 schema 校验 + diff 预览 sheet 确认后落盘。
- **外部变动响应**：所有 store 用 `DirectoryWatcher`（FSEvents 封装）监听对应目录，500ms debounce 后重扫。
- **发版与更新**：Sparkle ed25519 签名，`appcast.xml` 由 GitHub Pages 托管；app 内置 "Check for Updates…"，每 24h 自动轮询。

## 相关记录

- [project_vibebuddy.md](../../../.claude/projects/-Users-ivan97-workspace-XCodeWorkspace-vibe-buddy/memory/project_vibebuddy.md) — 项目定位与阶段决策
- [reference_session_schema.md](../../../.claude/projects/-Users-ivan97-workspace-XCodeWorkspace-vibe-buddy/memory/reference_session_schema.md) — session jsonl schema 参考
