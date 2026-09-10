<p align="center">
  <img src="assets/brand/anchor-lockup.png" alt="CDSI Anchor：个人数字主权，从一个脚本开始。" width="720">
</p>

# CDSI Anchor

**创作者数字主权基础设施**<br>
**Creator Digital Sovereignty Infrastructure**<br>

[中文](#中文) | [English](#english)

## 中文

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

> **创作者负责拥有，平台只负责渠道分发**

长期来看，CDSI 希望让每一个创作者都能够拥有自己的数字原点，而不是把全部数字存在建立在第三方平台之上。

> **完整安装步骤，请阅读 [使用说明/INSTALL](INSTALL.md)。**

Anchor 的产品定位、当前边界和已知限制见 [CDSI-Anchor](CDSI-Anchor.md)。

---

## 安装前准备

Anchor 当前支持 **Ubuntu Server 24.04/26.04 LTS**、**Debian 13**、
**CentOS Stream 10** 和 **openSUSE Leap 16.0**。

### 必需

1. **一台干净的受支持 Linux 服务器**
   - 支持 `x86_64` 和 `aarch64` 架构
   - 安装脚本要求至少 1 核 CPU；预检以 1GB 内存和 10GB 根分区可用空间作为
     警告阈值，低于阈值时会提示但允许继续
   - 建议至少 2GB 内存，正式环境推荐 4GB 内存和 20GB 根分区可用空间
   - 登录用户需要 root 或 sudo 权限
2. **稳定的公网入口和网络连接**
   - 准备公网 IP
   - 防火墙开放 80、443 端口
3. **交互式 SSH 终端**
   - Xshell
   - GitBash
   - PowerShell
没有域名也可以安装。Anchor 会先完成基础服务和 WordPress，再把域名与 HTTPS
作为最后一个可选步骤；直接按 Enter 即可跳过。默认网站地址为
`http://<服务器公网 IP>`，WordPress 和 Beacon Application Password 仍会创建。
输入的域名只有在 A/AAAA 解析严格匹配本机后才会生效；未就绪的域名保存在
`config/domain.pending`，不会改动当前 WordPress URL 或 Nginx 站点，也不会让
已经完成的基础安装失败。

公网 IP 也可以显式申请公信 HTTPS，但必须是公网 IPv4，且系统提供的 Certbot
必须为 5.4 或更高版本并支持 Let's Encrypt `shortlived` profile。能力不足时
Anchor 保持现有 HTTP 站点，不会安装不受信任证书，也不承诺 CentOS Stream
当前系统包一定满足该版本要求。Debian 13 默认源提供的 Certbot 4.0、openSUSE
Leap 16.0 默认源提供的 Certbot 5.1 均支持域名 HTTPS，但不满足 IP 证书所需的
Certbot 5.4+ 能力。公网 IP 探测受限时可显式传入 `CDSI_SERVER_IP`。

### 建议

- 优先使用干净、专用的服务器，不要与已有生产网站、数据库或共享运行时混用。
- 如果服务器已有业务数据或配置，也可单独安装 Anchor 组件。
- 长时间安装可在 `tmux` 或 `screen` 会话中执行，避免 SSH 中断影响交互流程。

---

## 安装体验

### Agent Skill MVP（实验性）

仓库提供 `$anchor-install-server` Skill。用户只需提供一台干净、专用的受支持
Linux 服务器及 root SSH 登录方式，Agent 会完成环境检查、固定版本引导、基础
组件安装、独立验收和结果交付。没有域名不会阻塞安装，最终先提供 IP HTTP 站点。

#### 1. 获取 Anchor 并打开仓库

```bash
git clone https://gitee.com/cdsi/anchor.git
cd anchor
```

使用支持仓库级 Agent Skills 的 Codex 打开该目录。Skill 位于
`.agents/skills/anchor-install-server`，无需单独执行其中的文件。也可以将该
目录复制到用户级 `~/.agents/skills/`，在其他项目中调用。其他 Agent 需要兼容
Agent Skills，并具备本地 SSH 和终端执行能力。

#### 2. 准备 root SSH 登录

推荐预先配置公钥，并先确认本机能够连接：

```bash
ssh root@SERVER_IP
```

可以把本机私钥的文件路径告诉 Agent，但不要在聊天中粘贴私钥正文、root 密码
或密钥口令。密码或口令只能由用户在自己控制的安全终端提示中输入；如果当前
Agent 环境不支持安全输入，应改用公钥登录。

#### 3. 调用 Skill

```text
$anchor-install-server

请在 SERVER_IP 上安装 Anchor。
SSH 用户：root
SSH 端口：22
认证密钥：本机已有的私钥文件路径
这是一台我拥有并授权安装的全新专用服务器。
暂时没有域名，先通过 IP 完成安装。
```

Agent 会先确认 SSH 主机指纹并执行只读检查，再安装 Nginx、MySQL/MariaDB、
PHP-FPM 和 WordPress，最后验证服务启动、开机启用、WordPress 数据库连接及
客户端侧公网访问。发现已有网站、数据库、证书、80/443 端口占用或不明确状态
时会停止；追加一句“继续”也不会绕过干净服务器门禁。

#### 4. 查看登录凭据

安装结果会返回网站地址、WordPress 后台地址和验收状态。为了避免密码进入
Agent 记录，凭据值保留在服务器中，由用户在自己的 root SSH 终端查看：

```bash
cat /root/cdsi-Anchor/password/wordpress.pass
cat /root/cdsi-Anchor/password/wordpress-beacon.pass
```

没有有效 HTTPS 时不要通过公网提交这些凭据。域名解析生效后，可以继续调用
Skill 所在的 Agent：

```text
请为刚安装的 Anchor 节点配置域名 example.com 和 HTTPS。
```

Skill 会单独确认域名与证书授权；DNS 或证书暂时不可用不会推翻已完成的基础
安装。完整支持范围、人工安装方式和故障处理见 [完整安装指南](INSTALL.md)。

### 新服务器快速启动

国内服务器使用 Gitee 下载远程引导脚本：

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://gitee.com/cdsi/anchor/raw/v0.3.5/bootstrap.sh \
  -o anchor-bootstrap.sh && sh anchor-bootstrap.sh
```

只有 `wget` 时：

```bash
wget -qO anchor-bootstrap.sh \
  https://gitee.com/cdsi/anchor/raw/v0.3.5/bootstrap.sh && \
  sh anchor-bootstrap.sh
```

脚本会自动完成以下步骤：

1. 检查操作系统、CPU 架构、systemd、root/sudo 权限和交互终端。
2. 刷新当前系统默认 APT/DNF/Zypper 仓库的元数据，不改写软件源、不执行全系统升级。
3. 安装 `bash`、Git、curl、CA 证书和 coreutils。
4. 自动进入 `install.sh` 的交互菜单。

Anchor 默认保存到 `/root/cdsi-Anchor`。保存前会检查目标路径；同名普通文件、
非 Git 目录或符号链接均不会被覆盖。已有目录只有在确认是 bootstrap 管理、
来源可信且工作区干净的 Anchor 仓库后，才会以 fast-forward 方式更新。

脚本下载到本地后再执行，因此用户可以先检查内容；非 root 用户执行时会通过
`sudo` 请求权限。远程可执行脚本只通过 HTTPS 分发，不提供 HTTP 入口。

GitHub 下载入口：

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/cdsi-project/Anchor/v0.3.5/bootstrap.sh \
  -o anchor-bootstrap.sh && sh anchor-bootstrap.sh
```

只准备环境和代码、不立即进入安装菜单：

```bash
sh anchor-bootstrap.sh --no-start
```

### 手动安装

已有 Git 时仍可手动克隆。国内服务器建议使用 Gitee：

```bash
git clone https://gitee.com/cdsi/anchor.git Anchor
cd Anchor
sudo ./install.sh
```

也可以使用 GitHub：

```bash
git clone https://github.com/cdsi-project/Anchor.git Anchor
cd Anchor
sudo ./install.sh
```

---

## English

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
version is **0.3.5**.

The primary path now provisions a WordPress OpenWeb node on supported versions
of Ubuntu Server, Debian, CentOS Stream, and openSUSE Leap:

| Status | Scope |
| --- | --- |
| Implemented in `install.sh` | Preflight, the required Nginx/MySQL-or-MariaDB/PHP-FPM/WordPress stack, optional final domain/HTTPS and Certbot setup, final service/access report, and component uninstall |
| Implemented support | Ubuntu/Debian APT, CentOS DNF, and openSUSE Zypper/systemd routes, bounded package retries, strict domain DNS activation, pinned SHA-256 verification for CDN downloads, and a Beacon WordPress Application Password |
| Standalone only | Redis and Supervisor scripts remain available, but are hidden from the main menu and Install All flow |
| Experimental | Repository-scoped `$anchor-install-server` Skill for installing the base node on one clean, dedicated server over root SSH |
| Planned | Composer/CDSI Core deployment, the `cdsi` CLI, `cdsi doctor`, resume/update workflows, and complete server backup/restore |

The supported fresh-install runtime is deliberately narrow:

```text
OS           Ubuntu Server 24.04/26.04 LTS, Debian 13, CentOS Stream 10, or openSUSE Leap 16.0
Web          Nginx from the operating system's default source
Runtime      PHP-FPM from the operating system's default source (PHP 8.4 on Debian 13/openSUSE Leap 16.0)
Database     MySQL on Ubuntu/CentOS; MariaDB 11.8 on Debian 13/openSUSE Leap 16.0
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

## Installation Experience

The goal is to reduce infrastructure complexity so that owning an independent digital node does not require deep knowledge of Linux, Nginx, PHP, MySQL/MariaDB, SSL, or deployment.

> The infrastructure should be complex underneath, but simple for the creator.

### Anchor Script Entry Points

`install.sh` is the primary entry point and coordinates scripts under `scripts/`:

```bash
sudo ./install.sh
```

When **Install All** is selected, Anchor installs Nginx, MySQL/MariaDB,
PHP-FPM, and WordPress before asking for a domain. Pressing Enter or reaching
EOF skips domain and HTTPS configuration, preserves the existing active and
pending state, and still prints the site and credential report. A supplied
domain uses the shared `configure-https.sh DOMAIN` flow. Temporary DNS or
certificate failures defer only the optional step and do not undo the completed
base installation. Enter `ip` to explicitly attempt public-IP HTTPS.

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

These public scripts detect the operating system before routing to the matching
platform directory. The implemented `scripts/ubuntu/`, `scripts/debian/`,
`scripts/centos-stream/`, and `scripts/opensuse-leap/` routes reuse the
component implementations under `scripts/common/`. The standalone Redis and
Supervisor scripts remain Ubuntu-only.

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

Nginx, database, and PHP-FPM installers verify both the active runtime state
and systemd boot enablement. When HTTPS is configured, the available
`certbot.timer` or `certbot-renew.timer` must likewise be active and enabled.

The PHP installer uses each supported operating system's default PHP stream. It
does not add a PHP PPA/Remi repository or replace an existing global PHP
alternative. A fresh installation provisions the Redis, ZIP, GD, and OPcache
PHP extensions. GD is the supported image-processing extension; Anchor does
not install Imagick.
Debian 13 uses PHP 8.4 and its versioned extension packages from the default
repository. The fast path verifies PHP-FPM and the complete required extension
set before it skips reconciliation.

openSUSE support is intentionally limited to Leap 16.0. Anchor uses only its
configured default Zypper repositories: Nginx loads the Anchor site from
`/etc/nginx/conf.d`, MariaDB 11.8 uses the `mariadb` and `mariadb-client`
packages with the `mariadb` service and preserves socket-based root
authentication, and PHP 8.4 uses the distribution's `php8-*` packages under
`wwwrun:www` with PHP-FPM at `127.0.0.1:9000`.
OpenSSL, OPcache, Redis, and GD are installed from their matching `php8-*`
packages.
Active firewalld and enabled SELinux policy are handled without disabling
either security layer. When required, Anchor records and enables
`httpd_can_network_connect` for the TCP PHP-FPM and outbound WordPress paths.
Redis and Supervisor services remain unavailable on this route.

---

## Repository Structure

Current structure:

```text
Anchor/
├── .agents/skills/
│   └── anchor-install-server/ # experimental clean-server install Skill
├── AGENTS.md
├── README.md
├── INSTALL.md
├── CDSI-Anchor.md
├── CDSI_MANIFESTO_ZH_EN.md
├── bootstrap.sh          # remote bootstrap; prepares tools and starts install.sh
├── install.sh
├── uninstall.sh
├── SHA256SUMS
├── config/
│   ├── domain            # verified active domain (generated locally)
│   └── domain.pending    # pending domain awaiting DNS (generated locally)
├── lib/                  # platform, DNS, package, systemd, and shared helpers
├── scripts/
│   ├── dispatch.sh       # operating-system detection and routing
│   ├── check-env.sh      # independently runnable public entry
│   ├── configure-domain.sh
│   ├── configure-https.sh
│   ├── install-*.sh      # independently runnable public entry
│   ├── common/           # shared component implementations
│   ├── ubuntu/           # implemented platform route
│   ├── debian/           # implemented Debian 13 route
│   ├── centos-stream/    # implemented platform route
│   └── opensuse-leap/    # implemented openSUSE Leap 16.0 route
├── templates/
├── tests/
├── docs/
└── password/             # generated locally and ignored by Git
```

Root `bootstrap.sh` is the version-pinned remote entry for an otherwise unprepared server;
`lib/bootstrap.sh` only transfers checked-out POSIX entry points into Bash.
`install.sh` remains the orchestration entry point. Scripts under `scripts/`
must remain independently runnable and communicate success or failure through
their exit code. `AGENTS.md` defines repository engineering rules; older
documents under `docs/` are retained as design history and are labeled
accordingly.

---

## Roadmap

### M0 — Node Anchor

**In progress.** The four-component WordPress OpenWeb base installation and
optional final Certbot/domain/HTTPS path are implemented. Current work is
integration testing, failure recovery, upgrade and uninstall safety, and real
health checks.

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

**M0 integration and hardening / Anchor Installer v0.3.5**

CDSI is under active development and is not yet ready for production use.
