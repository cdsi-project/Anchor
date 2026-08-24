# AGENTS.md

# CDSI Anchor Engineering Guide

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
- MySQL / MariaDB
- Redis
- Supervisor
- SSL
- deployment operations

to own a CDSI Node.

Infrastructure complexity should be pushed below the user-facing layer wherever reasonably possible.

---

# 3. Current Development Stage

The project is currently in:

# M0 — Anchor Installer v0.3.3 Integration and Hardening

Current priority:

> Make the implemented WordPress OpenWeb installation path reliable on clean
> and partially configured supported Ubuntu, Debian, and CentOS Stream servers.

The current working baseline already includes:

- a POSIX remote bootstrap that prepares an otherwise unconfigured server and
  hands control to `install.sh`
- preflight, logging, and component orchestration in `install.sh`
- required Nginx, MySQL/MariaDB, PHP-FPM, and WordPress installation followed
  by optional final domain/HTTPS and Certbot setup
- Ubuntu/Debian APT and CentOS DNF package backends with bounded retry
- system-default base stack packages and explicitly bounded EPEL use on CentOS
- strict A/AAAA domain activation with separate active and pending state
- standalone domain and HTTPS configuration, including capability-gated IP TLS
- CDN SHA-256 verification
- final site, WordPress administrator, and Beacon Application Password output
- component and full uninstall workflows

Redis and Supervisor remain independently runnable compatibility scripts, but
they are Ubuntu-only and intentionally hidden from the main menu and Install
All flow.

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

The implemented deployment stack and optional TLS path are:

```text
OS           Ubuntu Server 24.04/26.04 LTS, Debian 13, or CentOS Stream 10
Web          Nginx
Runtime      PHP-FPM; Debian 13 uses PHP 8.4
Database     MySQL on Ubuntu/CentOS; MariaDB 11.8 on Debian 13
SSL          Let's Encrypt / Certbot for verified domains; explicit supported public IPs
OpenWeb      WordPress
Integration  CDSI Beacon WordPress Application Password
```

The following distinctions are mandatory when documenting or changing the
repository:

```text
Required base    Nginx, MySQL/MariaDB, PHP-FPM, WordPress
Optional final   Domain activation, HTTPS, Certbot
Standalone only  Redis, Supervisor
Planned          Composer, CDSI Core deployment, cdsi CLI/doctor
```

The first version intentionally supports a narrow deployment path.

CentOS Stream 10 must keep these explicit boundaries:

- use BaseOS/AppStream for Nginx, MySQL 8.4, PHP-FPM, and required PHP modules
- use EPEL only for Certbot; never enable Remi
- never disable SELinux; when it is enabled, add persistent, recorded WordPress policy state
- modify firewalld only when it is active, and record the exact runtime or
  permanent layer for every Anchor-added service
- use `apache:apache` for WordPress/FPM ownership and the packaged Nginx socket ACL
- keep Redis and Supervisor unavailable on the CentOS route

Debian 13 must keep these explicit boundaries:

- use the system default APT repositories for the base stack
- install `mariadb-server` directly from Debian's default repositories; use the
  `mariadb` service and MariaDB-compatible SQL
- keep the Anchor-owned bind configuration scoped to
  `/etc/mysql/mariadb.conf.d/99-cdsi-anchor.cnf`; do not emit MySQL X settings or
  MySQL-only authentication clauses such as `caching_sha2_password`
- use the default PHP 8.4 stream and resolve versioned extension packages when
  an unversioned metapackage has no candidate
- use the default Certbot 4.0 packages for domain HTTPS; this version does not
  satisfy the Certbot 5.4+ public-IP certificate capability, so preserve HTTP
  for unsupported IP requests
- use `www-data:www-data` for WordPress/FPM ownership
- keep Redis and Supervisor unavailable on the Debian route

Do NOT claim or prematurely implement support for:

- CentOS Stream releases other than 10
- CentOS Linux
- Rocky Linux
- AlmaLinux
- Debian releases other than 13
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

## Anchor Installer

Responsible for server provisioning and the OpenWeb installation lifecycle.

Examples:

- operating system checks
- Nginx, PHP-FPM, MySQL/MariaDB, Certbot, and WordPress installation
- domain and service configuration
- generated credentials and final access reporting
- safe reruns, uninstall, and infrastructure verification

## Installed WordPress OpenWeb Node

WordPress owns content-management behavior after provisioning. Anchor may
configure WordPress and create the Beacon Application Password, but installation
scripts must not absorb CMS business logic.

## Future CDSI Core

Composer and CDSI Core deployment are planned, not current behavior. Do not
claim or implement them as part of M0 without an explicit scope change.

Do NOT put CDSI business logic into installation scripts.

---

# 6. Installer Structure

Current installer structure:

```text
Anchor/
├── bootstrap.sh                  # remote new-server bootstrap
├── install.sh
├── uninstall.sh
├── SHA256SUMS
├── lib/
│   ├── apt.sh
│   ├── dnf.sh
│   ├── domain.sh
│   ├── bootstrap.sh
│   ├── common.sh
│   ├── logger.sh
│   ├── packages.sh
│   ├── platform.sh
│   ├── services.sh
│   ├── system.sh
│   └── wordpress-access.sh
├── scripts/
│   ├── dispatch.sh
│   ├── check-env.sh              # public dispatcher
│   ├── install-*.sh              # public dispatchers
│   ├── configure-domain.sh       # independent domain lifecycle
│   ├── configure-https.sh        # independent domain/IP TLS lifecycle
│   ├── common/                   # shared component implementations
│   ├── ubuntu/                   # implemented platform route
│   ├── debian/                   # implemented Debian 13 platform route
│   ├── centos-stream/            # implemented platform route
│   ├── configure.sh
│   └── health.sh
├── config/
├── templates/                     # includes Certbot deploy hook
├── tests/
└── docs/
```

Root `bootstrap.sh` is a small POSIX remote entry point. It may validate the
supported platform, refresh metadata for the configured system repositories,
install the minimum download/runtime tools, and obtain or safely fast-forward a
bootstrap-managed Anchor checkout. It must not replace repository configuration,
perform a full operating-system upgrade, enable EPEL early, overwrite an
unmanaged checkout, or absorb component installation logic. `lib/bootstrap.sh`
has a separate internal role: it transfers checked-out POSIX entry points into
Bash.

`install.sh` owns user interaction and orchestration. Public component commands
under `scripts/` detect the operating system and dispatch to a platform route.
The `ubuntu/`, `debian/`, and `centos-stream/` routes are implemented. Their
wrappers invoke the shared implementations under `scripts/common/`. Shared
primitives belong under `lib/`. Keep these layers small and
responsibility-focused.

The Install All path must establish the usable base site before asking for a
domain: Nginx, database, PHP-FPM, then WordPress. Domain activation and HTTPS are
one optional final step. Empty input or EOF skips that step without changing
active or pending domain state. DNS, ACME, or public-IP certificate limitations
must not turn a completed base installation into a failure; report the optional
step as skipped, deferred, or failed, then print the final site and credentials.
Signal-derived exits must still interrupt the installer.

---

# 7. Script Convention

The public root `bootstrap.sh` must remain POSIX `/bin/sh` compatible because it
runs before Bash and Git can be assumed. Its documented download URL must use
HTTPS and a versioned release tag, never a mutable branch. Gitee is the primary
domestic clone source and GitHub is the fallback.
Failed downloads must remain staged outside the final checkout, and an existing
checkout may be updated only when it is explicitly bootstrap-managed, uses an
approved remote, has no local changes, and can fast-forward.

Every public script directly under `scripts/` must remain independently
runnable. `install.sh` invokes component scripts as child processes and relies
on their exit codes:

```text
0        component completed or was safely skipped
10       optional configuration was safely deferred
other    component failed; orchestration must report and stop as appropriate
```

Scripts may source shared functions from `lib/`, but must load the runtime they
need when executed directly. Component scripts must inspect existing system
state before making changes and verify the result they own.

Never assume the server is always completely clean.

`scripts/configure-domain.sh` and `scripts/configure-https.sh` are public,
independently runnable lifecycle commands. Domain or certificate changes must
not require reinstalling WordPress or the base services.

---

# 8. Idempotency

Installer operations MUST be designed to be idempotent wherever possible.

Running:

```bash
sudo ./install.sh
```

twice must not destroy an existing CDSI installation.

Expected behavior:

```text
Nginx             Installed        SKIP
PHP               Installed        SKIP
Database          Exists           SKIP
WordPress         Installed        SKIP / VERIFY
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

- use MySQL/MariaDB root as the CDSI application user
- use `chmod -R 777`
- expose secrets in logs
- hardcode production passwords
- silently ignore failed commands
- disable TLS verification
- download executable code over plain HTTP without verifying a repository-pinned cryptographic checksum
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
- existing MySQL/MariaDB
- existing Redis/Supervisor when present as legacy or standalone components

Do not modify the server before critical compatibility checks pass.

The active preflight is `scripts/check-env.sh` and accepts only Ubuntu
24.04/26.04, Debian 13, or CentOS Stream 10 on `x86_64`/`aarch64`. Every default
component script enforces the same platform guard when run independently.

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

`scripts/configure.sh` currently provides the standalone `/etc/cdsi`
configuration helper; it is not part of the main WordPress installation flow.
Future application configuration such as `.env` must be generated or updated
deliberately and safely.

Existing configuration must not be destroyed without explicit reason.

IP-mode WordPress installation must validate automatically discovered addresses
as globally routable IPv4. Reuse an existing public WordPress IP URL before
calling external discovery endpoints, reject private/reserved endpoint output,
and require `CDSI_SERVER_IP` or an explicit private-IP opt-in when public
detection is unavailable.

Domain state has two meanings that must never be conflated:

```text
config/domain          DNS-verified and active
config/domain.pending  requested but not safe to activate yet
```

Every requested domain must have at least one A record, and every returned A
record must equal the server IPv4. AAAA is optional, but every returned AAAA
record must belong to a global IPv6 configured on the server. If strict DNS
verification fails, write the normalized request to `config/domain.pending`
and leave the current WordPress URL and Nginx site unchanged. A fresh IP-mode
installation remains available at `http://<server IP>`.

Use `scripts/configure-domain.sh DOMAIN` to activate a verified domain and
`scripts/configure-domain.sh --clear` to return to IP HTTP mode. Use
`scripts/configure-https.sh [DOMAIN]` for domain TLS and
`scripts/configure-https.sh --ip` only for an explicit public-IP request.

Public IP certificates require a globally routable IPv4, system Certbot 5.4 or
newer with both `--ip-address` and `--preferred-profile`, and the Let's Encrypt
`shortlived` profile. If any capability is absent, preserve HTTP. Do not claim
that the current CentOS Stream EPEL Certbot necessarily supports IP
certificates. Debian 13's default Certbot 4.0 supports domain certificates but
does not meet the public-IP requirement. Do not install an untrusted certificate
as a substitute, and do not send IP certificate orders to a fallback CA.

The optional `CDSI_ACME_FALLBACK_SERVER` is selected only when the primary ACME
directory cannot be reached after bounded probes. It must never be selected in
response to DNS, CAA, authorization, validation, account, or rate-limit errors.
ZeroSSL fallback requires both `CDSI_ACME_FALLBACK_EAB_KID` and
`CDSI_ACME_FALLBACK_EAB_HMAC_KEY`; EAB values are secrets and must not be
persisted in repository files or logs.

---

# 15. Database Rules

The installed WordPress site must use a dedicated MySQL or MariaDB account.

Never use:

```text
root
```

as the normal application database account.

Installer responsibilities:

```text
install the platform database server
create database
create dedicated application user
generate password
grant minimum required privileges
write WordPress configuration
verify WordPress/database connectivity
```

Verification must test actual application/database connectivity where possible.

A running database process alone is not sufficient.

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

Successful Nginx, MySQL/MariaDB, and PHP-FPM installation requires both an active
runtime service and systemd boot enablement. Reconcile and verify both states on
fresh installs and fast reruns. When a certificate is configured, the packaged
`certbot.timer` or `certbot-renew.timer` must also be active and enabled; an
absent or inactive renewal timer is a certificate-configuration failure, not a
successful manual-renewal fallback.

Certificate deployment must validate the issued SANs, expiry, and private-key
match before changing WordPress or Nginx. Validate Nginx before reload and use a
deploy hook so successful renewals safely reload Nginx.

---

# 17. PHP Rules

Use the default PHP stream available from the supported operating system. Do not
add third-party PHP PPAs or Remi, force a global PHP alternative, or assume a
versioned package exists without resolving the platform runtime. On CentOS, PHP
packages and extensions must remain in BaseOS/AppStream; the PHP installer must
not enable EPEL. Debian 13 uses PHP 8.4 from the default repository; when an
unversioned extension package has no candidate, use the matching versioned
system package rather than a third-party repository.

The fresh-install path requires the extensions used by WordPress and Beacon's
OpenWeb workflow, including `mysqli`, cURL, XML, mbstring, ZIP, GD, Redis, and
OPcache. GD is the supported image-processing extension; do not install Imagick.
Checks for an existing PHP installation must not claim extensions were
installed unless they were actually verified.

---

# 18. CDSI CLI

The `cdsi` CLI is not implemented. The long-term operational entry point is:

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

`scripts/health.sh` is currently a placeholder. A future `cdsi doctor` should
validate three levels.

## Infrastructure

```text
Nginx
PHP-FPM
MySQL/MariaDB
WordPress
Nginx/database/PHP-FPM runtime active and boot enabled
Certbot renewal timer active and enabled when TLS is configured
Redis/Supervisor when explicitly installed
```

## Application

```text
Application boot
Database connectivity
Storage
Configuration
Beacon Application Password presence (never print the secret)
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
Fresh supported Linux server
        ↓
CDSI Installer
        ↓
Infrastructure configuration
        ↓
WordPress OpenWeb node
        ↓
Optional final domain/HTTPS prompt
  Enter/EOF        domain or ip
      ↓                 ↓
 keep current      configure/attempt
      └────────┬────────┘
               ↓
Final access and credentials report
        ↓
Healthy CDSI Node
```

Important scenarios:

1. Fresh server installation, including a server without Git or Bash prepared
   through root `bootstrap.sh`.
2. Installer run twice.
3. Server reboot.
4. Existing Nginx.
5. DNS not yet configured.
6. Requested domain has a wrong A or AAAA record and remains pending.
7. Empty input and EOF skip final domain/HTTPS configuration without changing
   active or pending domain state.
8. Deferred or failed optional HTTPS still produces the base-install access and
   credential report.
9. Domain is configured or cleared independently without reinstalling services.
10. Public IP HTTPS on capable and incapable Certbot versions.
11. Primary ACME directory is unreachable with and without an explicit fallback.
12. Partial installation failure.
13. Service unavailable or disabled at boot.
14. Incorrect configuration.
15. Uninstall dry-run and confirmed uninstall.
16. Future health/doctor behavior when implemented.

---

# 21. Current Milestone

## M0 Integration and Hardening

The installer skeleton milestone is complete. The current implementation must
be treated as an existing four-component base path with an optional final
Certbot/domain/HTTPS step, not as a plan to start over.

Implemented:

```text
POSIX new-server bootstrap with Gitee/GitHub retrieval
Preflight and logging
Nginx / MySQL or MariaDB / PHP-FPM / WordPress required base installation
Optional final Certbot and domain-aware HTTP/HTTPS setup
Strict A/AAAA activation with active/pending domain state
Independent domain clear/activate and domain/IP HTTPS commands
Directory-only ACME fallback and capability-gated short-lived IP certificates
Active/enabled service and certificate-renewal timer verification
APT/DNF package installation with bounded retry
CentOS Stream 10 platform route with MySQL 8.4 and explicit EPEL boundaries
Debian 13 platform route with MariaDB 11.8, PHP 8.4, and Certbot 4.0 boundaries
Pinned SHA-256 verification for WP-CLI and WordPress downloads
WordPress administrator and Beacon Application Password provisioning
Final access report
Component and full uninstall
```

Standalone but excluded from default orchestration:

```text
Redis
Supervisor
```

Not implemented:

```text
Composer and CDSI Core deployment
cdsi CLI / doctor / update
resume checkpoints
complete server backup and restore
automated fresh-server/reinstall/reboot integration coverage in this repository
```

Current work should prioritize clean-server regression testing, safe reruns,
partial-failure recovery, DNS/certificate degradation, upgrade compatibility,
uninstall safety, and real health checks. Do not expand into later CDSI product
features unless explicitly requested.

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

`uninstall.sh` is package/path based and does not track provenance. Every
single-component or full uninstall must be treated as a dedicated-server
operation: preview the exact same target with `--dry-run`, disclose shared
package/data/certificate impact, and never describe it as removing only packages
that Anchor originally installed.

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
