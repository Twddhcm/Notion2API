# Notion2API Neutral Assistant

基于 [GALIAIS/Notion2API](https://github.com/GALIAIS/Notion2API) 的定制版本，将 Notion AI 接口转换为 OpenAI 兼容 API，并对常见的助手身份自述进行中性化处理。

本项目支持 Web 管理后台、多账号池、动态模型发现、流式响应和 Docker 部署。它不会把无法验证的底层模型冒充为某个特定官方模型。

## 主要改动

- 将常见的 `Notion AI` 身份自述转换为通用 AI 助手表述
- 增加 GPT、Claude、Gemini、Grok、Kimi、DeepSeek、GLM 等模型映射
- Docker 配置目录改为可写挂载，后台保存配置后可以持久化
- 提供 Debian 13 一键安装脚本
- 排除本地账号、Cookie、API Key、数据库和运行数据

## 一键安装

适用于全新 Debian 13 服务器。需要 root 或 sudo 权限，并确保服务器可以访问 GitHub 和 Docker 软件源。

```bash
curl -fsSL \
  https://raw.githubusercontent.com/Twddhcm/Notion2API/v1.0.8-neutral.3/install.sh |
sudo bash
```

安装脚本将自动完成：

1. 安装 Docker Engine 和 Docker Compose
2. 下载 `v1.0.8-neutral.3` 源码
3. 创建 `/opt/notion2api/config` 和 `/opt/notion2api/data`
4. 生成随机 API Key 和管理密码
5. 构建并启动容器
6. 等待健康检查通过

安装凭据保存在：

```text
/opt/notion2api/config/install-credentials.txt
```

一键安装不会覆盖已有的 `/opt/notion2api`。已有部署请先备份配置和数据，再手动升级。

## 安装后配置

管理后台：

```text
http://服务器IP:8787/admin
```

进入后台后导入自己的 Notion 账号。可以粘贴 Cookie、`token_v2`，也可以导入完整 Probe JSON。账号凭据只应保存在服务器本地，禁止提交到 GitHub。

账号状态显示为 `ready`、`active`、`enabled` 后，再进行模型测试。

## 手动 Docker 部署

```bash
git clone --branch custom/neutral-assistant \
  https://github.com/Twddhcm/Notion2API.git

cd Notion2API
mkdir -p config data
cp config.docker.json config/config.json
chmod 600 config/config.json
```

在现有 `config/config.json` 中修改以下两个字段，不要用这个片段覆盖整个文件：

```json
{
  "api_key": "替换为自己的API密钥",
  "admin": {
    "password": "替换为管理后台密码"
  }
}
```

启动服务：

```bash
docker compose up -d --build
```

检查状态：

```bash
docker compose ps
curl -fsS http://127.0.0.1:8787/healthz
```

## API 使用

默认 OpenAI 兼容地址：

```text
http://服务器IP:8787/v1
```

设置 API Key：

```bash
export N2A_API_KEY='你的API密钥'
```

查询可用模型：

```bash
curl -sS http://127.0.0.1:8787/v1/models \
  -H "Authorization: Bearer ${N2A_API_KEY}" |
jq -r '.data[]?.id'
```

聊天测试：

```bash
curl -sS http://127.0.0.1:8787/v1/chat/completions \
  -H "Authorization: Bearer ${N2A_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "auto",
    "messages": [
      {"role": "user", "content": "你好，请简单介绍一下你自己。"}
    ]
  }' |
jq -r '.choices[0].message.content'
```

第三方客户端配置：

| 配置项 | 示例 |
| --- | --- |
| API 类型 | OpenAI Compatible |
| Base URL | `http://服务器IP:8787/v1` |
| API Key | 安装时生成或自行设置的 Key |
| Model | `auto` 或 `/v1/models` 返回的模型 ID |

## 模型说明

模型列表由以下内容合并生成：

- 程序内置模型
- `config/config.json` 中的 `models`
- 账号 Probe 中动态发现的模型
- `model_aliases` 中的自定义别名

因此模型是否可用以当前账号和 `/v1/models` 的实际返回结果为准。上游可能调整内部模型名称、账号权限或可用区域。

## Docker 运维

查看状态：

```bash
cd /opt/notion2api
docker compose ps
```

查看日志：

```bash
docker compose logs -f --tail=200 notion2api
```

重启服务：

```bash
docker compose restart notion2api
```

重新构建：

```bash
docker compose up -d --build
```

停止服务：

```bash
docker compose down
```

## 目录说明

```text
/opt/notion2api/
├── config/
│   ├── config.json
│   └── install-credentials.txt
├── data/
│   ├── notion2api.sqlite
│   └── notion_accounts/
├── docker-compose.yml
└── install.sh
```

`config/` 和 `data/` 包含敏感信息及运行数据，不应上传、分享或提交到版本库。

## 安全建议

- 首次登录后立即确认 API Key 和管理密码强度
- 不要公开 Cookie、`token_v2`、Probe JSON 或 `storage_state.json`
- 不建议将 `8787` 端口直接暴露给所有公网地址
- 公网使用时应配置防火墙、HTTPS 反向代理和访问控制
- 定期备份 `config/` 与 `data/`，备份文件同样需要加密保护
- 如果密钥曾出现在聊天、日志或 Git 历史中，应立即轮换

## 注意事项

本项目是非官方兼容桥接工具，与 Notion、OpenAI、Anthropic、Google 或其他模型厂商无隶属关系。请遵守相关服务条款、账号权限和当地法律法规。上游接口变化可能导致模型暂时不可用。

## 上游与许可

- 上游项目：[GALIAIS/Notion2API](https://github.com/GALIAIS/Notion2API)
- 定制版本：[Twddhcm/Notion2API](https://github.com/Twddhcm/Notion2API)
- 发布版本：[v1.0.8-neutral.3](https://github.com/Twddhcm/Notion2API/releases/tag/v1.0.8-neutral.3)
- 许可证：[MIT](LICENSE)
