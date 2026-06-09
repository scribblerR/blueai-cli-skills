---
name: blueai-skill-creator
description: >
  创建 / 改造 skill 时的 blueai 房规工厂。当用户要「做一个 skill / 把这个工作流封装成 skill /
  生成一个 skill 来自动做 X / 给我搞个 skill 处理 Y」(创建)，或「改一下我那个 skill 的鉴权 /
  把这个旧 skill 改成统一鉴权 / 帮我把某 skill 的 key 查找改成和 blueai 一致 / 别动 description
  只改鉴权」(改造)——任何**创建或修改 skill** 的意图,都先用本 skill。它分两种模式:**创建**走官方
  skill-creator(不在则落盘需求并引导安装、中止),设计前先用 blueai-cli 发现内部能力(spec tree /
  schema)让产出 skill「内部能力优先」;**改造**则完全不走 skill-creator,做外科手术式最小 diff,
  只把鉴权/key 查找拉齐到统一标准,保留原 description/结构/业务逻辑。两模式共用一套 blueai 房规:
  统一 Bearer ApiKey 鉴权、与 blueai-cli 一致的 key 解析链 / key 名 / 路径、内部能力优先、复用现有
  skill 生态。即使用户只含糊说「帮我封装个能力 / 把这个 skill 改达标」,也优先用本 skill 起手。
  **边界**:只在「创建 / 改造 skill」时触发;若用户只是要「用 blueai-cli 跑命令 / 调某个 API /
  写个普通脚本」而非产出/改一个 skill,那是 blueai-cli-core 的领地,不要用本 skill 抢触发。
---

# blueai skill 工厂（房规 + 创建/改造双模式）

本 skill 解决一个具体问题：团队的 skill 容易在两件事上跑偏——**能力来源**（明明内部有却用外部）
和**鉴权**（按旧文档接 OAuth/appid，而非统一 Bearer ApiKey）。本 skill 用一套 blueai 房规
（`references/house-rules.md`）把这两件事拉直，覆盖**新建**和**改造旧 skill**两种场景。

> 心法：本 skill **自己不造 skill**，也**不 fork skill-creator**。**创建**时它是「检测 → 发现内部能力
> → 把房规当硬约束、显式委派 skill-creator」的薄封装；**改造**时它是「审计 → 验证后端 → 最小 diff
> 改鉴权」的外科医生。真正的价值是**房规**和（创建时的）**发现 pre-pass**、（改造时的）**最小 diff**。

## 分派：先判创建还是改造

触发后先分类，再走对应模式：

- 指向一个**已存在的 skill**（给了路径/名字）+ 动词是「改 / 微调 / 只改鉴权 / 别动 description /
  达标 / 合规 / 统一鉴权」→ **模式 B（改造）**，走下面「模式 B」一节。
- 「做一个 / 生成 / 封装成 skill」（新建），或「加个功能 / 重构 / 大改」→ **模式 A（创建）**，走「模式 A」一节。
- 判据：**改动是否局限于鉴权/key/合规**。局限 → B；涉及新能力/重设计 → A。**拿不准就问用户一句**。
- 若用户其实只是想用 blueai-cli 跑命令、调 API、写普通脚本（不产出/改 skill），**不要用本 skill**——交给 `blueai-cli-core`。

---

# 模式 A：创建 / 重建 skill

### A0. 先查未完成的续作

检查当前目录是否存在 `./blueai-skill-handoff.md`。若存在，说明上次因 skill-creator 缺失而中止过：
读回里面记录的需求与发现映射，提示用户「检测到未完成的 skill 创建，是否在此基础上继续？」，
确认后直接进入 A2 之后的流程，不要重头再问一遍需求。处理完成后删除该文件。

### A1. 检测 skill-creator 是否可用

看你自己的**可用技能列表**里有没有 `skill-creator`（也可能以命名空间形式
`example-skills:skill-creator` 出现）。两种名都算可用。

- **可用** → 继续 A2。
- **不可用** → 跳到「中止 - 记录 - 引导」分支（见末尾），然后**停止**，不要自己硬造 skill。

### A2. 发现 pre-pass：把「要造的 skill 的任务」映射到内部能力

在动手设计前，先查 blueai-cli 里有没有现成能力覆盖这个 skill 要做的事。
**发现的权威 how-to 见 `blueai-cli-core`**（它在就用它，更全、更新）。
**最小自足兜底**（core 不在时够用）：

```bash
blueai-cli spec tree                         # 看全貌：内部有哪些能力、层级如何
blueai-cli spec tree --service <id>          # 收窄到某服务
blueai-cli schema <dotted.path> --resolve-refs   # 看某能力的参数/枚举/必填
```

产出一张映射：**要造的 skill 的每个核心步骤 → 有没有内部命令/服务能做**。
按房规 (1) 的优先级标注：哪些走 blueai-cli、哪些走内部 API、哪些只能外部。

### A3. 读房规

读 `references/house-rules.md` 全文。它是下一步注入 skill-creator 的硬约束。

### A4. 显式委派 skill-creator，注入房规

通过 Skill 工具 invoke `skill-creator`（或 `example-skills:skill-creator`）。
进入它的标准流程（capture-intent → 写 SKILL.md → evals → 评测 → 迭代），
但在以下两步把房规和发现映射**当作不可协商的约束**带进去：

- **capture-intent**：把 A2 的「任务 → 内部能力」映射作为既定事实交给它——
  内部能支持的步骤，产出 skill 必须用内部能力。
- **写 SKILL.md**：产出 skill 必须满足房规 (1)(2)(3)(4)——尤其 (2) 鉴权强制：
  统一 Bearer ApiKey、与 blueai-cli 一致的 key 解析链/key 名/路径、配置排错委派 blueai-cli-auth。

让 skill-creator 完成它后续的评测/迭代/打包流程。本 skill 的职责到此为止——
它保证的是「这个 skill 在 blueai 房规下被造出来」，而不是替代 skill-creator 的造法。

---

# 模式 B：改造现有 skill 达标（不走 skill-creator）

只动**鉴权 + key 查找**，其余（description、业务逻辑、结构、evals）一律不碰。
**模式 B 不依赖 skill-creator**，缺它也照常工作。完整范式见 `references/retrofit-auth.md`，逐步：

### B1. 定位并审计

读目标 skill（用户给路径，如 `C:\...\blueai-social-media-data`）。按 `references/retrofit-auth.md`
第 1 步的 grep 清单搜出所有鉴权/key 相关代码与文档，产出「当前鉴权 → 统一标准」差异清单。

### B2. 后端验证闸（并 key 前必须做）

用统一 apiKey 对该 skill 的目标后端发一个最小只读探针请求（带 `Authorization: Bearer <统一apiKey>`）：

- 后端接受（2xx）→ 继续 B3「彻底并成一把 key」。
- 后端拒绝（401/403）→ **停**。报告「该后端未接受统一 key」，给用户选项（在 `apiKey` 槽存该服务专用值 /
  确认正确的统一 key），**不要在未验证下删掉原鉴权路径**。

### B3. 最小 diff：只改鉴权 + key + 凭据文档

按 `references/retrofit-auth.md` 第 3/4 步：把 appid/secret/token 交换替换为「四级查找 + 直接 Bearer」
（key 名 `apiKey`、文件结构与 blueai-cli 一致），彻底并成一把 key；同步只改描述凭据的文档字段。
**显式不动**：description、业务逻辑、整体结构、evals。

### B4. 呈现 diff，批准后应用

只列鉴权/key/凭据文档的改动给用户看，批准后应用。若 skill 自带 `evals/`，跑一遍确认没改坏，不重写 evals。

### B5. 仅报告其他偏离（不动手）

如「自实现轮询可改用 blueai-cli task wait」「整段可改用 blueai-cli」——列为建议留给用户，本次不动手。

---

## 中止 - 记录 - 引导（仅模式 A，skill-creator 不可用时）

当 A1 检测到 skill-creator 不可用，按三步走，**不要自己硬造 skill**（模式 B 不受此限）：

### 1. 记录（落盘）

把已经收集到的信息写入当前目录的 `./blueai-skill-handoff.md`：

```markdown
# 未完成的 skill 创建（blueai-skill-creator handoff）

## 需求
- 这个 skill 要做什么：<...>
- 触发场景 / 用户会怎么说：<...>
- 输入 / 输出：<...>

## 发现 pre-pass：任务 → 内部能力映射
<如果 A2 已经跑过,把映射贴在这里;没跑就写「待装好后补」>

## 房规
见 blueai-skill-creator/references/house-rules.md（统一 Bearer ApiKey 鉴权 +
key 解析链与 blueai-cli 一致 + 内部能力优先 + 复用现有 skill 生态）。

## 续作
装好 skill-creator 后，重新表达创建意图即可；blueai-skill-creator 会读回本文件继续。
```

### 2. 引导安装

明确告诉用户 skill-creator 属 `example-skills` 插件，给出确切命令：

```
/plugin marketplace add anthropics/skills      # 若该市场尚未添加过
/plugin install example-skills@anthropic-agent-skills
```

### 3. 中止

告诉用户：「已把需求与房规记录到 `./blueai-skill-handoff.md`。装好 skill-creator 后，
再说一次你的创建意图，我会读回这份记录接着干。」然后停止，不继续造 skill。

## 为什么这么设计

- **不 fork skill-creator**：官方 skill-creator 会持续演进（评测、描述优化、打包）。
  fork 会让我们错过它的更新。创建时显式委派 + 注入约束，既借它的造法，又保证 blueai 房规。
- **创建/改造分两模式**：创建走 skill-creator（重）；改造只动鉴权、外科手术式最小 diff（轻），
  不依赖 skill-creator，也不动 description/业务逻辑——满足「旧 skill 只想微调鉴权」的真实诉求。
- **窄触发**：只管「创建/改造 skill」，不抢 blueai-cli-core 的「怎么用命令」意图，边界清晰。
- **房规单一来源**：房规集中在 `references/house-rules.md`，不在产出 skill 里复制 CLI/鉴权样板，
  避免会过时的副本。
