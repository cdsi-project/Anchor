# CDSI Manifesto / CDSI 项目纲领

**CDSI — Creator Digital Sovereignty Infrastructure**  
**创作者数字主权基础设施**

---

# 中文版

## 一、CDSI 是什么？

CDSI 全称：

**Creator Digital Sovereignty Infrastructure**

中文：

**创作者数字主权基础设施**

CDSI 是一套面向创作者的开源数字基础设施，目标是帮助创作者建立一个真正由自己拥有、自己控制、可以迁移、可以长期存在的数字节点。

CDSI 不是另一个中心化内容平台。

也不是一个通过封闭系统重新锁住创作者的 SaaS。

它不只是个人网站生成器、CMS、Newsletter 工具或者媒体文件仓库。

CDSI 想解决的是一个更基础的问题：

> **创作者能不能在开放 Web 上，拥有一个真正属于自己的数字位置？**

这个位置能够长期承载创作者的：

- 身份；
- 内容；
- 数据；
- 用户关系；
- 创作资产；
- 产品；
- 服务；
- 数字连接。

CDSI 的长期目标非常简单：

> **让每一个创作者，都能够拥有自己在互联网中的位置。**

---

## 二、我们正在解决什么问题

创作者每天都在生产大量数字价值。

文章是创作者写的。

视频是创作者拍的。

播客是创作者录制的。

观点、方法论、研究、品牌、产品、社区，也都来自创作者长期积累。

但今天，大量数字价值最终存在于第三方平台内部。

创作者可能拥有作品的版权，但平台依然控制着：

- 内容能不能被发现；
- 内容如何被分发；
- 粉丝能不能被再次触达；
- 能不能放外部链接；
- 账号能不能继续存在；
- 数据能不能完整导出；
- 用户关系能不能脱离平台继续存在。

于是出现了一个非常重要的结构性矛盾：

> **数字资产由创作者创造，但资产如何存在、如何连接、如何被分发，却越来越由平台决定。**

平台越强大，创作者获得的分发效率越高。

但与此同时，依赖也可能越来越深。

CDSI 就是为降低这种依赖而存在。

---

## 三、什么是创作者数字主权

CDSI 所说的“数字主权”，指的是创作者对自己数字存在核心部分的控制能力。

包括：

- 数字身份；
- 内容；
- 域名；
- 文件；
- 数据库；
- 元数据；
- 用户关系；
- 分发记录；
- 产品与服务；
- 备份；
- 迁移能力；
- 面向机器和 Agent 的接口。

数字主权并不意味着封闭。

也不是要求创作者脱离所有平台。

它真正要求的是：

> **在平台之下，创作者依然拥有一个独立存在的基础。**

---

## 四、先拥有，再分发

CDSI 遵循一个非常简单的原则：

> **Own First, Distribute Everywhere.**  
> **先拥有，再分发。**

平台依然是非常高效的分发基础设施。

创作者当然应该继续使用平台。

但“分发”和“拥有”不是一回事。

一个平台可以帮助创作者分发内容，但不应该因此成为内容唯一存在的地方。

一个平台可以带来流量，但不应该成为创作者唯一的数字身份。

一个平台可以提供粉丝关系，但创作者不应该只有一种连接用户的方法。

因此 CDSI 希望建立这样的结构：

```text
创作者
   │
   ▼
创作者自有数字原点
   │
   ├── 身份
   ├── 内容
   ├── 资产
   ├── 用户
   ├── 数据
   └── 行动入口
   │
   ▼
各类分发平台
```

平台负责分发。

创作者负责拥有。

---

## 五、CDSI Node

CDSI 的基本单元是：

> **CDSI Node — 创作者数字节点**

一个 CDSI Node 是由创作者自己控制的独立数字节点。

长期来看，它可以包含：

```text
Creator
│
├── Identity
│   ├── 个人资料
│   ├── 独立域名
│   └── 平台身份验证
│
├── Assets
│   ├── 文章
│   ├── 观点
│   ├── 视频
│   ├── 播客
│   ├── 图片
│   ├── Research
│   └── 项目
│
├── Audience
│   ├── 订阅者
│   ├── 会员
│   └── 用户关系
│
├── Distribution
│   ├── 平台链接
│   ├── 分发记录
│   └── Feed
│
├── Data
│   ├── 数据库
│   ├── 媒体文件
│   ├── 元数据
│   └── 备份
│
└── Action
    ├── 产品
    ├── 服务
    ├── 订阅
    ├── API
    └── Agent 接口
```

CDSI Node 不只是一个个人网站。

网站只是它最先能够被人看见的表层。

真正的目标是逐渐成为创作者自己的：

> **Digital Headquarters — 数字总部。**

---

## 六、CDSI 的核心原则

### 1. 创作者所有权优先

创作者应该控制自己的：

- 域名；
- 数据库；
- 媒体文件；
- 内容；
- 配置；
- 用户关系；
- 备份。

CDSI 自己不能成为新的平台锁定。

---

### 2. Self-Hosted First

自部署必须是一等公民。

未来 CDSI 可以提供官方托管服务，但开源版本必须始终能够独立部署。

创作者应该有能力把 CDSI 跑在自己控制的基础设施上。

---

### 3. 默认可导出

数据可迁移不是附加功能。

它是项目宪法的一部分。

核心数据应该能够通过常见格式导出，例如：

- Markdown；
- JSON；
- CSV；
- RSS / XML；
- 标准媒体文件；
- 数据库备份。

创作者应该能够离开 CDSI，而不失去自己的资产。

---

### 4. Open Web First

CDSI 应尽可能优先使用已有的开放 Web 技术和标准。

例如：

- HTTP / HTTPS；
- RSS；
- Sitemap；
- Schema.org；
- JSON；
- Markdown；
- Web 标准；
- 开放 API。

未来还可以逐步接入：

- ActivityPub；
- Webmention；
- AI 可读接口；
- Agent 可调用接口。

如果已经存在成熟开放标准，CDSI 不应该为了锁定用户重新创造私有协议。

---

### 5. CDSI 自身也必须可替换

CDSI 自己不是终点。

未来创作者应该能够替换 CDSI，而不失去自己的数字资产。

这是刻意设计的原则。

> **软件可以被替换，创作者资产必须活下来。**

---

## 七、CDSI 不是另一个平台

CDSI 不希望把成千上万创作者重新装进一个新的中央系统。

它希望建立的方向恰恰相反。

不是：

```text
无数创作者
    ↓
一个超级平台
```

而是：

```text
创作者 A → 独立节点
创作者 B → 独立节点
创作者 C → 独立节点
创作者 D → 独立节点
```

这些节点仍然可以相互连接。

仍然可以使用平台。

仍然可以被搜索引擎、AI 或未来 Agent 发现。

但每一个节点，都应该保持独立所有权。

---

## 八、CDSI 不是反平台运动

CDSI 并不建立在“平台会消失”这个假设上。

大型平台未来依然会是重要的分发基础设施。

CDSI 不是让创作者逃离平台。

真正要避免的是：

> **分发基础设施成为创作者数字存在的唯一载体。**

因此 CDSI 区分：

> **Distribution Dependency — 分发依赖**

和：

> **Asset Dependency — 资产依赖**

一个创作者完全可以战略性地把 80% 的流量集中在某一个平台。

这可能是理性的。

但是创作者的身份、内容原点、数据和用户关系，并不一定也要全部集中在同一个地方。

---

## 九、让内容真正成为资产

在平台的信息流中，内容通常只是一条 Post。

但在 CDSI 中，内容应该被视为长期数字资产。

创作者资产可以包括：

- 文章；
- 观点；
- 视频；
- 字幕；
- 口播稿；
- Podcast；
- Research；
- 图片；
- 项目记录；
- 数据集；
- 方法论；
- 产品文档；
- 原始文件；
- 草稿；
- 版本历史。

CDSI 不应该只保存最终作品。

还应该逐渐保存：

> **产生这些作品的知识资产和创作材料。**

因为真正长期有价值的，往往不是一条爆款，而是创作者背后的完整知识结构。

---

## 十、用户关系也是数字主权的一部分

一个创作者可能拥有几十万甚至几百万粉丝。

但这并不一定意味着他能够直接控制这些用户关系。

平台粉丝当然是一种资产。

但它往往是一种：

> **高价值、低控制权的关系资产。**

因此 CDSI 把直接用户关系也视为数字主权的重要组成部分。

可能包括：

- RSS；
- Email；
- Newsletter；
- 会员账号；
- 订阅；
- 社区；
- 直接服务；
- 创作者自己的 App。

目标不是把所有平台粉丝全部搬走。

而是：

> **让创作者不再只有一种连接用户的方法。**

---

## 十一、Web 重新成为数字原点

CDSI 认为，在 AI 时代，Web 可能重新成为创作者最重要的数字原点之一。

这并不意味着用户会重新每天打开几十个个人网站浏览内容。

真正重要的是：

> Web 依然是开放、可寻址、可连接的信息基础层。

独立域名可以提供：

- 稳定身份；
- 原始内容源；
- 永久 URL；
- 结构化元数据；
- 搜索入口；
- 机器可读能力；
- 来源归属；
- 产品和服务直接入口。

因此 Web 可以逐渐成为创作者自己的：

> **Source of Truth — 官方数字源头。**

平台则围绕这个源头承担分发职责。

---

## 十二、AI 与 Agent 时代

下一代互联网可能不再只围绕“人打开浏览器”组织。

搜索引擎已经帮助人发现信息。

AI 正在开始理解和重新组织信息。

Agent 未来可能进一步替用户做出选择并完成行动。

所以 CDSI 认为未来的创作者数字节点应该同时满足：

- Human-readable —— 人可以阅读；
- Machine-readable —— 机器可以理解；
- Linkable —— 可以连接；
- Versionable —— 可以追溯；
- Callable —— 可以被调用。

一个很重要的长期判断是：

> **Web负责存在，平台负责分发，AI负责理解，Agent负责行动。**

而创作者应该在这套体系里拥有自己的数字原点。

---

## 十三、第一个工程目标

CDSI 从基础设施开始。

在做文章、视频、播客、会员、AI 或开放社交协议之前，CDSI 首先需要证明一件更基础的事情：

> **一个创作者不应该为了拥有自己的数字节点，而先成为一个专业系统管理员。**

因此第一个工程里程碑是：

> **M0 — Node Anchor**

目标：

```text
一台干净 Ubuntu Server
        ↓
CDSI Installer
        ↓
Nginx
PHP
MySQL
Redis
Supervisor
HTTPS
        ↓
CDSI Node
```

基础设施可以复杂。

但用户面对的操作应该越来越简单。

最终：

```bash
cdsi install
```

就应该能够成为起点。

---

## 十四、不依靠锁定用户商业化

CDSI 可以商业化。

未来可以提供：

- 官方托管；
- 自动备份；
- CDN；
- 安全维护；
- 数据迁移；
- 创作资产整理；
- 搜索优化；
- AI 可发现性；
- 数字主权诊断；
- 专业实施；
- 企业支持。

用户可以为：

> 便利、专业能力、稳定性和服务

付费。

但不能因为：

> **无法离开 CDSI**

而被迫付费。

CDSI 的商业原则应该是：

> **帮助用户拥有更多，而不是让用户更难离开。**

---

## 十五、长期愿景

CDSI 从帮助一个创作者建立一个独立节点开始。

下一阶段，则可能让独立节点之间重新建立开放连接。

最终形成：

```text
Creator A Node
      ↕
Creator B Node
      ↕
Creator C Node
      ↕
搜索 / AI / Agent / 企业 / 用户
```

它不是一个新的超级平台。

而是一张由大量独立节点共同组成的开放网络：

- 每个节点都可以独立存在；
- 每个创作者都可以迁移；
- 每个创作者拥有自己的资产；
- 节点之间又可以通过开放协议连接。

---

## 十六、项目宪法

CDSI 存在的目的，是减少创作者对封闭数字基础设施的依赖。

因此 CDSI 自己也不能成为新的不必要依赖。

系统应该长期保持：

```text
Open
Self-hostable
Portable
Exportable
Replaceable
Interoperable
```

当“更多功能”和“更多所有权”发生冲突时：

> CDSI 应优先保护所有权。

当“方便”和“可迁移”发生冲突时：

> CDSI 应优先保护可迁移性。

当“锁定”与“互操作”发生冲突时：

> CDSI 应选择互操作。

当“增长”和“创作者控制权”发生冲突时：

> CDSI 不应该为了增长轻易牺牲创作者控制权。

---

## 十七、CDSI 宣言

我们认为，创作者应该有权决定：

- 自己的数字身份在哪里存在；
- 自己的内容保存在哪里；
- 自己的数据由谁控制；
- 用户通过什么方式连接自己；
- 数字资产如何迁移；
- 内容如何被发现；
- 产品和服务如何被访问。

平台会改变。

算法会改变。

公司可能消失。

软件会被替换。

甚至 CDSI 自己有一天也可能被替换。

但：

> **创作者的数字资产不应该因此消失。**

**Your Domain. Your Content. Your Data. Your Audience.**

**你的域名，你的内容，你的数据，你的用户关系。**

这就是 CDSI。

---

# English Version

## 1. What is CDSI?

CDSI stands for **Creator Digital Sovereignty Infrastructure**.

CDSI is an open-source infrastructure project designed to help creators build and operate a digital presence that they can truly own and control.

It is not another centralized content platform.

It is not a closed SaaS designed to lock creators into a new system.

It is not simply a website builder, CMS, newsletter tool, or media archive.

CDSI exists to help creators establish an independent digital node on the open Web — a node where their identity, content, data, relationships, and digital assets can continue to exist regardless of changes in any single platform.

The long-term goal is simple:

> **Every creator should be able to own their place on the Internet.**

---

## 2. The Problem

Creators produce enormous amounts of digital value.

They write articles.

They publish videos.

They record podcasts.

They develop ideas, methods, research, products, communities, and brands.

But much of this value is created and stored inside third-party platforms.

A creator may own the copyright to a piece of content, while the platform still controls:

- whether the content is discovered;
- how it is distributed;
- whether followers can be reached;
- whether links can be shared;
- whether the account remains available;
- whether data can be exported;
- whether relationships with audiences can continue outside the platform.

This creates a structural contradiction:

> **Creators create the assets, but platforms often control how those assets exist, connect, and reach people.**

The larger a creator becomes, the more valuable the platform relationship becomes.

But the same relationship can also become a dependency.

CDSI is created to reduce that dependency.

---

## 3. Digital Sovereignty

CDSI uses the term **digital sovereignty** to describe a creator's ability to control the core elements of their digital existence.

Digital sovereignty includes the ability to control:

- digital identity;
- content;
- domains;
- files;
- databases;
- metadata;
- audience relationships;
- distribution records;
- products and services;
- backups;
- migration paths;
- machine-readable interfaces.

Digital sovereignty does not mean isolation.

It does not mean abandoning platforms.

It means that the creator retains an independent foundation beneath those platforms.

---

## 4. Own First, Distribute Everywhere

CDSI follows a simple principle:

> **Own first. Distribute everywhere.**

Platforms are extremely effective distribution systems.

Creators should continue to use them.

But distribution and ownership are different things.

A platform can distribute a creator's content without becoming the only place where that content exists.

A platform can provide traffic without becoming the only place where the creator's identity exists.

A platform can provide followers without becoming the only mechanism through which the creator can maintain relationships.

CDSI therefore proposes a different structure:

```text
Creator
   │
   ▼
Creator-Owned Digital Origin
   │
   ├── Identity
   ├── Content
   ├── Assets
   ├── Audience
   ├── Data
   └── Actions
   │
   ▼
Distribution Platforms
```

The platform distributes.

The creator owns the origin.

---

## 5. The CDSI Node

The basic unit of CDSI is the **CDSI Node**.

A CDSI Node is an independent digital node controlled by the creator.

It may eventually include:

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

A CDSI Node is not simply a personal website.

The website is only the visible surface.

The deeper goal is to create a **creator-owned digital headquarters**.

---

## 6. Our Core Principles

### 6.1 Creator Ownership First

Creators should control their own:

- domain;
- database;
- media files;
- content;
- configuration;
- user relationships;
- backups.

CDSI must not become another platform lock-in.

---

### 6.2 Self-Hosted First

Self-hosting is a first-class deployment model.

Managed hosting may exist in the future, but the open-source version must remain independently deployable.

A creator should be able to operate CDSI on infrastructure they control.

---

### 6.3 Exportable by Default

Data portability is not an optional feature.

It is part of the constitution of the project.

Core data should remain exportable through common formats such as:

- Markdown;
- JSON;
- CSV;
- RSS / XML;
- standard media files;
- database backups.

The creator must be able to leave CDSI without losing their assets.

---

### 6.4 Open Web First

CDSI prefers established open technologies and standards whenever possible.

These may include:

- HTTP / HTTPS;
- RSS;
- Sitemap;
- Schema.org;
- JSON;
- Markdown;
- Web standards;
- open APIs.

Future integrations may include:

- ActivityPub;
- Webmention;
- AI-readable interfaces;
- Agent-callable interfaces.

CDSI should not invent proprietary protocols where open standards already exist.

---

### 6.5 Replaceable by Design

CDSI itself should be replaceable.

This is intentional.

A creator should eventually be able to migrate away from CDSI without losing their digital assets.

> **Software can be replaced. Creator assets must survive.**

---

## 7. CDSI Is Not Another Platform

CDSI does not aim to place millions of creators inside one centralized system.

Its long-term direction is the opposite.

Instead of:

```text
Millions of creators
        ↓
One platform
```

CDSI prefers:

```text
Creator A → Independent Node
Creator B → Independent Node
Creator C → Independent Node
Creator D → Independent Node
```

These nodes may still connect with each other.

They may still interact with platforms.

They may still be discovered by search engines, AI systems, or future Agents.

But each node should remain independently owned.

---

## 8. CDSI Is Not an Anti-Platform Movement

CDSI is not built on the assumption that platforms will disappear.

Large platforms will continue to play an important role in distribution.

The goal is not to escape platforms.

The goal is to prevent distribution infrastructure from becoming the sole owner of a creator's digital existence.

CDSI therefore distinguishes between:

> **Distribution dependency**

and:

> **Asset dependency**

A creator may strategically depend on one platform for most traffic.

That can be rational.

But the creator's identity, content origin, data, and relationships should not necessarily be concentrated in the same place.

---

## 9. Content Should Become Assets

In platform systems, content is often treated as posts in a feed.

In CDSI, content should be treated as long-term digital assets.

A creator's assets may include:

- articles;
- ideas;
- videos;
- transcripts;
- subtitles;
- podcast episodes;
- research;
- images;
- project records;
- datasets;
- methods;
- product documentation;
- source files;
- drafts;
- version history.

CDSI does not only preserve finished works.

It should also preserve the knowledge and material from which future works can be created.

---

## 10. Audience Relationships Matter

A creator may have hundreds of thousands of followers and still have very limited control over audience relationships.

Platform followers are valuable assets.

But they are often high-value, low-control assets.

CDSI therefore treats direct audience relationships as an important part of digital sovereignty.

Possible relationship channels include:

- RSS;
- email;
- newsletters;
- member accounts;
- subscriptions;
- communities;
- direct services;
- creator-owned applications.

The goal is not to move every follower off every platform.

The goal is to ensure that the creator has more than one way to maintain a relationship with the audience.

---

## 11. The Web as Digital Origin

CDSI believes that the Web may become increasingly important as a creator's digital origin.

Not necessarily because users will return to browsing personal websites all day.

But because the Web remains an open and addressable information layer.

A creator-owned domain can provide:

- a stable identity;
- canonical content sources;
- persistent URLs;
- structured metadata;
- search discoverability;
- machine readability;
- source attribution;
- direct product and service interfaces.

The Web can become the creator's **source of truth**.

Platforms can then become distribution nodes around that origin.

---

## 12. AI and Agent Era

The next generation of the Internet may no longer be organized only around human browsing.

Search engines already discover information.

AI systems increasingly interpret information.

Agents may increasingly perform actions on behalf of users.

CDSI therefore assumes that creator-owned digital infrastructure should be:

- human-readable;
- machine-readable;
- linkable;
- versionable;
- callable.

A useful long-term model is:

> **The Web provides existence.  
> Platforms provide distribution.  
> AI provides understanding.  
> Agents provide action.**

Creators should retain an independent origin inside this architecture.

---

## 13. The First Engineering Goal

CDSI begins with infrastructure.

Before building articles, podcasts, memberships, AI features, or social protocols, CDSI must first prove something more basic:

> **A creator should be able to establish an independent digital node without becoming a professional system administrator.**

The first engineering milestone is therefore:

**M0 — Node Anchor**

The goal:

```text
Clean Ubuntu Server
        ↓
CDSI Installer
        ↓
Nginx
PHP
MySQL
Redis
Supervisor
HTTPS
        ↓
CDSI Node
```

Infrastructure complexity should exist underneath.

The creator-facing experience should become progressively simpler.

Eventually:

```bash
cdsi install
```

should be enough to begin.

---

## 14. Commercialization Without Lock-In

CDSI may support commercial services.

Possible services may include:

- managed hosting;
- backups;
- CDN;
- security maintenance;
- migration;
- asset organization;
- search optimization;
- AI discoverability;
- professional implementation;
- digital sovereignty audits;
- enterprise support.

Users may pay for convenience, expertise, reliability, and service.

But they should not be forced to pay because they are unable to leave.

The commercial principle is:

> **Earn by helping users own more, not by making them harder to leave.**

---

## 15. Long-Term Vision

CDSI starts by helping one creator build one independent node.

The next stage may connect independent creator nodes.

Over time, an open network may emerge:

```text
Creator A Node
      ↕
Creator B Node
      ↕
Creator C Node
      ↕
Search / AI / Agents / Businesses / People
```

The goal is not a new super-platform.

The goal is a network in which:

- each node can exist independently;
- each creator can migrate;
- each creator owns their assets;
- nodes can still connect through open standards.

---

## 16. Project Constitution

CDSI exists to reduce creator dependence on closed digital infrastructure.

Therefore CDSI itself must not become another unnecessary dependency.

The system should remain:

```text
Open
Self-hostable
Portable
Exportable
Replaceable
Interoperable
```

When choosing between more features and more ownership, CDSI should prefer ownership.

When choosing between convenience and portability, CDSI should protect portability.

When choosing between lock-in and interoperability, CDSI should choose interoperability.

When choosing between growth and creator control, CDSI should not sacrifice creator control merely for growth.

---

## 17. Manifesto

We believe creators should have the right to decide:

- where their digital identity exists;
- where their content is stored;
- who controls their data;
- how their audience can reach them;
- how their assets can be migrated;
- how their work can be discovered;
- how their products and services can be accessed.

Platforms may change.

Algorithms may change.

Companies may disappear.

Software may be replaced.

CDSI itself may one day be replaced.

But the creator's digital assets should survive.

> **Your Domain. Your Content. Your Data. Your Audience.**

That is the purpose of CDSI.
