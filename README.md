---
created: 2026-06-02 17:01:09 +0800
summary: 深圳 AI 航海家大课一键安装与课前检测脚本说明
last_change: 2026-09-04 — 按最新对外预习手册补齐课前文件、数据包和人工自检口径
---

# 深圳 AI 航海家大课 · 一键安装与课前检测助手

> 制作者：[xitangwang](https://github.com/xitangwang)  
> 使用场景：深圳 AI 航海家大课

这是面向零基础学员的一键部署项目。按 2026-09-04 最新对外预习手册，深圳课程软件必装项是 Codex 和飞书桌面版；飞书 CLI、官方 Agent Skills、Hermes、Obsidian 继续保留为可选增强，不影响“自动环境检查已就绪”的最终判定。

本项目负责安装流程、环境检测和中文提示；各软件本体均来自对应厂商的官方安装源。

“安装完成”只代表命令可以执行，不代表账号已经登录。脚本会把安装检查和登录授权分开提示。

只检测模式还会检查 Google / GitHub 网络、至少 10GB 可用空间、“我的跨境Agent大课”五个文件夹、课前四份文件和解压后的课程 ABA 数据包。最终结果同时显示在终端和系统中文弹窗中。

## 一句话用法

### Mac

打开「终端」App，粘贴：

```bash
curl -fsSL https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/install.sh | bash
```

只检测、不安装：

```bash
curl -fsSL https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/install.sh | bash -s -- --check
```

### Windows

按 `Win + R`，粘贴下面这一整行并回车：

```cmd
cmd /k powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/go.ps1 | iex"
```

`cmd /k` 会保留外层窗口：即使 PowerShell 或安装脚本异常退出，错误信息也不会跟着闪退消失。启动器还会在桌面自动生成 `navigator-installer-日期时间.log` 诊断日志；安装失败时会等待按回车后再关闭。

如果已经打开了 Windows PowerShell 或 Windows Terminal，也可以继续使用原命令：

```powershell
irm https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/go.ps1 | iex
```

只检测、不安装：

```cmd
cmd /k powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:CHECK_ONLY=1; irm https://raw.githubusercontent.com/xitangwang/mac-onboarding-setup/main/go.ps1 | iex"
```

交互提示中：回车表示继续，`s` 表示跳过，`q` 表示退出。安装后建议重开终端再验证。

### 实时进度说明

- Mac 下载 Node.js、飞书桌面版、Obsidian、ChatGPT 和 Hermes 桌面安装包时，会显示实时百分比，并在结束时显示总耗时。
- Windows 的 Node.js、飞书桌面版、Obsidian 和 Microsoft Store 安装会显示 winget 原生下载 / 安装进度，并持续显示已用时间。
- Windows 直接下载 Codex 辅助程序或 Hermes 桌面安装包时，如果下载源提供总大小，会显示已下载大小、总大小、百分比和耗时；否则显示已下载大小和耗时。
- Codex、Hermes、飞书 CLI 等官方安装器如果没有提供总工作量，脚本不会伪造百分比，而是保留官方实时输出并显示当前阶段和总耗时。
- 如果安装过程中出现 UAC 权限确认窗口，需要手动点击允许；终端会持续提示查看 UAC。

## 设备兼容范围

| 设备 | 支持情况 |
|---|---|
| Apple Silicon Mac，macOS 14+ | Codex、飞书桌面版、飞书 CLI 和新版 ChatGPT App 均可走官方安装路径；Hermes 可选 |
| Apple Silicon Mac，macOS 12～13 | CLI 工具可安装；新版 Codex / ChatGPT 桌面 App 不支持 |
| Apple Silicon Mac，macOS 11 | Node 22 和飞书 CLI 可用；Hermes 与新版桌面 App 会明确跳过，Codex CLI 由官方安装器判断 |
| Intel Mac | Codex、飞书桌面版和飞书 CLI 可安装；macOS 14+ 可用新版 ChatGPT App；Hermes 官方不支持，会被脚本跳过 |
| Windows 10/11 x64 | 支持 Codex、飞书桌面版、飞书 CLI；Hermes、Obsidian 为可选 |
| Windows ARM64 | 支持原生 ARM64；脚本通过 CIM 识别真实架构，并强制 Node/Codex 使用 ARM64 包 |
| 32 位 Windows 或 Windows 10 以前版本 | 当前主力 CLI 不支持，脚本会停止并说明原因 |

## 安装内容与方式

| 工具 | 安装方式 | 安装成功判定 |
|---|---|---|
| Codex | OpenAI 官方脚本 | `codex --version` 成功且有版本文本；Windows 还需 sandbox 辅助程序就绪 |
| 飞书桌面版 | Mac 读取飞书官网当前芯片安装包；Windows 使用 winget `ByteDance.Feishu` | 实际检测到应用或官方包 |
| 飞书 CLI（可选） | 官方 `npx @larksuite/cli@latest install` | `lark-cli --version` 成功，同时存在官方 Agent Skills |
| Node.js（可选依赖） | 选择飞书 CLI 时按需安装；Mac 使用 Node 22 LTS 官方包并核对 SHA-256，Windows 使用 winget LTS | `node --version` 和 `npm --version` 都成功 |
| Hermes（可选） | Nous Research 官方脚本；Windows 依赖由安装器放在用户目录 | `hermes --version` 成功且有版本文本 |
| Obsidian（可选） | Mac 自动读取当前 GitHub DMG；Windows 使用 winget | 实际检测到应用或 winget 包 |
| ChatGPT 桌面 App（内含 Codex） | Mac 自动下载并安装官方 ChatGPT 桌面 App（内含 Codex）；Windows 使用 Microsoft Store | Mac 校验 DMG、OpenAI 代码签名、Bundle ID 和芯片架构后再复制安装 |

脚本不会因为 PATH 中存在一个同名但损坏的命令就显示成功。每个版本命令默认最多等待 8 秒；无响应时会标记为异常并继续检查其他项目。

## 深圳课程“已就绪”判定

以下项目全部通过才返回成功状态：支持的系统架构、Codex（Windows 包含 sandbox 辅助程序）、飞书桌面版、Google / GitHub 网络、至少 10GB 可用空间、五个课程文件夹、四份非空课前文件（人格档案、AI 协作说明、我的业务说明书、方向清单），以及 `03-数据包` 中不少于约 2GB 的已解压课程数据。只有 ZIP 压缩包不会标记为通过。

飞书 CLI、Agent Skills、Node.js、Hermes 和 Obsidian 不参与官方深圳课程自动就绪判定；安装失败会列在“可选工具未完成”，不会误报为必需项失败。

### 必须本人确认的项目

脚本不能可靠代替真人检查以下事项，因此只给出清单和官方入口，不会伪造“已通过”：

- Google 账号可用；ChatGPT Plus / Pro 已就绪，Codex 能连续对话 5 轮。
- 卖家精灵已在官方入口注册，并在自检表填写同一注册邮箱；MCP 等课程统一带装。
- 跨境适配度测试已提交，裸问回答和课前作业三件套已提交。
- 自带网口或转换器已经用网线测试；手机热点可以作为备用网络。

官方入口：

- [课前预习手册](https://shengcaiyoushu01.feishu.cn/wiki/Rtrjwqp2Mi59I1kdtUfcRyebn6b)
- [课前自检清单](https://scys.com/form/z27Vz6Fl)
- [卖家精灵注册](https://open.sellersprite.com/mcp)

## 登录与授权

- Codex：安装后按提示手动运行 `codex login`；无浏览器环境可使用 `codex login --device-auth`。
- 飞书 CLI（可选增强）：先运行初始化，再进入扫码或浏览器授权。两步分别检查返回码，取消或失败只进入可选工具清单。
- Hermes：本脚本只安装本体和环境；模型/provider 后续按 Hermes 官方文档配置。

只检测模式和最终版本检查不会判断账号是否已经登录。

## 错误提示说明

脚本会尽量保留官方安装器的原始输出，并区分以下情况：

- 下载源、DNS、超时或代理认证失败。
- 系统版本或 CPU 架构不支持。
- 目录权限、PowerShell 执行策略、UAC 或公司设备策略。
- Microsoft Store / winget 不可用或被禁用。
- 磁盘空间不足、安装包校验失败或文件不完整。
- 命令文件存在，但 `--version` 实际执行失败。
- 命令执行超过 8 秒无响应。
- 飞书初始化失败、登录取消或授权失败。

如果流程末尾仍有必需项失败，脚本会显示“不能标记为全部就绪”，并设置非零状态；不会再把所有失败都写成“多半是网络”。

## 常见处理

### Mac 上可选的 Node 或飞书 CLI 安装失败

脚本固定选择兼容 macOS 11+ 的 Node 22 LTS，并校验官方 SHA-256。如果仍失败，查看上方提示属于下载、校验、权限还是磁盘问题；也可手动安装 Node 22 LTS 后重开终端再运行。

### Windows 上 winget 返回非零代码

检查 Microsoft Store 的「应用安装程序」、公司策略、UAC 弹窗、代理和杀毒软件。Windows ARM64 应在检测信息中显示 `ARM64`；如果显示错误，请保留完整截图。

### Intel Mac 没有安装 Hermes

这是官方支持范围限制，不是网络错误。脚本会继续安装该机器受支持的 Codex、飞书 CLI 和 Obsidian。

### 命令存在但仍显示损坏

脚本实际执行了 `--version`。如果失败，常见原因是旧安装残留、架构不匹配、文件被杀毒软件隔离或依赖文件缺失；重新运行脚本会尝试覆盖修复。

## 项目文件

- `install.sh`：Mac 主安装器。
- `install.ps1`：Windows 主安装器。
- `go.ps1`：Windows ASCII/UTF-8 启动器，负责 TLS、下载内容校验和异常提示。
- `tests/test_installers.sh`：可重复运行的安装器回归测试。
- `tests/test_install_ps1.ps1`：Windows 运行时超时和课程就绪规则测试。
- `docs/superpowers/plans/`：本轮可靠性修复的实施计划。
- `README.md`：本说明。

## 维护与验证

本地修改后至少运行：

```bash
bash tests/test_installers.sh
bash -n install.sh
bash install.sh --check
pwsh -NoProfile -File tests/test_install_ps1.ps1
```

本次发布已在 Windows 11 x64 完成只检测实测；Windows 10 x64、Windows ARM64、Apple Silicon Mac 与 Intel Mac 仍待对应真机复核，未验机的平台请先按测试版使用并保留完整日志。

入口与来源：

- Codex：<https://github.com/openai/codex>
- Hermes：<https://hermes-agent.nousresearch.com/docs/>
- 飞书 CLI：<https://github.com/larksuite/cli>
- 飞书桌面版：<https://www.feishu.cn/download>
- Obsidian：<https://obsidian.md/download>

`go.ps1`、`install.sh` 和各官方安装入口仍属于联网下载并执行代码。发布时应保护主分支写权限；Node 二进制已经增加 SHA-256 校验，其他上游官方安装脚本由对应厂商维护。
