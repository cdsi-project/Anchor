# CDSI

**Creator Digital Sovereignty Infrastructure**  
**创作者数字主权基础设施**

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

The primary path now provisions a WordPress OpenWeb node on a supported Ubuntu
Server:

| Status | Scope |
| --- | --- |
| Implemented in `install.sh` | Preflight, Nginx, MySQL, PHP-FPM, Certbot, WordPress, final service/access report, and component uninstall |
| Implemented support | System-default APT sources, bounded DPKG-lock retry, pinned SHA-256 verification for CDN downloads, and a Beacon WordPress Application Password |
| Standalone only | Redis and Supervisor scripts remain available, but are hidden from the main menu and Install All flow |
| Planned | Composer/CDSI Core deployment, the `cdsi` CLI, `cdsi doctor`, resume/update workflows, and complete server backup/restore |

The supported fresh-install runtime is deliberately narrow:

```text
OS           Ubuntu Server 24.04 LTS or 26.04 LTS
Web          Nginx from the system default APT source
Runtime      PHP-FPM from the system default APT source
Database     MySQL
SSL          Let's Encrypt / Certbot when a valid domain is available
OpenWeb      WordPress
Integration  CDSI Beacon WordPress Application Password
```

### Current Priority

The project is currently focused on:

- clean-server regression testing on both supported Ubuntu releases
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

The current entry point is:

```bash
git clone https://github.com/cdsi-project/Anchor.git
cd Anchor
sudo ./install.sh
```

The installer presents a component menu and can install all five visible
components in dependency order. The future CLI remains planned:

```bash
cdsi install
cdsi status
cdsi doctor
cdsi update
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
bash scripts/health.sh
sudo bash scripts/install-nginx.sh
sudo bash scripts/install-mysql.sh
sudo bash scripts/install-php.sh
sudo bash scripts/install-certbot.sh
sudo bash scripts/install-wordpress.sh
```

`check-env.sh` is the active preflight implementation. `configure.sh` is a
standalone `/etc/cdsi` configuration helper that is not yet called by the main
install flow. `health.sh` remains a visible placeholder for the future
`cdsi doctor` workflow.

The PHP installer uses the default PHP packages from the supported Ubuntu
repositories. It does not add a third-party PHP PPA or replace an existing
global PHP alternative. On a fresh supported installation it provisions Redis,
GD, and OPcache extensions; Imagick is installed when an Ubuntu package is
available. The fast path for a pre-existing PHP installation currently verifies
PHP-FPM and `mysqli`, so administrators should verify any additional extensions
needed by their site.

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
├── lib/
├── scripts/
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
