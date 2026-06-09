# 改造现有 skill 的鉴权达标范式（模式 B 专用）

模式 B 只动**鉴权 + key 查找**，其余一律不碰。本文件是改造的确定化范式。

## 第 1 步：审计（grep 清单）

在目标 skill 目录里搜出所有鉴权/key 相关代码与文档：

```bash
grep -rni "secret_key\|client_id\|app_?id\|api_key\|apikey\|token\|Authorization\|Bearer\|credentials\|getenv\|os\.environ\|BLUEAI_" <skill-dir>
```

产出差异清单：当前用什么字段、什么查找方式、什么鉴权流程 → 与统一标准的差距。

## 第 2 步：后端验证闸（并 key 前必须做）

用统一 apiKey 对该 skill 的目标后端发一个最小探针请求（沿用它原本的某个只读端点），
带 `Authorization: Bearer <统一apiKey>`：

- 2xx → 后端接受统一 key，继续第 3 步「彻底并成一把 key」。
- 401/403 → **停**。报告「该后端未接受统一 Bearer apiKey」，给用户两个选项：
  (a) 在统一查找链的 `apiKey` 槽里存该服务专用的 key 值（管道统一、值按服务）；
  (b) 用户确认正确的统一 key 再试。
  **不要**在未验证的情况下删掉原鉴权路径。

## 第 3 步：统一鉴权目标范式（Python）

把原来的 appid/secret / token 交换，替换为下面这套「四级查找 + 直接 Bearer」。
key 名统一 `apiKey`，文件结构、查找顺序与 blueai-cli 完全一致：

```python
import json
import os
from pathlib import Path


def resolve_api_key(cli_flag: str | None = None, profile: str = "default") -> str:
    """按 blueai-cli 的四级链解析统一 apiKey，取第一个非空。

    1. 显式传入(等价 --api-key)  2. 工作区 .blueai(向上 walk-up)
    3. BLUEAI_API_KEY env        4. 用户级 ~/.blueai
    """
    if cli_flag:
        return cli_flag

    # 2. 工作区：从 CWD 向上找最近的 .blueai/credentials.json
    cwd = Path.cwd()
    for parent in [cwd, *cwd.parents]:
        cred = parent / ".blueai" / "credentials.json"
        if cred.exists():
            key = _read_api_key(cred, profile)
            if key:
                return key

    # 3. 环境变量
    env_key = os.environ.get("BLUEAI_API_KEY")
    if env_key:
        return env_key

    # 4. 用户级
    user_cred = Path.home() / ".blueai" / "credentials.json"
    if user_cred.exists():
        key = _read_api_key(user_cred, profile)
        if key:
            return key

    raise RuntimeError(
        "未解析到 blueai apiKey。请用 --api-key 传入、设 BLUEAI_API_KEY、"
        "或运行 blueai-cli config init。"
    )


def _read_api_key(path: Path, profile: str) -> str | None:
    """凭据文件结构 { "<profile>": { "apiKey": "..." } }，以 activeProfile 名为键。"""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None
    bucket = data.get(profile) or {}
    return bucket.get("apiKey")
```

发请求时直接：

```python
headers = {"Authorization": f"Bearer {resolve_api_key()}"}
```

**删除**：原 `client_id`/`secret_key` 字段、`POST /api/auth/token` token 交换、token 缓存逻辑
（统一方案无 token 交换；apiKey 即 Bearer）。配置与排错引导改为指向 `blueai-cli-auth`。

## 第 4 步：同步更新描述凭据的文档

只改「描述凭据」的部分，不动业务说明。常见落点（按目标 skill 实际文件名核对）：

- `references/data_storage.md`：凭据文件结构、字段说明 → 改为 `{ "<profile>": { "apiKey": "..." } }`。
- `references/params_schema.json` / `references/skill_api.json`：凭据入参 `secret_key`/`client_id` → `apiKey`。
- `SKILL.md`：交互流程里收集 `secret_key` 的提示 → 收集/解析 `apiKey`，并指向 blueai-cli-auth。

## 第 5 步：呈现最小 diff，用户批准后应用

只列鉴权/key/凭据文档的改动。改完若 skill 自带 `evals/`，跑一遍确认没改坏，不重写 evals。

## 第 6 步：仅报告其他偏离（不动手）

如「自实现了任务轮询，其实可改用 blueai-cli task wait」「整段可改用 blueai-cli 调用」——
列为建议，留给用户决定，**不在本次改造里动手**。
