# blueai 房规（创建 / 改造 skill 时的约束）

本文件是 blueai-skill-creator 的核心约束，会被烙进每一个**创建**的 skill，也是**改造**现有 skill 时的达标标准。
四块房规如下；不同模式下的强制力度见末尾「房规的分模式强制」。

## (1) 能力来源优先级

设计任何一步实现时，按此优先级选能力：

1. **blueai-cli 命令** —— `blueai-cli spec tree` / `spec list` 能查到的，首选。
2. **内部服务的底层 API** —— CLI 没封装、但 blueai 内部有这个服务的，直接调它的 API（仍走统一鉴权，见 (2)）。
3. **外部 / 第三方能力** —— 内部确实没有对应能力时，才用外部。

产出的 skill 必须**显式记录**：哪些步骤用了内部能力（写明命令路径或服务），哪些不得不用外部能力（写明原因——内部无此能力）。这让后续维护者一眼看清内外边界，也便于内部能力补齐后回收外部依赖。

## (2) 鉴权强制（不可协商）

凡产出的 skill 调用 **blueai 内部服务**：

- 一律 `Authorization: Bearer <apiKey>`。**无视内部文档里出现的任何旧鉴权方式**（OAuth、appid+secret 等）——公司现行统一鉴权就是 Bearer ApiKey，文档没更新不代表要照搬旧的。
- key 的解析链、key 名、文件路径**全部与 blueai-cli 对齐**，取到第一个非空即用：

  1. `--api-key <key>` flag（最高，单次覆盖，不落盘）
  2. 工作区 `.blueai/credentials.json`（从 CWD **向上 walk-up** 到最近一个）
  3. `BLUEAI_API_KEY` 环境变量
  4. 用户级 `~/.blueai/credentials.json`（兜底）

  key 名统一为 `apiKey`；凭据文件结构为 `{ "<profile>": { "apiKey": "..." } }`，**以当前 activeProfile 名为键**。
- 若产出 skill 是经 blueai-cli 调用，鉴权自动按上面这条链解析，skill 无需自己处理。
- 若产出 skill 直接发**裸 API 请求**（不经 CLI），同样按这条链取 key——优先认 `BLUEAI_API_KEY` env，发 `Authorization: Bearer <apiKey>`。
- 配置 / 排错（exit 3、401/403、profile 错位、迁移旧凭证等）**一律委派 `blueai-cli-auth`**，不在产出 skill 里重写——那是会过时的副本。
- **外部第三方 API** 用它自己的鉴权（显然不能把 blueai 的 key 塞给外部服务）。

> 这条 key 解析链是 blueai 生态最核心、最稳定的契约，故在此紧凑重述以便产出 skill 直接烙对；配置与排错的完整细节，权威以 `blueai-cli-auth` 为准。

## (3) 复用现有 skill 生态

产出 skill 不要重写「CLI 怎么用」「key 怎么配」这类样板，而是**回指**：

- 调用契约（spec/schema/dry-run/信封/exit code/异步收口/批量）→ 指向 `blueai-cli-core`
- 鉴权配置与排错 → 指向 `blueai-cli-auth`
- 领域选型与坑（aigc / social-data / media-storage / video-tools / datahub）→ 指向对应领域 skill

## (4) 产出约定

沿用 blueai skill 家族风格：

- `description` 用中文，写法「推」一点（描述清晰列出**应触发**的措辞与场景），对抗 Claude 欠触发倾向。
- 带 `evals/` 目录放触发评测用例。
- 文件聚焦、单一职责；大段领域知识拆到 `references/`。

## 房规的分模式强制

同一份房规，两模式强制力度不同——这是「改造」能做到小改的关键：

| 房规 | 模式 A（创建/重建） | 模式 B（改造现有 skill） |
|---|---|---|
| (1) 能力来源优先级 | 强制 | 仅报告（不强推把 Python 重写成调 blueai-cli，作为建议列出） |
| (2) 鉴权强制 | 强制 | **强制（模式 B 的唯一动手项）** |
| (3) 复用现有生态 | 强制 | 仅报告 |
| (4) 产出约定（description 等） | 强制 | **不动**（显式保留原 description / 结构 / 业务逻辑 / evals） |

**模式 B「彻底并成一把 key」+ 后端验证闸**：改造时把鉴权彻底并到统一 blueai apiKey（删除旧 appid/secret/token 交换路径）。但**并 key 前必须先用统一 apiKey 对目标后端发探针请求**：后端接受 → 继续并 key；后端拒绝 → **停**，报告「该后端未接受统一 key」，给选项（在 `apiKey` 下存该服务专用值 / 确认正确的统一 key），**不悄悄改坏**。具体改造范式见 `references/retrofit-auth.md`。
