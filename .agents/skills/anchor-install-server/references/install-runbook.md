# Anchor Server Installation Runbook

Use this runbook only for a single clean, dedicated server authorized by the
user. Commands in this document are intended to run inside an authenticated
root shell unless explicitly described as client-side checks.

## Reviewed release

These values form one release contract and must stay synchronized:

```text
ANCHOR_RELEASE=v0.3.5
ANCHOR_RELEASE_COMMIT=06ce8445c1835215dc822c34255962420b8d690e
ANCHOR_BOOTSTRAP_SHA256=ed33762b3ec1e052a886b4fb0181d11a7a9bf64788efb86c228d6ae0973a7d63
ANCHOR_INSTALL_DIR=/root/cdsi-Anchor
```

Official bootstrap URLs, in order:

```text
https://gitee.com/cdsi/anchor/raw/v0.3.5/bootstrap.sh
https://raw.githubusercontent.com/cdsi-project/Anchor/v0.3.5/bootstrap.sh
```

The `v0.3.5` tag is annotated but not cryptographically signed. Require both
the bootstrap checksum and the checked-out commit. A mismatch is a hard stop.

## Establish SSH identity

1. Validate the host as a hostname or IP address and the port as an integer in
   `1..65535`. Pass them as SSH arguments; do not interpolate them into remote
   shell source.
2. Use `root` with an existing SSH agent, SSH configuration, a user-supplied
   private-key path, or password entry in a user-controlled secure prompt. Do
   not read key contents or use a password already exposed in chat. If the
   environment cannot provide a secure prompt, require key-based access.
3. Confirm the server host-key SHA-256 fingerprint. If an existing known-hosts
   entry changed, stop and ask the user to verify the replacement out of band.
4. Record the host, port, host-key fingerprint, and `/etc/machine-id` for this
   operation. Recheck them after every reconnect.

## Read-only clean-server gate

Run this before downloading bootstrap or refreshing package metadata. Collect
evidence without reading credential files:

- `id -u` is `0`.
- `/etc/os-release` is exactly Ubuntu 24.04 or 26.04, Debian 13, CentOS Stream
  10, or openSUSE Leap 16.0.
- `uname -m` is `x86_64` or `aarch64`, and PID 1 is systemd.
- At least one CPU is present. Report and obtain confirmation for less than 1
  GB RAM or less than 10 GB free on the root filesystem.
- System time is plausible; DNS and outbound HTTPS work; the platform package
  manager is not broken or already running.
- Ports 80 and 443 are not occupied.
- Nginx, Apache, PHP, MySQL, MariaDB, WordPress, `/var/lib/mysql`,
  `/var/www/wordpress`, existing ACME certificates, and an active non-Anchor
  workload are absent.
- `/root/cdsi-Anchor` does not exist. An existing path, including a managed
  Anchor checkout, is outside this clean-server MVP and requires review.
- Configured package repositories do not include conflicting third-party PHP,
  Nginx, or database sources.

Stop on an unsupported or ambiguous result. Do not accept a warning from the
later Anchor preflight as permission to overwrite an existing workload. The
user cannot waive this clean-server gate by saying "proceed anyway"; require a
clean target because cleanup and migration are outside this Skill.

Before mutation, tell the user the verified target and that Anchor will refresh
package metadata, install and enable the base services, create a local database
and WordPress site, write under `/root/cdsi-Anchor` and `/var/www/wordpress`,
and may adjust active firewalld/SELinux state as implemented by Anchor. Proceed
without another prompt only when the user already directly authorized this
installation on the exact target.

## Download and verify bootstrap

Use a protected temporary file. Prefer Gitee; use GitHub only when the Gitee
download itself fails. If downloaded bytes fail verification, discard them and
stop rather than execute them.

```sh
(
  set -eu
  umask 077
  ANCHOR_BOOTSTRAP_FILE="$(mktemp /root/anchor-bootstrap.XXXXXX)"
  ANCHOR_BOOTSTRAP_SHA256="ed33762b3ec1e052a886b4fb0181d11a7a9bf64788efb86c228d6ae0973a7d63"
  trap 'rm -f -- "$ANCHOR_BOOTSTRAP_FILE"' 0 1 2 15

  if ! curl --proto '=https' --tlsv1.2 -fsSL \
    'https://gitee.com/cdsi/anchor/raw/v0.3.5/bootstrap.sh' \
    -o "$ANCHOR_BOOTSTRAP_FILE"; then
    curl --proto '=https' --tlsv1.2 -fsSL \
      'https://raw.githubusercontent.com/cdsi-project/Anchor/v0.3.5/bootstrap.sh' \
      -o "$ANCHOR_BOOTSTRAP_FILE"
  fi

  printf '%s  %s\n' "$ANCHOR_BOOTSTRAP_SHA256" "$ANCHOR_BOOTSTRAP_FILE" \
    | sha256sum -c -
  sh "$ANCHOR_BOOTSTRAP_FILE" --no-start
)
```

If curl is absent but wget is available, download the same URLs to the same
temporary file and perform the identical checksum check. If neither exists,
install only curl and CA certificates from the already configured system
default repository after the clean-server gate; do not change repository
configuration or upgrade the system.

Verify the resulting checkout before running any Anchor component:

```sh
test "$(git -C /root/cdsi-Anchor rev-parse HEAD)" \
  = '06ce8445c1835215dc822c34255962420b8d690e'
test -z "$(git -C /root/cdsi-Anchor status --porcelain)"
```

## Run preflight

From `/root/cdsi-Anchor`, run:

```sh
bash scripts/check-env.sh
```

Interpret status `0` as ready, `1` as warnings requiring review, `2` as a hard
failure, and any other status as an unexpected failure. Do not lose the status
through `set -e` or a compound `&&` command. Continue after status `1` only when
every warning is understood and no clean-server invariant is violated.

## Install the base node

Run the public component entries sequentially, waiting for each one to finish
and requiring status `0` before starting the next:

```sh
cd /root/cdsi-Anchor
bash scripts/install-nginx.sh
bash scripts/install-mysql.sh >/dev/null
bash scripts/install-php.sh
env CDSI_INSTALL_CONTEXT=all CDSI_SERVER_IP='PUBLIC_IPV4' \
  bash scripts/install-wordpress.sh >/dev/null
```

Replace `PUBLIC_IPV4` only with a validated globally routable IPv4 belonging to
the server. Do not derive it blindly from an unvalidated SSH host string. When
the SSH endpoint is a hostname, resolve and compare it with the server's public
address before setting `CDSI_SERVER_IP`.

The output suppression on the database and WordPress steps is mandatory because
those scripts may print credentials. Keep stderr visible for failures. Do not
redirect their combined output to a file, `tee`, a transcript, or an Agent log.

This sequence is the supported non-interactive equivalent of the required
Install All base order: Nginx, MySQL/MariaDB, PHP-FPM, then WordPress. Do not
install Certbot when no domain was provided. The site should remain available
at `http://PUBLIC_IPV4`.

## Optional domain and HTTPS

Do not block the base MVP on a domain. Run this section only if the user
separately supplies a valid bare domain and authorizes certificate issuance,
including CA terms and public certificate-transparency records.

First verify that every A record equals the server IPv4 and every present AAAA
record belongs to a global IPv6 configured on the server. Then run:

```sh
cd /root/cdsi-Anchor
bash scripts/configure-https.sh example.com
```

Status `10` means safely deferred: preserve the working HTTP site and report
`base installed; HTTPS deferred`. Do not retry DNS, authorization, CAA, or rate
limit failures automatically. Never use a DNS-force option without a separate,
explicit proxy or load-balancer decision from the user.

## Post-install verification

Run independent checks; `scripts/health.sh` is not evidence because it is a
placeholder in this release.

1. Verify `nginx -t`.
2. Source `/root/cdsi-Anchor/lib/platform.sh`, call `cdsi_platform_init`, derive
   PHP-FPM with `cdsi_php_fpm_version` and `cdsi_php_service_name`, and verify
   the Nginx, database, and PHP-FPM units are both active and enabled.
3. Confirm the database listener is loopback-only.
4. Run both commands successfully:

   ```sh
   wp --path=/var/www/wordpress core is-installed --allow-root
   wp --path=/var/www/wordpress db check --allow-root
   ```

5. Read only the public site URL:

   ```sh
   wp --path=/var/www/wordpress option get home --allow-root
   ```

6. Confirm `password/wordpress.pass` and
   `password/wordpress-beacon.pass` exist, are regular files owned by root, have
   mode `0600`, and contain the expected field names without printing values:

   ```sh
   cd /root/cdsi-Anchor
   test "$(stat -c '%a:%U' password/wordpress.pass)" = '600:root'
   test "$(stat -c '%a:%U' password/wordpress-beacon.pass)" = '600:root'
   grep -q '^user:.' password/wordpress.pass
   grep -q '^pass:.' password/wordpress.pass
   grep -q '^user:.' password/wordpress-beacon.pass
   grep -q '^name:.' password/wordpress-beacon.pass
   grep -q '^app_id:.' password/wordpress-beacon.pass
   grep -q '^uuid:.' password/wordpress-beacon.pass
   grep -q '^pass:.' password/wordpress-beacon.pass
   ```
7. From the server, request the final URL and require an HTTP success or expected
   redirect. Then request the same URL from the Agent's client side so a cloud
   firewall or public-routing problem cannot be mistaken for success. If the
   Agent environment cannot perform the client-side request, report public
   reachability as unverified rather than substituting another server-side test.
8. When HTTPS was configured, additionally verify external HTTPS, expected
   certificate SANs and expiry, key match, redirect behavior, and an active and
   enabled Certbot renewal timer.

Do not reboot as part of the MVP. Report boot persistence as configured but not
reboot-tested.

## Failure and reconnect handling

- Report the exact failed component and its exit status. Inspect redacted
  diagnostics and `/var/log/cdsi/install.log` when present; never read password
  files for diagnosis.
- Do not start a second installer while an Anchor or package-manager process is
  active. Do not delete lock files or kill unattended package work.
- After SSH loss, recheck host key, `/etc/machine-id`, running processes, and
  completed component state. Rerun only the failed or incomplete public
  component after its state is understood.
- Never recover by uninstalling, deleting the database or WordPress directory,
  resetting Git, or replacing system configuration wholesale.

## Handoff

Return the verified site URL, admin URL, Anchor release, service states, and
external reachability. Point the user to the two credential files in a secure
root terminal without revealing their contents. For HTTP-only installs, clearly
state that HTTPS is not configured and credentials should not be submitted over
the public network.
