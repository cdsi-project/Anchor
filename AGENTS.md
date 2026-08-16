# AGENTS.md

# CDSI Agent Engineering Guide

This file defines the engineering rules, project boundaries, and working conventions for AI coding agents working in the CDSI repository.

All agents MUST read this file before modifying the repository.

---

# 1. Project

## CDSI

**CDSI — Creator Digital Sovereignty Infrastructure**

中文：

**创作者数字主权基础设施**

CDSI is an open-source infrastructure project designed to help creators own and control their:

- digital identity
- content
- creator assets
- data
- audience relationships
- distribution metadata
- digital presence

CDSI does NOT aim to build another centralized content platform.

The long-term goal is:

> Help every creator build and operate an independent digital node on the open Web.

Core principle:

> **Your Domain. Your Content. Your Data. Your Audience.**

中文原则：

> **你的域名，你的内容，你的数据，你的用户关系。**

---

# 2. Project Philosophy

All engineering decisions should respect the following principles.

## 2.1 Creator ownership first

CDSI must not create a new form of platform lock-in.

Users must retain control over:

- domain
- database
- media files
- content
- configuration
- user relationships
- backups

Do not introduce unnecessary dependencies on proprietary infrastructure.

---

## 2.2 Self-hosted first

Self-hosting is a first-class deployment model.

Managed hosting may exist in the future, but the open-source version must remain independently deployable.

A creator should be able to run CDSI on infrastructure they control.

---

## 2.3 Exportable by default

Core creator data must remain exportable.

Preferred portable formats include:

- Markdown
- JSON
- CSV
- RSS / XML
- standard media files
- SQL/database backups

Do not deliberately create proprietary formats that make migration difficult.

---

## 2.4 Open Web first

Prefer established open technologies and protocols where appropriate.

Examples:

- HTTP / HTTPS
- RSS
- Sitemap
- Schema.org
- JSON
- Markdown
- Web standards

Future support may include:

- ActivityPub
- Webmention
- Agent-readable interfaces

Do not invent new protocols without a clear need.

---

## 2.5 Infrastructure should reduce complexity

Users should not need deep knowledge of:

- Linux
- Nginx
- PHP-FPM
- MySQL
- Redis
- Supervisor
- SSL
- deployment operations

to own a CDSI Node.

Infrastructure complexity should be pushed below the user-facing layer wherever reasonably possible.

---

# 3. Current Development Stage

The project is currently in:

# M0 — Node Bootstrap

Current priority:

> From a clean Ubuntu Server to a working HTTPS-accessible CDSI Node through automated installation.

The current engineering focus is NOT yet:

- Article management
- Video management
- Podcast features
- Newsletter
- Membership
- CRM
- Creator analytics
- AI features
- ActivityPub
- mobile apps

Do not expand scope into these areas unless explicitly requested.

---

# 4. Current M0 Architecture

The initial supported deployment stack is:

```text
OS           Ubuntu Server LTS
Web          Nginx
Runtime      PHP-FPM
Package      Composer
Database     MySQL
Cache        Redis
Process      Supervisor
SSL          Let's Encrypt / Certbot
Application  CDSI Core
```

The first version intentionally supports a narrow deployment path.

Do NOT prematurely add support for:

- CentOS
- Rocky Linux
- AlmaLinux
- arbitrary Debian variants
- Apache
- PostgreSQL
- Docker
- Kubernetes
- HA
- clusters
- load balancing
- multi-node orchestration

unless explicitly requested.

Principle:

> Make one deployment path reliable before expanding compatibility.

---

# 5. Repository Boundaries

The repository should maintain clear boundaries between:

## CDSI Core

Responsible for application/business logic.

Examples:

- creator identity
- creator assets
- articles
- notes
- videos
- podcasts
- projects
- audience
- distribution
- data
- action interfaces

## Installer

Responsible for infrastructure setup and application deployment.

Examples:

- operating system checks
- Nginx
- PHP
- Composer
- MySQL
- Redis
- Supervisor
- Certbot
- CDSI deployment
- service configuration
- health checks

Do NOT put CDSI business logic into installation scripts.

---

# 6. Installer Structure

Preferred structure:

```text
installer/
├── install.sh
│
├── lib/
│   ├── common.sh
│   ├── logger.sh
│   ├── system.sh
│   ├── config.sh
│   └── secrets.sh
│
├── modules/
│   ├── nginx.sh
│   ├── php.sh
│   ├── mysql.sh
│   ├── redis.sh
│   ├── supervisor.sh
│   ├── certbot.sh
│   └── cdsi.sh
│
├── templates/
│   ├── nginx.conf.tpl
│   ├── supervisor-worker.conf.tpl
│   └── env.tpl
│
└── checks/
    ├── preflight.sh
    └── health.sh
```

CLI:

```text
bin/
└── cdsi
```

Do NOT build one giant `install.sh`.

Keep modules small and responsibility-focused.

---

# 7. Module Convention

Infrastructure modules should preferably expose:

```bash
<module>_check
<module>_install
<module>_configure
<module>_verify
```

Example:

```bash
nginx_check
nginx_install
nginx_configure
nginx_verify
```

Modules must inspect existing system state before making changes.

Never assume the server is always completely clean.

---

# 8. Idempotency

Installer operations MUST be designed to be idempotent wherever possible.

Running:

```bash
sudo ./installer/install.sh
```

twice must not destroy an existing CDSI installation.

Expected behavior:

```text
Nginx             Installed        SKIP
PHP               Installed        SKIP
MySQL Database    Exists           SKIP
Redis             Running          SKIP
CDSI              Installed        VERIFY
SSL               Valid            SKIP
```

Never automatically:

- recreate an existing database
- reset database credentials
- overwrite user data
- overwrite `.env` without checking
- overwrite Nginx configuration blindly
- request unnecessary new SSL certificates
- delete existing application data

Idempotency is a core engineering requirement.

---

# 9. Security Rules

Security defaults must be conservative.

Agents MUST NOT:

- use MySQL root as the CDSI application user
- use `chmod -R 777`
- expose secrets in logs
- hardcode production passwords
- silently ignore failed commands
- disable TLS verification
- download executable code over plain HTTP
- weaken server security merely to make installation easier

Use dedicated application credentials.

Example:

```text
Database: cdsi
User: cdsi
Password: generated securely
```

Sensitive configuration should have restricted permissions.

Example:

```bash
chmod 600 /etc/cdsi/secrets.env
```

Generate secrets using cryptographically appropriate system tools.

---

# 10. Shell Standards

Installer shell scripts should preferably use Bash.

Recommended:

```bash
set -Eeuo pipefail
```

However, expected probe failures must be handled explicitly.

General rules:

- functions use `snake_case`
- constants use `UPPER_CASE`
- avoid duplicated logic
- avoid implicit working-directory assumptions
- quote variables correctly
- check command exit status
- use absolute paths for important system locations
- separate templates from shell logic
- avoid large inline generated config blocks when a template is more appropriate

Preferred constants:

```bash
readonly CDSI_CONFIG_DIR="/etc/cdsi"
readonly CDSI_APP_DIR="/var/www/cdsi"
readonly CDSI_LOG_DIR="/var/log/cdsi"
```

Run ShellCheck where practical.

---

# 11. Logging

Do not scatter unstructured `echo` statements throughout installer modules.

Use common logging helpers such as:

```bash
log_info
log_success
log_warning
log_error
```

Example output:

```text
[INFO] Installing Nginx...
[ OK ] Nginx installed.
[WARN] Domain DNS does not point to this server.
[FAIL] SSL certificate request failed.
```

Logs should also be persisted.

Example:

```text
/var/log/cdsi/install.log
```

Never write passwords, tokens, private keys, or other secrets to logs.

---

# 12. Error Handling

Installation failures must be explicit.

Bad:

```text
Something went wrong.
```

Good:

```text
Installation failed.

Stage:
MYSQL_CONFIG

Log:
/var/log/cdsi/install.log
```

Where reasonable, distinguish:

```text
OK
WARNING
ERROR
```

Not every recoverable problem should abort the full installation.

Example:

DNS not yet configured:

```text
Application installed.
Domain DNS not ready.
SSL configuration postponed.
```

This is preferable to failing the entire deployment.

---

# 13. Preflight First

Before installing infrastructure, run a preflight check.

At minimum inspect:

- OS
- OS version
- CPU architecture
- CPU count
- memory
- disk
- network connectivity
- root/sudo privileges
- ports 80/443
- existing Nginx
- existing PHP
- existing MySQL
- existing Redis
- existing Supervisor

Do not modify the server before critical compatibility checks pass.

---

# 14. Configuration

Do not hardcode environment-specific values throughout scripts.

Prefer central CDSI configuration.

Example:

```text
/etc/cdsi/cdsi.conf
```

Sensitive values should be separated when appropriate:

```text
/etc/cdsi/secrets.env
```

The application `.env` should be generated or updated deliberately and safely.

Existing configuration must not be destroyed without explicit reason.

---

# 15. Database Rules

CDSI application code must use a dedicated MySQL account.

Never use:

```text
root
```

as the normal application database account.

Installer responsibilities:

```text
install MySQL
create database
create CDSI user
generate password
grant minimum required privileges
write configuration
verify application connection
```

Verification must test actual application/database connectivity where possible.

A running MySQL process alone is not sufficient.

---

# 16. Nginx Rules

Nginx configuration changes must be validated before reload.

Always use:

```bash
nginx -t
```

before:

```bash
systemctl reload nginx
```

If validation fails:

- keep the previous working configuration
- report the failure clearly
- do not leave Nginx in a broken state

Use templates where practical.

---

# 17. PHP Rules

PHP installation must follow CDSI Core's actual dependency requirements.

Do not blindly trust this document if the project's Composer requirements differ.

Inspect:

```text
composer.json
composer.lock
```

before deciding required PHP versions/extensions.

The repository itself is the source of truth for application dependencies.

---

# 18. CDSI CLI

The long-term operational entry point is:

```bash
cdsi
```

Initial commands:

```bash
cdsi version
cdsi status
cdsi doctor
cdsi update
```

Future commands may include:

```bash
cdsi install
cdsi backup
cdsi restore
cdsi ssl
cdsi domain
cdsi logs
cdsi restart
```

Do not implement future commands prematurely unless explicitly requested.

---

# 19. Health Checks

`cdsi doctor` should eventually validate three levels.

## Infrastructure

```text
Nginx
PHP-FPM
MySQL
Redis
Supervisor
Queue
```

## Application

```text
Application boot
Database connectivity
Storage
Configuration
Queue
```

## Network

```text
Domain
HTTP
HTTPS
Certificate
```

A service being "running" does not always mean the CDSI Node is healthy.

Prefer end-to-end verification where possible.

---

# 20. Testing Philosophy

Do not consider infrastructure code complete because it "looks correct".

Installer behavior must be tested against real or disposable Linux environments.

Primary integration scenario:

```text
Fresh Ubuntu Server
        ↓
CDSI Installer
        ↓
Infrastructure configuration
        ↓
CDSI Core
        ↓
Domain
        ↓
HTTPS
        ↓
Healthy CDSI Node
```

Important scenarios:

1. Fresh server installation.
2. Installer run twice.
3. Server reboot.
4. Existing Nginx.
5. DNS not yet configured.
6. Partial installation failure.
7. Service unavailable.
8. Incorrect configuration.
9. `cdsi doctor`.

---

# 21. Current Milestone

## Milestone 1

The current implementation priority is:

```text
Installer Skeleton
Logger
Preflight
Error Handling
```

Unless the user explicitly changes the milestone, DO NOT jump ahead and implement the entire infrastructure stack.

Milestone 1 should produce:

```bash
sudo ./installer/install.sh
```

with useful output such as:

```text
CDSI Installer

CDSI Preflight Check
────────────────────────

OS              Ubuntu 24.04       OK
Architecture    x86_64             OK
Memory          3.8 GB             OK
Disk            42 GB              OK
Port 80         Available          OK
Port 443        Available          OK

Nginx           Not Installed
PHP             Not Installed
MySQL           Not Installed
Redis           Not Installed

Ready to install CDSI.
```

And create:

```text
/var/log/cdsi/install.log
```

Do NOT install Nginx/PHP/MySQL as part of Milestone 1 unless explicitly requested.

---

# 22. Agent Workflow

Before modifying code:

1. Read this `AGENTS.md`.
2. Inspect repository structure.
3. Read relevant existing code.
4. Read existing documentation.
5. Check current git status.
6. Identify the requested milestone/task.
7. Make the smallest coherent change required.

Do not assume architecture that is not present in the repository.

---

# 23. Do Not Over-Engineer

Avoid speculative architecture.

Especially avoid adding:

- abstraction layers with no current use
- complex plugin systems
- multiple OS adapters before needed
- Kubernetes-oriented architecture
- distributed orchestration
- generic provisioning frameworks
- unnecessary dependencies

CDSI is early-stage.

Prefer:

> simple → explicit → testable → replaceable

over:

> generic → abstract → theoretical

---

# 24. Do Not Rewrite Unrelated Code

When working on Installer:

Do not casually refactor:

- authentication
- application models
- routes
- frontend
- unrelated Laravel services
- database schema
- business logic

If a required change crosses subsystem boundaries, explain why before making a large modification.

Keep diffs focused.

---

# 25. Existing Code Wins

When documentation and implementation differ:

1. Inspect current implementation.
2. Determine whether the difference is intentional.
3. Do not silently overwrite existing behavior.
4. Report the discrepancy.
5. Make the minimum safe change.

Do not assume every design document represents already-implemented behavior.

---

# 26. Destructive Operations

Agents must be extremely cautious with commands that can destroy data or configuration.

Do NOT automatically execute destructive operations such as:

```bash
rm -rf
DROP DATABASE
git reset --hard
git clean -fd
php artisan migrate:fresh
php artisan db:wipe
```

unless explicitly required and safe in the current context.

Never destroy user data to make a test pass.

---

# 27. Git Discipline

Before changing files:

```bash
git status
```

Respect existing user changes.

Do not:

- revert unrelated modifications
- overwrite uncommitted user work
- rewrite git history
- force push
- delete branches

unless explicitly requested.

Keep changes scoped to the current task.

---

# 28. Documentation

Infrastructure behavior should be documented when it affects:

- installation
- configuration
- supported environments
- system requirements
- security
- commands
- upgrade paths

Do not document features that do not actually exist.

Documentation must distinguish:

```text
Implemented
Planned
Experimental
```

---

# 29. Completion Report

After completing a task, report:

## Changed

List modified/created files.

## Implemented

Describe what now works.

## Validation

Provide exact commands used or recommended to verify the result.

## Known Limitations

State what is intentionally not supported yet.

## Next Step

Recommend the next logical milestone only.

Do not claim work is complete without verification.

---

# 30. Project Constitution

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

A CDSI user should eventually be able to replace CDSI itself without losing their digital assets.

This is intentional.

> **Software can be replaced.  
> Creator assets must survive.**

---

# 31. Final Engineering Principle

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

The goal is not to build the largest creator platform.

The goal is to make it easier for creators to own their place on the Internet.
