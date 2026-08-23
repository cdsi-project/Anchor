<p align="center">
  <img src="assets/brand/anchor-lockup.png" alt="CDSI Anchor：个人数字主权，从一个脚本开始。" width="720">
</p>

# CDSI Anchor

**Creator Digital Sovereignty Infrastructure**<br>
**创作者数字主权基础设施**<br>
**个人数字主权，从一个脚本开始。**

> **Your Domain. Your Content. Your Data. Your Audience.**  
> **你的域名，你的内容，你的数据，你的用户关系。**

## 中文简介

**CDSI（Creator Digital Sovereignty Infrastructure，创作者数字主权基础设施）**是一套面向创作者的开放数字基础设施。

它不是为了再建立一个内容平台，而是帮助创作者在开放 Web 上建立一个由自己控制的独立数字节点，用来长期保存和管理自己的：

- 数字身份
- 文章
- 观点
- 视频
- 播客
- 创作资产
- 数据
- 用户关系
- 产品与服务入口

CDSI 的核心原则是：

> **平台负责分发，创作者负责拥有。**

以及：

> **流量可以借，资产必须留下。**

长期来看，CDSI 希望让每一个创作者都能够拥有自己的数字原点，而不是把全部数字存在建立在第三方平台之上。

> **完整的安装步骤、菜单说明、域名/SSL 配置、常见问题排错，请阅读 [使用说明/INSTALL](INSTALL.md)。**

Anchor 的产品定位、当前边界和已知限制见 [CDSI-Anchor](CDSI-Anchor.md)。

---

CDSI is an open-source infrastructure project for creators who want to own and control their digital identity, content, data, and audience relationships.

CDSI does **not** aim to build another centralized content platform.

Its goal is to help every creator build and operate an independent digital node on the open Web.

---

## Why CDSI?

Creators produce enormous amounts of digital value:

- articles
- videos
- podcasts
- ideas
- research
- images
- projects
- products
- audience relationships

But much of that value is stored inside third-party platforms.

The creator may own the copyright, while the platform still controls discovery, distribution, reach, account access, user relationships, outbound links, and data portability.

> **Creators create the assets, but platforms often control how those assets exist, connect, and reach people.**

CDSI exists to reduce that dependency.

---

## Core Idea

CDSI follows a simple principle:

> **Own first. Distribute everywhere.**

Platforms remain valuable distribution channels. CDSI does not ask creators to leave platforms.

```text
Creator
   │
   ▼
CDSI Node
   │
   ├── Identity
   ├── Content
   ├── Assets
   ├── Audience
   ├── Data
   └── Actions
   │
   ▼
Distribution
   │
   ├── Douyin
   ├── Zhihu
   ├── Weibo
   ├── Xiaohongshu
   ├── YouTube
   └── Other Platforms
```

The platform distributes.

The creator owns the origin.

---

## What is a CDSI Node?

A **CDSI Node** is an independent digital home controlled by the creator.

A mature node may contain:

```text
Creator
│
├── Identity
│   ├── Profile
│   ├── Domain
│   └── Verified Accounts
│
├── Assets
│   ├── Articles
│   ├── Notes
│   ├── Videos
│   ├── Podcasts
│   ├── Images
│   ├── Research
│   └── Projects
│
├── Audience
│   ├── Subscribers
│   ├── Members
│   └── Relationships
│
├── Distribution
│   ├── Platform Links
│   ├── Syndication Records
│   └── Feeds
│
├── Data
│   ├── Database
│   ├── Media
│   ├── Metadata
│   └── Backups
│
└── Action
    ├── Products
    ├── Services
    ├── Subscriptions
    ├── APIs
    └── Agent Interfaces
```

The long-term goal is for a CDSI Node to become a creator's **Digital Headquarters**.

---

## Project Principles

### 1. Creator Ownership First

Creators should control their domain, database, media files, content, configuration, audience relationships, and backups.

CDSI must not become another source of platform lock-in.

### 2. Self-Hosted First

Self-hosting is a first-class deployment model.

Managed hosting may exist later, but the open-source version must remain independently deployable.

### 3. Exportable by Default

Core data should remain portable.

Preferred formats include:

- Markdown
- JSON
- CSV
- RSS / XML
- standard media files
- database backups

Data portability is not an optional feature. It is part of the project constitution.

### 4. Open Web First

Prefer established open Web standards and protocols.

Examples:

- HTTP / HTTPS
- RSS
- Sitemap
- Schema.org
- JSON
- Markdown

Future integrations may include ActivityPub, Webmention, AI-readable interfaces, and Agent-callable interfaces.

### 5. Replaceable by Design

CDSI itself should be replaceable.

A creator should eventually be able to migrate away from CDSI without losing their digital assets.

> **Software can be replaced. Creator assets must survive.**

---

## Current Status

CDSI Anchor is currently in **M0 integration and hardening**. The installer
version is **0.3.0**.

The primary path now provisions a WordPress OpenWeb node on supported Ubuntu
Server and CentOS Stream releases:

| Status | Scope |
| --- | --- |
| Implemented in `install.sh` | Preflight, Nginx, MySQL, PHP-FPM, Certbot, WordPress, domain/HTTPS configuration, final service/access report, and component uninstall |
| Implemented support | Ubuntu APT and CentOS DNF/systemd routes, bounded package retries, strict domain DNS activation, pinned SHA-256 verification for CDN downloads, and a Beacon WordPress Application Password |
| Standalone only | Redis and Supervisor scripts remain available, but are hidden from the main menu and Install All flow |
| Planned | Composer/CDSI Core deployment, the `cdsi` CLI, `cdsi doctor`, resume/update workflows, and complete server backup/restore |

The supported fresh-install runtime is deliberately narrow:

```text
OS           Ubuntu Server 24.04/26.04 LTS or CentOS Stream 10
Web          Nginx from the operating system's default source
Runtime      PHP-FPM from the operating system's default source
Database     MySQL (mysql-server on Ubuntu, mysql8.4-server on CentOS)
SSL          Let's Encrypt / Certbot for a verified domain; explicit IP HTTPS when supported
OpenWeb      WordPress
Integration  CDSI Beacon WordPress Application Password
```

### Current Priority

The project is currently focused on:

- clean-server regression testing on every supported OS route
- safe reruns after partial installation
- DNS, certificate, package-lock, and network failure recovery
- uninstall safety and upgrade compatibility
- replacing the placeholder health check with real end-to-end validation

### Not Yet the Focus

The following are planned and should not be considered implemented by Anchor:

- CDSI Core application deployment
- Composer management
- `cdsi install`, `cdsi status`, `cdsi doctor`, and `cdsi update`
- server-side CDSI API/data synchronization
- complete automated server backup and restore
- Redis or Supervisor in the default installation flow
- article management
- video asset management
- podcast publishing
- newsletter
- membership
- CRM
- creator analytics
- AI features
- ActivityPub
- mobile apps
- Agent interfaces

---

## 安装前准备

Anchor 当前支持 **Ubuntu Server 24.04/26.04 LTS** 和
**CentOS Stream 10**。Debian 目录仅保留扩展边界，尚未实现安装支持。

### 必需

1. **一台干净的受支持 Linux 服务器**
   - 支持 `x86_64` 和 `aarch64` 架构
   - 最低 1 核 CPU、1 GB 内存和 10 GB 根分区可用空间；推荐 2 GB 内存和
     20 GB 根分区可用空间
   - 登录用户需要 root 或 sudo 权限
   - 系统使用 systemd，以及 Ubuntu APT 或 CentOS DNF 默认软件源
   - 需要使用 `git` 获取 Anchor 源码；CentOS Stream 10 默认未安装 Git，
     请先运行 `sudo dnf install -y git`
2. **稳定的公网入口和网络连接**
   - 准备公网 IP
   - 防火墙开放 80 端口和实际使用的 SSH 管理端口；启用 HTTPS 时再确保
     443 端口开放。
3. **交互式 SSH 终端**
   - `install.sh` 使用交互菜单，不能通过无 TTY 的后台任务或管道运行。

### 使用域名和 CDSI Beacon 时必需

4. **一个能够管理 DNS 的域名**
   - 使用裸域名，例如 `cdsi.com`，不要包含 `https://`、端口或路径。
   - 所有 DNS A 记录都必须指向服务器公网 IPv4；如果存在 AAAA 记录，也必须
     指向当前服务器实际配置的公网 IPv6。
   - 等待 DNS 生效，并确保公网能够访问 80 端口，供 Let's Encrypt HTTP-01
     验证使用。

没有域名也可以安装。默认网站地址为 `http://<服务器公网 IP>`，WordPress 和
Beacon Application Password 仍会创建。输入的域名只有在 A/AAAA 解析严格匹配
本机后才会生效；未就绪的域名保存在 `config/domain.pending`，不会改动当前
WordPress URL 或 Nginx 站点。

公网 IP 也可以显式申请公信 HTTPS，但必须是公网 IPv4，且系统提供的 Certbot
必须为 5.4 或更高版本并支持 Let's Encrypt `shortlived` profile。能力不足时
Anchor 保持现有 HTTP 站点，不会安装不受信任证书，也不承诺 CentOS Stream
当前系统包一定满足该版本要求。公网 IP 探测受限时可显式传入
`CDSI_SERVER_IP`。

### 建议

- 优先使用干净、专用的服务器，不要与已有生产网站、数据库或共享运行时混用。
- Ubuntu 安装前移除 nginx.org、Ondrej PHP/Nginx PPA 等冲突源；Anchor 不会
  静默改写这些软件源。CentOS 基础栈使用 BaseOS/AppStream，并会在需要
  Certbot 或可选 Imagick 时从 CentOS Extras 安装 `epel-release`。
- 如果服务器已有业务数据或配置，先创建云盘快照，并备份 Nginx、PHP、MySQL
  和 WordPress 数据。
- 长时间安装可在 `tmux` 或 `screen` 会话中执行，避免 SSH 中断影响交互流程。

---

## Installation Experience

The current entry point is:

CentOS Stream 10 需要先通过系统默认源安装 Git：

```bash
sudo dnf install -y git
```

国内服务器建议使用 Gitee（码云）镜像：

```bash
git clone https://gitee.com/cdsi/anchor.git Anchor
```

也可以使用 GitHub：

```bash
git clone https://github.com/cdsi-project/Anchor.git Anchor
```

克隆完成后运行：

```bash
cd Anchor
sudo ./install.sh
```

The goal is to reduce infrastructure complexity so that owning an independent digital node does not require deep knowledge of Linux, Nginx, PHP, MySQL, SSL, or deployment.

> The infrastructure should be complex underneath, but simple for the creator.

### Anchor Script Entry Points

`install.sh` is the primary entry point and coordinates scripts under `scripts/`:

```bash
sudo ./install.sh
```

Each script under `scripts/` can also be run independently for focused operation or diagnosis:

```bash
bash scripts/check-env.sh
sudo bash scripts/configure.sh
sudo bash scripts/configure-domain.sh example.com
sudo bash scripts/configure-domain.sh --clear
sudo bash scripts/configure-https.sh example.com
sudo bash scripts/configure-https.sh --ip
bash scripts/health.sh
sudo bash scripts/install-nginx.sh
sudo bash scripts/install-mysql.sh
sudo bash scripts/install-php.sh
sudo bash scripts/install-certbot.sh
sudo bash scripts/install-wordpress.sh
```

这些公开脚本会先检测操作系统，再路由到对应平台目录。
`scripts/ubuntu/` 与 `scripts/centos-stream/` 已实现，并复用
`scripts/common/` 中的组件实现；`scripts/debian/` 仍会在修改系统前明确返回
“不支持”。Redis 与 Supervisor 独立脚本目前仅支持 Ubuntu。

`check-env.sh` is the active preflight implementation. `configure.sh` is a
standalone `/etc/cdsi` configuration helper that is not yet called by the main
install flow. `health.sh` remains a visible placeholder for the future
`cdsi doctor` workflow.

`configure-domain.sh` and `configure-https.sh` are implemented standalone
operations. Domain activation requires every A record, and every present AAAA
record, to resolve only to this server. A failed check records
`config/domain.pending` and leaves the current site unchanged. Without an
active domain, installation stays at `http://<public IP>` until HTTPS is
explicitly requested with `configure-https.sh --ip` and the local Certbot has
the required IP-certificate capability.

The HTTPS path uses Let's Encrypt by default. An operator may set
`CDSI_ACME_FALLBACK_SERVER` for a secondary ACME directory; it is selected only
when the primary directory itself is unreachable after bounded network probes.
DNS, CAA, authorization, certificate-validation, and rate-limit failures never
trigger an automatic CA switch. ZeroSSL additionally requires
`CDSI_ACME_FALLBACK_EAB_KID` and `CDSI_ACME_FALLBACK_EAB_HMAC_KEY`.

Nginx, MySQL, and PHP-FPM installers verify both the active runtime state and
systemd boot enablement. When HTTPS is configured, the available
`certbot.timer` or `certbot-renew.timer` must likewise be active and enabled.

The PHP installer uses each supported operating system's default PHP stream. It
does not add a PHP PPA/Remi repository or replace an existing global PHP
alternative. A fresh installation provisions Redis, ZIP, GD, and OPcache;
Imagick is optional and uses the system package on Ubuntu or EPEL on CentOS.
The fast path verifies PHP-FPM and the complete required extension set before it
skips reconciliation.

---

## Repository Structure

Current structure:

```text
Anchor/
├── AGENTS.md
├── README.md
├── INSTALL.md
├── CDSI-Anchor.md
├── CDSI_MANIFESTO_ZH_EN.md
├── install.sh
├── uninstall.sh
├── SHA256SUMS
├── config/
│   ├── domain            # 已验证且已生效的域名（本机生成）
│   └── domain.pending    # DNS 未就绪的候选域名（本机生成）
├── lib/                  # 平台、DNS、APT/DNF、systemd 与公共工具
├── scripts/
│   ├── dispatch.sh       # 操作系统检测与路由
│   ├── check-env.sh      # 可独立运行的公开入口
│   ├── configure-domain.sh
│   ├── configure-https.sh
│   ├── install-*.sh      # 可独立运行的公开入口
│   ├── common/           # 共享组件实现
│   ├── ubuntu/           # 已实现的平台路由
│   ├── debian/           # 规划边界，尚未实现
│   └── centos-stream/    # 已实现的平台路由
├── templates/
├── tests/
├── docs/
└── password/             # generated locally and ignored by Git
```

`install.sh` is the orchestration entry point. Scripts under `scripts/` must
remain independently runnable and communicate success or failure through their
exit code. `AGENTS.md` defines repository engineering rules; older documents
under `docs/` are retained as design history and are labeled accordingly.

---

## Roadmap

### M0 — Node Anchor

**In progress.** The five-component WordPress OpenWeb installation path is
implemented. Current work is integration testing, failure recovery, upgrade and
uninstall safety, and real health checks.

Goal:

> One command to turn a clean server into a running CDSI Node.

### M1 — Creator Identity

Planned direction:

- profile
- domain identity
- social account references
- creator metadata
- public identity page

### M2 — Creator Assets

Planned direction:

- articles
- notes
- videos
- podcasts
- images
- projects
- permanent asset URLs
- metadata
- export

### M3 — Audience & Subscription

Planned direction:

- RSS
- email subscription
- member accounts
- direct audience relationships

### M4 — Distribution

Planned direction:

- platform distribution records
- syndication metadata
- canonical source management
- search-friendly output

### M5 — Machine-Readable Web

Planned direction:

- structured data
- APIs
- AI-readable content
- Agent-callable actions
- open protocol integrations

The roadmap is intentionally evolutionary. Scope may change as real creator needs are validated.

---

## What CDSI Is Not

CDSI is **not**:

- another centralized creator platform
- a closed SaaS that owns creator data
- just a personal homepage generator
- just a blogging CMS
- an attempt to replace every social platform
- a requirement that creators abandon existing distribution channels

CDSI is infrastructure for ownership.

---

## Philosophy

The Internet may continue to be dominated by large platforms.

AI may become a major discovery interface.

Agents may become a major action interface.

CDSI is built around a longer-term view:

> **The Web provides existence.  
> Platforms provide distribution.  
> AI provides understanding.  
> Agents provide action.**

Creators should still retain an independent digital origin inside that system.

---

## For Contributors

Before modifying the repository:

1. Read `AGENTS.md`.
2. Inspect the current milestone.
3. Keep changes scoped.
4. Prefer simple, explicit, testable implementations.
5. Avoid premature abstraction.
6. Preserve self-hosting and portability.
7. Do not introduce unnecessary lock-in.
8. Do not claim planned features are implemented.

The current engineering priority is M0 unless the project roadmap explicitly changes.

---

## Project Constitution

CDSI exists to reduce creator dependence on closed digital infrastructure.

Therefore CDSI itself must not become another unnecessary source of dependence.

The system should remain:

```text
Open
Self-hostable
Portable
Exportable
Replaceable
Interoperable
```

When choosing between:

```text
more features
```

and:

```text
more ownership
more portability
more reliability
less lock-in
```

CDSI should prefer the latter.

---

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

---

## Status

**M0 integration and hardening / Anchor Installer v0.3.0**

CDSI is under active development and is not yet ready for production use.
