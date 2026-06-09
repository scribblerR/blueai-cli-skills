---
name: blueai-cli-auth
description: >
  配置 blueai-cli 的 apiKey 凭证、并排查鉴权失败。当用户要：第一次配 key、设置 / 修改
  apiKey、key 放哪一层（工作区 vs 用户级 vs 环境变量 vs --api-key flag）、多环境
  profile 切换、CI / 容器 / Agent 怎么注入 key、迁移旧凭证（providers/services/appid）——
  或遇到鉴权报错：exit code 3、"No API key found"、auth 失败、401/403、
  "明明 export 了 BLUEAI_API_KEY 却还用旧 key"、"key 不生效 / 用错了 key"、
  "doctor 说没 apiKey 但命令能跑"——任何此类配置或排错意图都用本 skill。
  即使用户只含糊说"blueai 怎么登录 / 怎么填 key / 鉴权过不去"，也优先用本 skill
  把意图翻译成正确的凭证放置层 + CLI 命令。本 skill 负责"key 放哪、谁会赢、怎么排"。
---

# BlueAI CLI 凭证配置与鉴权排错

blueai-cli 用**单一统一 apiKey**（`Authorization: Bearer <apiKey>`）鉴权所有服务。本 skill 解决两件事：**把 key 配到正确的层** + **鉴权过不去时定位根因**。

## 核心：四级优先级链（一切的基础）

每次调用，CLI 按从高到低四级解析最终生效的 apiKey，**取到第一个非空即用**：

| 优先级 | 来源 | 适用场景 |
|---|---|---|
| 1（最高） | `--api-key <key>` flag | 单次调用临时覆盖一切；CI/Agent 显式传，不落盘 |
| 2 | 工作区 `.blueai/credentials.json`（从 CWD **向上 walk-up** 到最近一个） | 项目级 key 覆盖全局；多仓库用不同账号 |
| 3 | `BLUEAI_API_KEY` 环境变量 | 单 shell 会话 / 容器 / CI 全局默认 |
| 4（兜底） | 用户级 `~/.blueai/credentials.json` | 个人开发机的全局默认 |

> **铁律 1：凭据文件的查找都以「当前 activeProfile 名」为键。** 文件结构是 `{ "<profile>": { "apiKey": "..." } }`。key 存在 `default` 下但 active 是 `prod`（或反之）→ 查不到 → exit 3。这是"我配了啊怎么还报没 key"的头号原因。
>
> **铁律 2：上层会静默压过下层。** 工作区文件赢过 env var 赢过用户级。所以"我 export 了 `BLUEAI_API_KEY` 怎么还用旧 key"几乎总是因为 CWD 或某个父目录里藏着 `.blueai/credentials.json`。

四级全空 → 抛 `auth` 错误，**exit code 3**，提示 `blueai-cli config init`。

## 决定把 key 放哪一层

先问"这个 key 的作用域多大"，再选层——别无脑都写用户级：

| 场景 | 放哪 | 命令 |
|---|---|---|
| 个人机，一个账号到处用 | 用户级 | `blueai-cli config init` |
| 某项目要用**不同**账号/环境 | 工作区（项目根 `.blueai/`） | 见下方 recipe，**记得 gitignore** |
| CI / 容器 / Agent 批处理 | env var 或每次 flag | `export BLUEAI_API_KEY=…` / `--api-key` |
| 临时拿另一个 key 跑一次 | flag，不落盘 | `--api-key "…"` |
| prod/staging 多环境来回切 | profiles | `config profiles --use` + 各自 init |

## 配置 recipe

```bash
# 用户级（交互式，人用）
blueai-cli config init

# 用户级（非交互，Agent/CI 首选——避免 stdin 阻塞）
blueai-cli config init --api-key "$BLUEAI_KEY"

# 工作区（项目级覆盖）——在项目根目录
mkdir -p .blueai
printf '{ "default": { "apiKey": "%s" } }\n' "$BLUEAI_KEY" > .blueai/credentials.json
echo '.blueai/' >> .gitignore        # 千万别把 key 提交进仓库

# 环境变量（容器/CI/单会话）
export BLUEAI_API_KEY="blueai-xxxx"

# 单次覆盖（最高优先级，不写任何文件）
blueai-cli <cmd> --params '{...}' --api-key "blueai-xxxx"
```

> 工作区文件结构与用户级**完全相同**（profile 名为键）。若工作区用的是非 default profile，键名要对上 active profile。

## 多环境 profile

```bash
blueai-cli config profiles              # 列出所有 profile + active 标记 + hasApiKey
blueai-cli config profiles --use prod   # 切到 prod（不存在则以当前 profile 为模板新建）
blueai-cli config init --api-key "$PROD_KEY"   # 给「当前 active」profile 存 key
```

> 切了 profile 之后**必须**单独给新 profile init 一个 key——新建的 profile 只复制了行为配置（轮询/格式等），不复制凭据。`config profiles` 输出里 `hasApiKey:false` 就是它在喊"我还没 key"。

## 排错流程

**第一步永远先跑 doctor**：

```bash
blueai-cli doctor    # 检查 config / 工作区凭证命中 / apiKey / gateway 连通性
```

> **doctor 的 `apiKey` 检查走完整解析链（工作区 → `BLUEAI_API_KEY` env → 用户级），并在 detail 里报告命中来源**（如 `来源：BLUEAI_API_KEY 环境变量`）。纯靠 env var 的人也会看到 apiKey 检查通过。注意它**不认 `--api-key` flag**（flag 是单次调用临时传的、doctor 自身拿不到），所以只靠 flag 跑命令时 doctor 仍会报 apiKey 缺失——这是正常的。`workplace` 检查会打印命中的工作区路径，排"被静默压过"时最有用。

然后按错误类型分流：

| 错误信号 | 含义 | 往哪查 |
|---|---|---|
| **exit code 3** / `error.type=auth` / "No API key found" | key **没解析到**，或解析到了**错的层/错的 profile** | 四级优先级 + profile 名（下方 gotchas） |
| **401 / 403**（业务错，**非** exit 3，`error.type=api`） | key 解析到了，但**无效/过期/无权限** | 不是放置问题；换有效 key，看 `error.detail.body` |
| `error.type=network` | 连不上 gateway | `doctor` 的 gateway 检查；与 key 无关 |

## Gotchas（排错对号入座）

1. **工作区文件静默压过 env var + 用户级** —— "export 了还用旧 key"：CWD 或父目录有 `.blueai/credentials.json`。用 `doctor` 看 workplace 命中路径，删/改它或改用 `--api-key` 强制覆盖。
2. **doctor 认 env var、但不认 `--api-key` flag** —— doctor 走完整解析链（含 `BLUEAI_API_KEY` env），靠 env var 配的 key 会显示通过并在 detail 标出来源。唯一例外：只用 `--api-key` flag 单次传 key 时 doctor 拿不到（flag 是临时的），会报"没 apiKey"但命令照跑不 exit 3——正常。
3. **profile 错位** —— key 在 `default`、active 是别的（或反之）。`config profiles` 看哪个 profile 有 key、哪个是 active，用 `--use` 对齐或给当前 profile 重新 init。
4. **`BLUEAI_CONFIG_DIR` 关掉工作区 walk-up** —— 一旦设了它（测试隔离/CI 路径重定向），工作区查找**直接跳过**，只认它指向的目录。CI 里又设它又指望工作区 key 生效 → 不会生效，改用 env var/flag。
5. **walk-up 取最近的** —— 嵌套目录里，离 CWD 最近的 `.blueai` 赢。在子目录跑 vs 在仓库根跑可能拾取不同文件。

## 迁移旧凭证

```bash
blueai-cli config migrate    # 旧 providers.*.api_key / services.*.api_key → 统一顶层 apiKey；自动备份 .bak
```

- 旧文件只含 `appid`/`secret`（OAuth 凭证）→ **无法自动迁移**，必须申请 BlueAI 统一 apiKey 再 `config init`。
- 同一 profile 下多个服务的 api_key **值不一致** → migrate 报错（无法替你选）→ 手动 `config init` 定一个统一 key。
- 已是统一 apiKey 格式 → migrate 提示 "nothing to migrate"，幂等安全。

## 别踩的混淆

- **gateway env var ≠ auth。** `BLUEAI_GATEWAY` / `BLUEAI_SPEC_GATEWAY` / `BLUEAI_<SERVICE>_GATEWAY` 改的是**请求/spec 端点**，跟 apiKey 解析无关。鉴权过不去别去动这些。
- **`api` 内置命令需要 `--gateway`**，但它的鉴权仍走同一套 apiKey 解析——key 配置方式不变。
- **安全**：永不把 `.blueai/credentials.json` 提交进 git；CI 里从 secret store 注入 `BLUEAI_API_KEY`，别硬编码进脚本或日志。

## 常见错误速查

| 现象 | 根因 | 修正 |
|---|---|---|
| exit 3 "No API key found" | 四级全空，或 key 在别的 profile | `config init`；`config profiles` 核对 active |
| export 了 env 仍用旧 key | 工作区 `.blueai` 静默压过 | `doctor` 看 workplace 路径 → 删/改，或 `--api-key` 覆盖 |
| doctor 说没 apiKey 但能跑 | 你在靠 `--api-key` flag（doctor 拿不到单次 flag；env var 它是认的） | 正常，以是否 exit 3 为准 |
| CI 里工作区 key 不生效 | 设了 `BLUEAI_CONFIG_DIR` 关掉 walk-up | 改用 env var/flag |
| 401/403（非 exit 3） | key 有效但失效/越权 | 非放置问题；换 key，看 `error.detail.body` |
| migrate 报 appid/secret 无法升级 | 旧 OAuth 凭证 | 申请统一 apiKey → `config init` |
| 切了 profile 后 exit 3 | 新 profile 没 key | 给当前 active profile `config init` |
