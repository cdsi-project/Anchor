---
name: anchor-install-server
description: Install a CDSI Anchor WordPress node over SSH on one user-authorized, clean, dedicated supported Linux server. Use when the user provides the server and root login and wants the agent to handle target checks, pinned bootstrap, base installation, verification, and handoff. Do not use for shared production hosts, server purchasing, upgrades, uninstall, or unsupported Linux releases.
---

# Anchor Install Server

Install one Anchor node on a clean, dedicated server. The normal MVP result is
an IP-based HTTP WordPress site; a domain and HTTPS are not required.

Read [the installation runbook](references/install-runbook.md) completely
before connecting to or changing a server. Follow its pinned release contract
and verification gates exactly.

## Required input

Collect only what is missing:

- SSH host or public IPv4 address, and a non-default port when applicable.
- Root authentication through an existing SSH agent, SSH config, or a path to
  a private key already present on the user's machine.
- A direct instruction authorizing Anchor installation on that exact server.

Do not ask for a private-key body, password, or passphrase in chat. Password or
passphrase entry may occur only in a user-controlled secure prompt. If the
execution environment cannot provide that, stop and explain the limitation.
If a user already pasted a password or private-key body into chat, do not use,
repeat, retype, or store it. Advise the user to rotate the exposed credential
and provide an existing key path, SSH-agent identity, or a fresh password only
through a user-controlled secure prompt.
Do not ask for a domain merely to complete the base installation.

## Authorization boundary

Treat root access as capability, not ownership or permission. A request such as
"install Anchor on HOST" is sufficient authorization for the reviewed Anchor
base stack on that host. If the user supplied only connection details, obtain
confirmation before the first mutation.

Authorization covers the pinned Anchor bootstrap and the required Nginx,
MySQL-or-MariaDB, PHP-FPM, and WordPress components. It does not cover:

- purchasing or deleting a server;
- changing DNS or provider firewalls;
- changing SSH or root-login policy;
- replacing package repositories or upgrading the operating system;
- installing Redis, Supervisor, or unrelated software;
- issuing a certificate, rebooting, uninstalling, or deleting data.

Obtain separate authorization for any optional action outside the base stack.

## Safety boundary

- Preserve strict SSH host-key checking. On first contact, show the SHA-256
  fingerprint for out-of-band confirmation or explicit first-use acceptance.
  A changed key is a hard stop; never remove it automatically.
- Never use `sshpass`, agent forwarding, command-line or environment secrets,
  `StrictHostKeyChecking=no`, or `UserKnownHostsFile=/dev/null`. Never upload a
  private key to the server.
- Before bootstrap, perform the runbook's read-only clean-server gate. Existing
  web/database workloads, occupied ports 80/443, certificates, WordPress data,
  an unmanaged Anchor path, or ambiguous state are hard stops. Additional
  confirmation cannot waive this MVP gate; cleanup and migration require a
  different workflow.
- Download only the pinned release bootstrap to a protected file and verify its
  SHA-256 before execution. Never pipe network content to a shell, trust a
  mutable branch, disable TLS verification, or trust the tag name alone.
- Never clear package locks, kill package-manager jobs, force DNS, run the
  installer concurrently, invoke `uninstall.sh`, or use destructive recovery.
- Do not wrap Anchor's bounded retries in an unbounded retry loop. After a lost
  connection, re-identify the host and inspect running processes before
  continuing a known idempotent component.

## Credential handling

Database and WordPress installers can print secrets. Run the credential-producing
commands exactly as specified in the runbook so their standard output is not
captured by the agent. Never read, copy, download, quote, or summarize credential
values. Verify only credential filenames, ownership, mode `0600`, and required
field names.

Tell the user to retrieve credentials in their own root SSH terminal from:

- `/root/cdsi-Anchor/password/wordpress.pass`
- `/root/cdsi-Anchor/password/wordpress-beacon.pass`

Do not reveal database credentials unless the user separately requests them in
an appropriate secure channel.

## Completion contract

Do not infer success from a zero exit code or from `scripts/health.sh`, which is
currently a placeholder. Complete the runbook's service, WordPress/database,
credential-metadata, and client-side HTTP checks.

Report in the user's language:

- `not started`, `completed`, `partially completed`, or `failed`;
- the verified target and installed Anchor release;
- site URL and WordPress admin URL;
- required service and public reachability status;
- the two remote credential-file paths without their values;
- HTTPS as `not configured` unless separately completed;
- the failed stage and safe next action when incomplete.

Use `not started` when authentication, target identity, platform support, or the
clean-server gate stops the run before mutation. Use `completed` only when all
base components and local checks pass and the client-side HTTP check succeeds;
HTTPS may remain explicitly `not configured` because it is optional. Use
`partially completed` when the base node passes local checks but public HTTP
fails or cannot be verified. Use `failed` when mutation began but a required
component or local verification did not complete.

When the site is HTTP-only, warn the user not to submit credentials over the
public network until a domain and valid HTTPS certificate are configured. Do
not claim that Anchor provides host hardening, backups, monitoring, or a
production-readiness guarantee.
