# CDSI Phase 2 — Creator Asset Layer

> Status: Future design draft v0.1; not active Anchor implementation
> Target: Codex / Engineering Implementation  
> Project: CDSI  
> Phase: 2  
> Core theme: Creator Digital Asset Ownership

> **Repository status (2026-08-22):** Anchor remains in M0 installer
> integration and hardening. The WordPress OpenWeb provisioning path is
> implemented, but CDSI Core, server-side asset APIs, backup/restore, and this
> asset layer are not implemented in this repository. Do not use the phase
> number in this historical draft as the active roadmap or an immediate task;
> the root [README](../README.md) and [AGENTS](../AGENTS.md) are authoritative.
> Local asset discovery and cloud backup currently belong to CDSI Beacon.

---

## 1. Phase 2 Goal

This draft originally assumed that CDSI Phase 1 had completed the full
infrastructure path:

- GitHub repository exists
- server initialization can run
- Nginx / MySQL / PHP and related runtime dependencies can be installed
- basic deployment workflow is functional
- CDSI Anchor can provision a usable server environment

Anchor now provisions the five-component WordPress OpenWeb path, but M0 still
requires integration, recovery, upgrade, uninstall, and health-check hardening.
The broader assumption in this draft must therefore be treated as a future
activation gate, not as a completion claim.

Phase 2 should stop expanding infrastructure horizontally.

The next objective is to turn CDSI from:

> an infrastructure provisioning tool

into:

> a creator digital asset control layer.

The core success condition of Phase 2 is:

> A creator can store, describe, back up, restore, and migrate their core digital assets without depending on a specific content platform.

The system should treat platforms such as WordPress, Zhihu, WeChat, Xiaohongshu, Douyin, Bilibili, YouTube, etc. as distribution endpoints rather than the authoritative source of creator assets.

---

# 2. Product Principle

CDSI must follow one core principle:

> The CDSI copy is the source of truth. Platform copies are distributions.

In other words:

```text
CDSI Content
    ↓
Distribution
    ├── Website
    ├── WordPress
    ├── Zhihu
    ├── WeChat
    ├── Xiaohongshu
    ├── Douyin
    ├── Bilibili
    └── YouTube
```

A creator should not define an article as:

> “an article published on Zhihu”

but as:

> “a creator-owned content asset that may have been distributed to Zhihu.”

CDSI should therefore own:

- identity metadata
- original content
- media files
- content metadata
- distribution metadata
- backup metadata
- migration metadata

---

# 3. Scope of Phase 2

Phase 2 should implement five core capabilities:

1. Creator Asset Specification
2. Content Vault
3. Content Manifest
4. Backup / Restore
5. End-to-End Creator Site provisioning

Optional if time permits:

6. Markdown import
7. WordPress import
8. local media import

Do NOT prioritize the following in Phase 2:

- CRM
- newsletter
- user membership
- recommendation systems
- multi-platform publishing automation
- social login
- AI agents
- analytics dashboard
- complex content editing UI

These belong to later phases.

---

# 4. Proposed CDSI Layer Model

```text
┌─────────────────────────────────────┐
│            External Platforms       │
│ WordPress / Zhihu / WeChat / etc.   │
└──────────────────┬──────────────────┘
                   │
             Distribution
                   │
┌──────────────────▼──────────────────┐
│                CDSI                 │
│                                     │
│ Creator Identity                    │
│ Content                             │
│ Media Assets                        │
│ Metadata                            │
│ Distribution Records                │
│ Manifest                            │
│ Backup / Restore                    │
│ Migration                           │
└──────────────────┬──────────────────┘
                   │
┌──────────────────▼──────────────────┐
│          Owned Infrastructure       │
│ Filesystem / DB / Object Storage    │
│ Web Server / Runtime / Backup       │
└─────────────────────────────────────┘
```

---

# 5. Creator Asset Specification v0.1

Create a first open asset specification.

Suggested file:

```text
docs/specs/creator-asset-spec-v0.1.md
```

The specification should define the following logical asset groups.

## 5.1 Creator Identity

```yaml
creator:
  id: creator-001
  name: Example Creator
  display_name: Example Creator
  avatar: assets/avatar.jpg
  bio: ""
  website: https://example.com

  domains:
    - example.com

  social_accounts:
    - platform: douyin
      username: example
      url: ""
```

Required fields:

- id
- name

Optional fields:

- display_name
- avatar
- bio
- website
- domains
- social_accounts

---

## 5.2 Content

Supported initial content types:

```text
article
video
image
audio
note
```

Phase 2 implementation should prioritize:

```text
article
video
```

Each content item must have:

- globally unique CDSI ID
- type
- title
- creation time
- canonical content location
- asset references
- metadata
- distribution records

---

## 5.3 Media Assets

Media should not be embedded directly inside content metadata.

Use file references.

Example:

```yaml
assets:
  - id: asset-cover
    type: image
    path: assets/cover.jpg

  - id: asset-video
    type: video
    path: assets/final.mp4
```

Potential asset types:

```text
image
video
audio
document
attachment
thumbnail
cover
subtitle
```

---

# 6. Content Vault

Implement a filesystem-based Content Vault.

Initial design should prefer:

> Human-readable + Git-friendly + portable.

Do not make the database the only source of truth.

Suggested root structure:

```text
cdsi-data/
├── creator.yaml
├── content/
│   ├── articles/
│   ├── videos/
│   ├── images/
│   ├── audio/
│   └── notes/
├── assets/
├── backups/
├── exports/
└── system/
```

Each content item should use its own directory.

Example article:

```text
content/articles/2026/csi-20260818-001/
├── manifest.yaml
├── content.md
└── assets/
    └── cover.jpg
```

Example video:

```text
content/videos/2026/csi-20260818-002/
├── manifest.yaml
├── script.md
├── final.mp4
├── subtitle.srt
└── assets/
    └── cover.jpg
```

---

# 7. Content Manifest Schema

Every content item must have a `manifest.yaml`.

Example:

```yaml
version: "0.1"

id: csi-20260818-001

type: article

title: 流量是如何一点一点变少的

slug: traffic-is-disappearing

creator:
  id: creator-001

status: published

created_at: 2026-08-18T10:00:00+08:00
updated_at: 2026-08-18T10:00:00+08:00

canonical:
  format: markdown
  file: content.md

assets:
  - id: cover
    type: image
    file: assets/cover.jpg

tags:
  - 内容生态
  - 平台分发
  - 数字主权

distribution:
  - platform: wordpress
    status: published
    url: https://example.com/traffic-is-disappearing
    published_at: 2026-08-18T10:30:00+08:00

  - platform: zhihu
    status: published
    url: ""
    published_at: null

metadata:
  language: zh-CN
  source: original
```

---

# 8. Manifest Validation

Implement manifest schema validation.

Requirements:

- required fields must be checked
- unsupported content types must fail
- invalid timestamps must fail
- referenced local files must optionally be checked
- duplicate IDs must be detected

Suggested command:

```bash
cdsi validate
```

Optional:

```bash
cdsi validate content/articles/2026/csi-20260818-001
```

Output example:

```text
✓ creator.yaml valid
✓ csi-20260818-001 valid
✓ csi-20260818-002 valid

2 content items checked.
0 errors.
```

On error:

```text
ERROR csi-20260818-003:
- missing required field: title
- referenced file not found: assets/cover.jpg
```

The validator should return a non-zero exit code when validation fails.

---

# 9. CDSI CLI

Phase 2 should start converging around a stable CLI.

Suggested commands:

```bash
cdsi init
cdsi install
cdsi status
cdsi validate

cdsi content list
cdsi content show <id>

cdsi backup
cdsi restore <backup-file>

cdsi import markdown <path>
cdsi import wordpress <file>
```

Do not implement every command immediately.

Required Phase 2 commands:

```bash
cdsi init
cdsi status
cdsi validate
cdsi backup
cdsi restore
```

---

# 10. `cdsi init`

Goal:

Initialize a CDSI creator asset workspace.

Example:

```bash
cdsi init
```

Expected result:

```text
cdsi-data/
├── creator.yaml
├── content/
├── assets/
├── backups/
├── exports/
└── system/
```

Interactive questions may include:

```text
Creator name:
Primary domain:
Default language:
Storage path:
```

Non-interactive mode should eventually support:

```bash
cdsi init \
  --creator "Example Creator" \
  --domain example.com \
  --language zh-CN
```

Phase 2 may implement either interactive or non-interactive first.

---

# 11. `cdsi status`

Purpose:

Show whether the creator infrastructure and asset layer are healthy.

Example:

```text
CDSI Status

Infrastructure
  Nginx       OK
  MySQL       OK
  PHP         OK
  HTTPS       OK

Asset Layer
  Creator     OK
  Content     42 items
  Assets      156 files
  Validation  OK

Backup
  Last backup 2026-08-18 08:00
```

Exit code should be non-zero for critical failure.

---

# 12. Backup System

Backup is a first-class feature.

Command:

```bash
cdsi backup
```

Output:

```text
backups/
└── cdsi-backup-20260818-110000.tar.gz
```

Recommended backup contents:

```text
manifest.json
creator.yaml
content/
assets/
database.sql
config/
```

Do NOT blindly include secrets.

Sensitive configuration such as:

```text
API keys
passwords
private keys
OAuth secrets
```

must either:

- be excluded
- or explicitly documented as encrypted / separately managed

Initial Phase 2 behavior:

> Exclude secrets from backup by default.

---

# 13. Backup Manifest

Each backup should contain metadata.

Example:

```json
{
  "cdsi_version": "0.2.0",
  "backup_version": "0.1",
  "created_at": "2026-08-18T11:00:00+08:00",
  "creator_id": "creator-001",
  "content_count": 42,
  "asset_count": 156,
  "includes_database": true,
  "includes_content": true,
  "includes_assets": true
}
```

---

# 14. Restore System

Command:

```bash
cdsi restore cdsi-backup-20260818-110000.tar.gz
```

Required steps:

1. validate archive
2. validate backup manifest
3. verify CDSI version compatibility
4. optionally create safety backup of current state
5. restore creator metadata
6. restore Content Vault
7. restore assets
8. restore database
9. run validation
10. print final status

Restore must fail safely.

Never destroy an existing installation before confirming that the backup archive is valid.

---

# 15. Disaster Recovery Acceptance Test

This is one of the most important Phase 2 tests.

Scenario:

```text
The current CDSI server is completely lost.
```

Test procedure:

```bash
# On a fresh server

git clone <CDSI_REPO>

cd CDSI

./install.sh

cdsi restore cdsi-backup.tar.gz

cdsi validate

cdsi status
```

Expected result:

- creator identity restored
- content restored
- media assets restored
- database restored
- website usable
- canonical URLs recoverable
- validation passes

This should be documented as:

```text
docs/disaster-recovery.md
```

---

# 16. First End-to-End Creator Site

Phase 2 should produce one complete real-world reference deployment.

Use an actual creator site / CDSI Research-type site as the dogfooding target.

The test instance should contain:

- creator profile
- at least 10 articles
- images
- tags
- publish times
- canonical URLs
- WordPress distribution metadata
- at least one full backup
- successful restore test

The goal is to verify:

> CDSI can reconstruct the creator's owned digital asset layer from backup.

---

# 17. Import Layer

Import is secondary to the core asset model.

Do not design importer-specific structures before the canonical CDSI Content Manifest is stable.

All importers must normalize external content into the CDSI content structure.

Pattern:

```text
External Source
      ↓
Importer
      ↓
Normalizer
      ↓
CDSI Manifest
      ↓
Content Vault
```

---

# 18. Markdown Import

Recommended first importer.

Command:

```bash
cdsi import markdown ./articles
```

Supported formats:

```text
*.md
```

Optional front matter support:

```yaml
---
title: Example
date: 2026-08-18
tags:
  - example
---
```

If metadata is missing:

- infer title from first H1 when possible
- infer created time from file metadata only as fallback
- create a CDSI ID
- create manifest.yaml
- preserve original Markdown

---

# 19. WordPress Import

Recommended second importer.

Initial implementation can use:

```text
WordPress WXR/XML export
```

Command:

```bash
cdsi import wordpress wordpress-export.xml
```

Normalize:

- post title
- slug
- body
- publish date
- tags
- categories
- media URLs
- canonical WordPress URL

Do not make remote crawling mandatory in v0.1.

---

# 20. Content ID Strategy

Every CDSI content item needs a stable ID independent of platform IDs.

Suggested format:

```text
cdsi-YYYYMMDD-random
```

Example:

```text
cdsi-20260818-a7f3c2
```

Alternative:

UUID / ULID.

Preferred properties:

- globally unique
- sortable if possible
- platform-independent
- immutable

If adopting ULID:

```text
01K2XXXXXXXXXXXXXXX
```

Then platform IDs live only inside distribution metadata.

Example:

```yaml
distribution:
  - platform: wordpress
    external_id: "1928"
```

---

# 21. Canonical Content Rule

Every content asset must have one canonical CDSI representation.

For articles:

```text
Markdown is preferred canonical source in Phase 2.
```

For videos:

```text
script.md + original/final video file + manifest
```

A rendered HTML page is not necessarily the canonical source.

Example:

```text
content.md
    ↓
renderer
    ↓
HTML / WordPress / RSS / API
```

---

# 22. Separation of Concerns

Avoid coupling CDSI Core to WordPress.

Recommended modules:

```text
core/
  asset/
  manifest/
  validator/
  backup/
  restore/

adapters/
  wordpress/
  filesystem/
  mysql/

importers/
  markdown/
  wordpress/

cli/
```

Conceptually:

```text
CDSI Core
    ↑
Adapters
    ↑
External systems
```

WordPress must remain replaceable.

---

# 23. Configuration

Suggested config file:

```text
cdsi.yaml
```

Example:

```yaml
version: "0.1"

creator_data_path: ./cdsi-data

site:
  domain: example.com
  language: zh-CN

storage:
  driver: filesystem
  path: ./cdsi-data

database:
  driver: mysql

backup:
  path: ./cdsi-data/backups
  include_database: true
```

Secrets should live separately.

Example:

```text
.env
```

and `.env` should never be committed.

---

# 24. Repository Structure Proposal

Adapt to existing repository if necessary.

```text
CDSI/
├── README.md
├── AGENTS.md
├── cdsi.yaml.example
├── install.sh
│
├── bin/
│   └── cdsi
│
├── src/
│   ├── core/
│   │   ├── asset/
│   │   ├── manifest/
│   │   ├── validator/
│   │   ├── backup/
│   │   └── restore/
│   │
│   ├── importers/
│   │   ├── markdown/
│   │   └── wordpress/
│   │
│   └── adapters/
│       ├── filesystem/
│       ├── mysql/
│       └── wordpress/
│
├── schemas/
│   ├── creator.schema.json
│   └── content-manifest.schema.json
│
├── docs/
│   ├── architecture.md
│   ├── disaster-recovery.md
│   └── specs/
│       └── creator-asset-spec-v0.1.md
│
└── tests/
    ├── fixtures/
    ├── unit/
    └── integration/
```

Do not force this exact structure if it conflicts heavily with the current repository.

Preserve existing architecture where reasonable.

---

# 25. GitHub Issues for Phase 2

Create / implement in approximately this order.

## Issue #1 — Define Creator Asset Specification v0.1

Deliverables:

- `docs/specs/creator-asset-spec-v0.1.md`
- creator schema
- content manifest schema
- examples

Acceptance criteria:

- article can be fully represented
- video can be fully represented
- platform metadata is not authoritative
- schema is portable

---

## Issue #2 — Implement Content Vault

Deliverables:

- standard directory structure
- initialization logic
- creator.yaml creation
- content directory conventions

Acceptance criteria:

```bash
cdsi init
```

creates a valid workspace.

---

## Issue #3 — Implement Manifest Validation

Deliverables:

- schema validation
- file reference validation
- duplicate ID detection

Acceptance criteria:

```bash
cdsi validate
```

returns:

```text
0
```

for valid content and non-zero for invalid content.

---

## Issue #4 — Implement Backup

Deliverables:

- archive creation
- backup manifest
- database dump
- Content Vault inclusion
- secrets exclusion

Acceptance criteria:

```bash
cdsi backup
```

creates a valid portable archive.

---

## Issue #5 — Implement Restore

Deliverables:

- archive validation
- restore workflow
- safety handling
- post-restore validation

Acceptance criteria:

A clean CDSI installation can be restored from a backup.

---

## Issue #6 — Build Reference Creator Instance

Deliverables:

- real creator profile
- real Markdown content
- real media assets
- backup file generated
- restore test documented

Acceptance criteria:

The reference site survives a complete server rebuild.

---

## Issue #7 — Markdown Importer

Deliverables:

```bash
cdsi import markdown <path>
```

Acceptance criteria:

Markdown files become valid CDSI content assets.

---

## Issue #8 — WordPress Importer

Deliverables:

```bash
cdsi import wordpress <wxr-file>
```

Acceptance criteria:

WordPress posts can be normalized into CDSI content assets.

---

# 26. Recommended Development Order

Use this exact priority unless a blocking architectural issue appears.

```text
1. Asset specification
2. Manifest schema
3. Content Vault
4. Validator
5. Backup
6. Restore
7. Disaster recovery test
8. Reference creator deployment
9. Markdown importer
10. WordPress importer
```

Do not start multi-platform publishing before steps 1–8 are stable.

---

# 27. Definition of Done for Phase 2

Phase 2 is complete when all of the following are true:

- [ ] CDSI has a documented Creator Asset Specification
- [ ] creator identity can be represented
- [ ] articles can be represented as portable CDSI assets
- [ ] videos can be represented as portable CDSI assets
- [ ] every content item has a manifest
- [ ] CDSI can validate the asset repository
- [ ] CDSI can create a full backup
- [ ] CDSI can restore the backup on a clean server
- [ ] WordPress is treated as an adapter / distribution endpoint
- [ ] a real creator site has passed disaster recovery testing
- [ ] core data does not depend exclusively on one platform or database
- [ ] secrets are excluded from backup by default

---

# 28. Non-Goals

Phase 2 does NOT need to solve:

- follower migration
- social platform API automation
- newsletter delivery
- user membership
- paid subscriptions
- comments
- CRM
- recommendation
- AI content generation
- AI agent orchestration
- analytics
- creator monetization
- decentralized identity
- blockchain

Avoid scope expansion.

---

# 29. Future Phases

## Phase 3 — Audience / Identity Layer

Potential capabilities:

```text
subscriber ownership
email list
RSS
newsletter
user accounts
membership
CRM
audience tags
```

Goal:

> User relationships belong to the creator.

---

## Phase 4 — Distribution Layer

Potential capabilities:

```text
WordPress publishing
RSS
Email
API
platform adapters
scheduled distribution
distribution status tracking
```

Goal:

> CDSI owns the source; platforms receive copies.

---

## Phase 5 — Intelligence Layer

Potential capabilities:

```text
semantic search
creator knowledge base
AI assistant
content reuse
cross-platform adaptation
asset relationship graph
content strategy
personal agent
```

Goal:

> AI operates on creator-owned data instead of fragmented platform data.

---

# 30. Architectural Principle

Before implementing a new feature, ask:

> Does this increase creator ownership, portability, recoverability, or independence?

If not, it is probably not a Phase 2 priority.

CDSI should optimize for:

```text
Ownership
Portability
Recoverability
Interoperability
Replaceability
```

Avoid optimizing primarily for:

```text
platform lock-in
specific CMS integration
one deployment environment
one database
one social platform
```

---

# 31. Core Product Definition

CDSI is not:

> a website installer.

CDSI is not:

> a WordPress management tool.

CDSI is not:

> a social publishing dashboard.

CDSI should evolve toward:

> An open creator digital asset control layer that allows creators to own, organize, back up, migrate, and distribute their digital assets independently of any single platform.

---

# 32. Codex Execution Instructions

When implementing this phase:

1. Inspect the current repository before modifying architecture.
2. Reuse existing installation and infrastructure modules.
3. Do not rewrite working Phase 1 code without necessity.
4. Keep Phase 2 modules loosely coupled from deployment code.
5. Prefer simple, portable formats.
6. Prefer filesystem + Markdown + YAML/JSON for canonical assets.
7. Do not make WordPress a hard dependency.
8. Add tests for every destructive operation.
9. Backup and restore must be idempotent where possible.
10. Any destructive command should use explicit confirmation or safe pre-checks.
11. Preserve backward compatibility with current install workflow.
12. Update README when commands become usable.
13. Update `AGENTS.md` if new repository-wide engineering rules are introduced.
14. Keep secrets out of Git and backup archives.
15. Before marking Phase 2 complete, execute the disaster recovery test on a clean environment.

---

# 33. Future Activation Gate

Do not start this phase until the active Anchor roadmap explicitly moves beyond
M0 and identifies which repository owns the server-side asset model. When that
happens, start with:

```text
Issue #1 — Creator Asset Specification v0.1
```

Do not begin by writing the importer.

First establish:

```text
What is a creator asset?
What fields are canonical?
What is mutable?
What is immutable?
What belongs to CDSI?
What belongs only to a platform adapter?
How are files referenced?
How are IDs generated?
How are versions handled?
```

Once the specification and schema are stable enough, implement the Content Vault and validator in the repository selected by that roadmap decision.

The specification must drive the code, not the other way around.
