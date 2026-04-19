# Phase 1 · Markdown + Frontmatter 编辑三件套

**状态**：✅ 完成（Subagents / Prompts / Skills 三模块 + 保存前 diff 预览均已落地）
**时间窗**：2026-04-18
**Git 范围**：`e56a527` → `447a0d9`

## 目标

在一套共享的 "markdown + YAML frontmatter" 编辑层上，依次落地三个模块：

1. **Subagents** — `~/.claude/agents/*.md`，83 个样本最规整（3 字段 frontmatter）
2. **Prompts (commands)** — `~/.claude/commands/*.md`，支持目录嵌套命名空间
3. **Skills** — `~/.claude/skills/<name>/SKILL.md`，目录形态、符号链接、plugin 只读

三个模块共享：frontmatter codec、原子写入、schema 协议、编辑器组件、列表 + 表单 + body 的布局。

## 技术方案

### 基础设施层

**FrontmatterCodec**（手撸 YAML-lite）

只支持 Claude Code 里观察到的子集：
- `key: value` 标量（裸 / 双引号 / 单引号）
- 简单字符串列表：`key:` 后跟 `  - item`
- 内联空列表：`key: []`

round-trip 约束：
- 键顺序保留
- 未知键透传（已知 schema 只认 `name/description/model`，其余放 `extras` 原样往回写）
- body 首部多个换行归一成 0 个；serializer 始终在 `---` 后写一个空行 → round-trip 稳定
- 缺失闭合 `---` / BOM / 坏行都降级为 "无 frontmatter，整段当 body"

**SafeTextWriter**

- `Data.write(options: .atomic)` → Foundation 写临时 + rename，读者不会看到半写状态
- 覆写时先把旧版本拷贝到同名 `.bak` 作为兜底（失败仅记录，不阻断写入）
- `describeSymlink(at:)` 返回符号链接目标 URL；Skills 模块后续要用它在写入前提醒用户"正在改源文件"
- 缺失父目录自动创建

**FrontmatterDocument<Schema> + FrontmatterSchema 协议**

```swift
protocol FrontmatterSchema: Equatable, Sendable {
    init(from map: FrontmatterMap)
    func toMap() -> FrontmatterMap
    static var empty: Self { get }
}

struct FrontmatterDocument<Schema: FrontmatterSchema> {
    var schema: Schema
    var body: String
    init(raw source: String)                 // 解析 markdown 文件
    func serialized() -> String              // 序列化回去
}
```

每个模块实现自己的 schema struct（Subagents 用 `AgentFrontmatter`，后续 Prompts 用 `CommandFrontmatter`，Skills 用 `SkillFrontmatter`），把已知字段命名为属性，未知字段存在 `extras: FrontmatterMap` 里透传。

**Store 模板**（目前 `AgentStore` 为代表）

- `reload()` → `Task.detached` 扫目录、并发 decode 每个文件 header、排序
- `load(_ handle)` / `save(_ doc, to handle)` / `create(name:description:model:)` / `delete(_ handle)`
- `startWatching()` → `DirectoryWatcher` + 500ms debounce，外部编辑实时同步

**AuthoringScope 枚举**

```swift
enum AuthoringScope: String { case global, project, plugin }
```

为 Prompts / Skills 准备好 section 分组语义；Subagents 当前只用 `.global`，但 UI 已经按 section 布置，三模块能共用同一个 `AgentListView` 布局模式。

### UI 层

**共享原子组件**（`Features/Authoring/`）

- `LabeledRow` — 标签 + 可选 hint + 内容容器
- `MultilineTextField` — 用作 `description` 输入
- `MarkdownEditor` — 用作 body 输入；Phase 1 MVP 是等宽 `TextEditor` + 带 placeholder + 圆角边框；后续可替换为带高亮的编辑器，外部 API 不变

**每个模块的视图组合**（以 Subagents 为参考）

```
SubagentsRoot (从 env 拿 AgentStore)
└── SubagentsShell (HSplitView)
    ├── AgentListView (搜索 + section + 底部 New Agent)
    └── AgentEditorView  (或 EmptyDetailView)
        ├── toolbar (Unsaved / Reveal / Delete / Revert / Save)
        ├── LabeledRow "Name"
        ├── LabeledRow "Description"
        ├── LabeledRow "Model" (Picker)
        ├── MarkdownEditor "body"
        └── Unknown frontmatter keys (只读展示)
    └── NewAgentSheet (弹窗，kebab-case 自动归一)
```

这套组合在 Prompts / Skills 会被复用（列表 + 表单 + body），差别在表单字段数量和 section 分组逻辑。

### 写入策略

- **立即保存 vs 显式 Save**：选择显式 Save（`⌘S` 或工具栏按钮）。好处：编辑中途不触发 watcher 循环；dirty 标记清晰；配合后续的 diff 预览自然。
- **Revert**：从磁盘重新 load，丢掉本地修改。
- **`.bak` 自动保留**：任何覆写都留一份上一版本，误删也能手工恢复。
- **Delete 确认**：alert 弹窗，强调 `.bak` 会留着。

## 交付内容

### ✅ 已交付（P1-1 ~ P1-6）

**基础设施**
- `Infrastructure/FrontmatterCodec.swift` + 10 个 codec 测试
- `Infrastructure/SafeTextWriter.swift` + 6 个 writer 测试
- `Features/Authoring/FrontmatterSchema.swift` — 协议 + 文档壳
- `Features/Authoring/MarkdownEditor.swift` + `FormControls.swift`

**Subagents 模块**
- `Features/Subagents/AgentFrontmatter.swift` + 4 个 schema 测试
- `Features/Subagents/AgentStore.swift`（list / load / save / create / delete / watch）
- `SubagentsRoot.swift` / `AgentListView.swift` / `AgentEditorView.swift` / `NewAgentSheet.swift`
- `ModuleRoute.subagents.phase = 0`（chip 消失）；`ModuleHost` 分派到 `SubagentsRoot`

**功能**
- [x] 列出 `~/.claude/agents/` 的 83 个 agent，按字母序
- [x] 搜索（name / description）
- [x] 选中 → 编辑 frontmatter（name / description / model）+ body
- [x] 未知 frontmatter key 只读展示，保证 round-trip
- [x] Save 原子写 + `.bak`；`⌘S` 快捷键；Revert 按钮
- [x] New Agent 弹窗 + kebab-case 自动归一 + 命名冲突报错
- [x] Delete 确认 + `.bak` 兜底
- [x] FSEvents 监听，外部编辑 500ms 内列表刷新
- [x] Reveal in Finder

### ✅ 已交付（P1-7 · Prompts）

- `Features/Prompts/CommandFrontmatter.swift` + 4 个 schema 测试（字段：`description` / `argument-hint` / `allowed-tools`）
- `Features/Prompts/CommandScanner.swift` + 5 个 scanner 测试：递归扫 `commands/` 子目录，用路径拼 `/namespace:command`
- `Features/Prompts/CommandStore.swift`：load / save / create / delete / watch（复用 `SafeTextWriter` + `DirectoryWatcher`）
- `PromptsRoot.swift` / `CommandListView.swift` / `CommandEditorView.swift` / `NewCommandSheet.swift`
- Sidebar 按目录分组折叠；新建时可选目标子目录
- 项目级 `.claude/commands/` 以 `Project` section 加入 sidebar
- `ModuleRoute.prompts.phase = 0`（chip 消失）

### ✅ 已交付（P1-8 · Skills）

- `Features/Skills/SkillFrontmatter.swift` + 3 个 schema 测试（字段：`name` / `description` / 可选 `license` + `allowed-tools`）
- `Features/Skills/SkillClassifier.swift` + 6 个分类测试：目录形态（`<name>/SKILL.md`）、符号链接解引用、plugin-provided 识别、缺失 SKILL.md 的残缺标记
- `Features/Skills/SkillStore.swift`：list / load / save / create / delete + FSEvents
- `SkillsRoot.swift` / `SkillListView.swift` / `SkillEditorView.swift` / `NewSkillSheet.swift`
- Plugin-provided skill 独立 section 只读展示（按钮置灰）
- 残缺 skill 列表里标红、保留在 sidebar 供排查

### ✅ 已交付（P1-9 · 保存前 diff 预览）

- `Features/Authoring/DiffPreviewSheet.swift` + `TextDiffTests.swift`（7 个测试）
- 简单行 diff 渲染 before / after，编辑场景默认弹预览，新建走静默保存
- `MarkdownEditor` 在 Phase 1 中期升级为 preview / edit 切换（`MarkdownUI` 渲染 block 级 markdown），预览上限 256 KB
- 三个模块（Subagents / Prompts / Skills）统一接入同一个 diff sheet

### 跨模块整合

- Plugins 模块（Phase 3）为三类资源加了"来源"徽章，点击 → 跳转到 Plugins 模块聚焦该插件
- Prompts / Skills / Subagents 的列表项显示 `Global / Project / Plugin: <name>` 三态

### 未落地（P1-10 · 跨 scope 迁移）

"Copy to Project" / "Promote to Global" 动作最终没在 v0.1.0 前落地。原因：Phase 3 的跨模块跳转 + Plugins 的来源徽章已经覆盖 "我这个 skill 来自哪" 的主要痛点；真正需要"在 global / project 之间搬家"的用户场景少，留到 v0.2.x 再做。

## 里程碑

| # | 任务 | Commit | 验收 |
|---|---|---|---|
| P1-1 | FrontmatterCodec（parse / serialize） | `e56a527` | 10 个测试覆盖 agent 样本 / 未知键保留 / list / 引号 / 空列表 / 坏 fence / BOM |
| P1-2 | SafeTextWriter（原子写 + `.bak`） | `d7c40b1` | 6 个测试覆盖新建 / 覆写 backup / 跳过 backup / 父目录 / symlink 检测 |
| P1-3 | FrontmatterDocument + AgentFrontmatter | `d7c40b1`→`9249ef7` 之间 | 4 个测试覆盖标准形 / 未知键 round-trip / empty model / 无 frontmatter |
| P1-4 | AgentStore + FSEvents | `9249ef7` | 扫描 83 个 agent，外部编辑 500ms 内刷新 |
| P1-5 | MarkdownEditor + 表单原子组件 | `3e9a983` | 复用到 `AgentEditorView` + `NewAgentSheet` |
| P1-6 | Subagents 模块端到端 | `58e877f` | app 启动 → Subagents route → 可编辑 / 保存 / 新建 / 删除 / reveal |
| P1-7 | Prompts 模块 | `3de38d9` | 递归子目录 + `/ns:cmd` 命名、sidebar 分组折叠、Project section 可用 |
| P1-8 | Skills 模块 | `aba60b2` → `52a21be` | 目录形态、symlink 解引用、plugin-provided 只读 section、残缺标记 |
| P1-9 | 保存前 diff 预览 | `447a0d9` | 编辑默认弹 sheet、新建直接落盘；三模块共用 |
| P1-10 | 跨 scope 迁移（Copy to Project / Promote to Global） | — | ⏭ 延后至 v0.2.x |

## 对 Phase 2 的影响

- `SafeTextWriter` 的"原子 + 备份"路径 Phase 2 会被复用，但会再加一层 "schema 校验 + diff 预览"，因为写的是 `settings.json` 这种会直接影响正在运行的 Claude Code 的生产配置
- `AuthoringScope` 在 Phase 2 仍然适用（global / project）
- `MarkdownEditor` 不在 Phase 2 的路径上，但 `LabeledRow` / `MultilineTextField` 会被 Statusline / MCP / Hooks 的表单复用

## 遗留 / 约定

- 手撸 YAML-lite 解析器只覆盖实测出现的写法；遇到用户手工塞了嵌套 map / anchor / tag 的文件会降级为 "无 frontmatter + raw body"，不会炸但会失去表单编辑能力。后续如遇真实案例再切 Yams。
- P1-10 跨 scope 迁移未落地：真实使用中"在 global / project 之间搬家"的场景少，由 Plugins 模块的跨模块跳转 + 来源徽章覆盖了主要痛点；留待后续 minor 版本。
- `MarkdownEditor` 只是 preview / edit 切换，没有语法高亮；等外部提示再升级，避免过早引入体量大的编辑器依赖。
