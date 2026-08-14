# Home Assistant Supervised on CachyOS

Implementation plan for migrating the existing Home Assistant Supervised
installation from `homeassistant.local` to the CachyOS x86_64 host at
`192.168.2.55`.

> **Porting note:** This runbook combines reusable procedure with a historical
> audit of one host. `homeassistant.local`, `maccie`, `192.168.2.55`, interface
> names, USB paths, versions, backup names, and checksums are examples from that
> audit. Inventory the actual source and target, substitute their values, and do
> not run target-specific cutover commands unchanged.

> **Status:** target restore and reboot validation complete on `maccie`;
> external network cutover and final acceptance remain intentionally incomplete.
> This is a technically feasible, unsupported Home Assistant deployment. It
> intentionally avoids a VM and preserves Supervisor plus Supervisor-managed
> apps by using rootful Docker on the CachyOS host.

## 0. Implemented staging bundle

The tracked `homeassistant-supervised-cachyos/` bundle is the reviewed local
host integration. It contains the CachyOS dependency/configuration contract,
verified OS Agent provenance, Supervisor launcher, AppArmor loader and profile,
systemd units, installation script, and preflight script. It is installed on the
target under `/usr/local/lib/homeassistant-supervised/` and
`/usr/local/src/homeassistant-supervised-cachyos/`.

The target has Docker `29.7.2`, OS Agent `1.11.0`, Supervisor `2026.07.5`,
AppArmor enforcement, the journal gateway Unix socket, and a restored Core
`2026.7.2` workload. The source produced full backup `2dfd8dcc` (22,131,619,840
bytes; SHA-256
`6e4260fc750b44f2b979bb17dc36edfc810421627f2d883917d0c936d409c49e`) containing
18 apps and `share`, `ssl`, and `media`. The independent source recovery archive
is `/root/hassio-recovery-2026-08-13.tar.zst` (SHA-256
`668c3802e60abfb5e1c4cf13a811311356afbfc38cb75e5fe7600e1c57f7d7f5`).

The source Supervisor and its managed containers remain stopped. The target has
been rebooted twice; after the second reboot all required host services,
Supervisor, Core, and the preflight pass automatically. Restored add-ons have
been set to manual boot and isolated; only individually validated internal apps
are running. Supervisor reports healthy with only the expected unsupported OS
condition. The external cutover, missing Zigbee coordinator, and final workload
acceptance remain open.

### 0.1 Execution record and current gates

Completed evidence:

- Full backup generated through the source Supervisor and restored through the
  target Supervisor; the restore job completed without errors.
- Core HTTP landing page returns `200`; the restored recorder database is
  approximately 890 MiB and passes SQLite integrity check.
- Supervisor reports all 18 restored apps and no unhealthy resolution issues.
- Core, Mosquitto, Vaultwarden, Node-RED, Gitea, NGINX, SSH, Grocy, Barcode
  Buddy, Syncthing, Transmission, and VNC Viewer were started and exercised
  internally; the validated apps reached their expected running/healthy state.
- The target currently has no ConBee II or `/dev/serial/by-id` device.
  Zigbee2MQTT is therefore kept stopped. Tailscale and other duplicate external
  identities are also kept stopped unless explicitly tested.
- A profile-copy fallback was added to the tracked AppArmor loader because a
  full restore can replace the data-directory copy of `hassio-supervisor`; the
  bundled profile is now also kept under
  `/usr/local/lib/homeassistant-supervised/apparmor/`.
- The target log path was repaired after diagnosis: CachyOS lacked
  `libmicrohttpd`, so `systemd-journal-gatewayd.service` exited while leaving
  its socket file present. Installing
  `cachyos-core-v3/libmicrohttpd 1.0.10-1.1`, resetting the failed unit, and
  recreating containers after adding the Docker journald tag restored
  `/supervisor/logs`, `/core/logs`, and add-on logs.

Remaining gates are the external router/DNS/TLS cutover, validation of
unavailable LAN devices and custom integrations, final hardware decision,
rollback exercise, and the agreed observation period. Do not mark the source
retired until these are complete.

## 1. Outcome and constraints

The target architecture is:

```text
CachyOS host (192.168.2.55)
├── systemd
├── NetworkManager + systemd-resolved
├── D-Bus + dbus-broker
├── UDisks2 + udev
├── AppArmor
├── rootful Docker Engine + containerd + runc
├── Home Assistant OS Agent (upstream first; fork only if required)
├── adapted hassio-supervisor.service
└── Supervisor container
    ├── Home Assistant Core
    ├── built-in Supervisor plugins
    └── Supervisor-managed apps/add-ons
```

The objective is to retain:

- the Supervisor UI and API;
- Home Assistant Core state and history;
- Supervisor-managed apps/add-ons;
- add-on configuration and data;
- the existing integrations, custom components, secrets, dashboards,
  automations, and scripts;
- the existing external access model after DNS/port-forward changes.

The objective is **not** to reproduce Home Assistant OS itself. The CachyOS host
will not provide HAOS/RAUC operating-system updates, HAOS data-disk migration,
or HAOS boot management.

### Non-goals

- Do not copy the Docker data root or running container IDs from the old host.
- Do not install the old Debian `.deb` blindly on CachyOS.
- Do not use rootless Docker/Podman for Supervisor.
- Do not shut down the old host for final cutover or remove its service
  ownership until the new instance has passed the acceptance checklist. A brief,
  controlled stop is allowed when creating the consistent source filesystem
  archive.
- Do not restore the newest discovered archive without checking its backup type:
  `8d0234a5.tar` is a **partial** backup.

### Explicit migration-window risk acceptance

Keep the source authoritative until the infrastructure-only staging gate passes.
Do not restore stateful apps while the source remains live. The migration must
use separate gates:

1. **Infrastructure gate:** validate the empty Supervisor, Core landing page,
   Docker, AppArmor, D-Bus, OS Agent, networking, and automatic service startup.
2. **Maintenance window:** stop or isolate the source, create the final
   consistent full backup and filesystem archive, then restore the target.
3. **Workload gate:** validate restored Core, apps, integrations, and hardware
   while external access and duplicate service identities remain disabled.
4. **Cutover:** only after workload acceptance, move service ownership and
   shared hardware. If rollback is required, discard or explicitly reconcile
   target writes; do not silently resume the old state and lose the accepted
   data window.

## 2. Findings from the target-host audit

The target is an x86_64 CachyOS installation:

- Host: `maccie`
- Address: `192.168.2.55`
- Kernel: `7.1.8-arch1-3`
- RAM: approximately 15 GiB
- Free disk: approximately 182 GiB on Btrfs
- systemd: `261.2`
- cgroups: v2
- Network: NetworkManager over `enp0s20f0u8u1` Ethernet at 100 Mb/s; `wlan0` is
  disconnected
- KVM exists, but this plan does not use it

Already present and working:

- systemd;
- NetworkManager;
- systemd-resolved;
- D-Bus and dbus-broker;
- UDisks2;
- jq, curl, Bash, iproute2, `nmcli`, `resolvectl`, `busctl`, `journalctl`, and
  `apparmor_parser`;
- kernel support/modules for cgroups, overlayfs, bridge networking, veth, TUN,
  NAT, iptables, and seccomp;
- systemd journal gateway binaries and the `libmicrohttpd` runtime package;
- `bluez`, `cifs-utils`, and `nfs-utils` packages.

At the initial audit, the following were missing or incomplete:

- Docker Engine, containerd, and runc;
- OS Agent;
- the journal gateway socket;
- the Supervisor data directory and host integration;
- a ConBee II on the target.

The staging implementation now provides:

- Docker `29.7.2`, containerd `2.3.3`, runc `1.5.1`, rootful Docker, journald
  logging, overlay2, cgroups v2, and validated bridge/veth/published-port
  networking;
- OS Agent `1.11.0` with successful `io.hass.os` introspection;
- AppArmor enabled and the `hassio-supervisor` profile loaded in enforce mode;
- `/run/systemd-journal-gatewayd.sock` and enabled baseline services;
- Supervisor `2026.07.5`, built-in plugins, Core `2026.8.1`, and a successful
  API ping.

Remaining before restore are the source full backup, the consistent filesystem
archive, ConBee II transfer, workload acceptance, and final network cutover. The
AUR packages are not used; the local bundle is built from reviewed upstream
inputs.

## 3. Upstream interfaces to preserve

The upstream repositories are:

- Supervisor: <https://github.com/home-assistant/supervisor>
- OS Agent: <https://github.com/home-assistant/os-agent>
- supervised installer: <https://github.com/home-assistant/supervised-installer>
- operating system: <https://github.com/home-assistant/operating-system>

The OS Agent owns the D-Bus name `io.hass.os` and object path `/io/hass/os`.
Preserve these names and the upstream method/property signatures so Supervisor
can use the agent without a Supervisor fork.

The agent currently exposes these relevant interfaces:

- `io.hass.os`
- `io.hass.os.AppArmor`
- `io.hass.os.CGroup`
- `io.hass.os.System`
- `io.hass.os.DataDisk`
- `io.hass.os.Config.Swap`
- board-specific interfaces

The Supervisor also talks directly to ordinary host D-Bus services:

- `org.freedesktop.systemd1`
- `org.freedesktop.NetworkManager`
- `org.freedesktop.resolve1`
- `org.freedesktop.hostname1`
- `org.freedesktop.login1`
- `org.freedesktop.timedate1`
- `org.freedesktop.UDisks2`

A forked OS Agent cannot replace those services. Keep them working on the
CachyOS host.

## 4. Phase 0 — protect and inventory the source installation

Perform these steps on `homeassistant.local` before making any migration change.

### 4.1 Record versions and workload

Record:

```text
Home Assistant Core version
Supervisor version
OS Agent version
Docker version
Machine type
Installed apps/add-ons and versions
Custom repositories
Host ports and router port forwards
USB/serial device paths
```

The inspected source is currently:

- Debian 12 x86_64;
- Home Assistant Supervised;
- data directory `/usr/share/hassio`;
- machine type `qemux86-64`;
- Supervisor `2026.07.5` in the latest backup metadata;
- Home Assistant Core `2026.7.2` in the latest backup metadata;
- four CPU cores and approximately 15 GiB RAM;
- ConBee II at
  `/dev/serial/by-id/usb-dresden_elektronik_ingenieurtechnik_GmbH_ConBee_II_DE2471038-if00`;
- many Supervisor apps, including Mosquitto, Zigbee2MQTT, Node-RED, NGINX,
  Vaultwarden, Immich, WireGuard, Gitea, Syncthing, UniFi, Transmission, Music
  Assistant, and others.

Treat the app list as a source inventory, not as a guarantee that every app is
still available for the target architecture or current Core release.

### 4.2 Create a new full backup

From the Home Assistant UI:

1. Open **Settings → System → Backups**.
2. Create a **full** backup.
3. Include Home Assistant and every app/add-on whose state must be retained.
4. Include `ssl` and `share`.
5. Use encryption if the backup will cross an untrusted transport.
6. Download the backup to a separate machine or copy it off the source host.
7. Verify its SHA-256 checksum and record the backup name, timestamp, and size.
8. If the UI cannot create a full backup, stop and resolve that before
   migration. Do not substitute a partial backup without documenting the missing
   components.

Also preserve an independent, metadata-preserving copy of the complete
Supervisor state. The full `/usr/share/hassio` tree is required; do not rely on
a selective list of familiar directories because current and future Supervisor
versions may store important state under additional paths such as `apps/data`,
`app_configs`, `media`, or `mounts`.

Create the UI backup first, then stop Supervisor. The `docker ps` check below
must show no Supervisor-managed container still running or writing state; if any
remain, stop them through the supported shutdown procedure before making the
filesystem copy:

```bash
sudo systemctl stop hassio-supervisor.service
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
sudo tar --acls --xattrs --numeric-owner --sparse \
  -C / -cpf /mnt/recovery/hassio-state-<timestamp>.tar \
  usr/share/hassio etc/hassio.json
sha256sum /mnt/recovery/hassio-state-<timestamp>.tar
```

Use an equivalent Btrfs snapshot or metadata-preserving copy if that is more
appropriate for the source. Store the archive on a separate disk or host, verify
its checksum after transfer, and restart the source only after the copy is
complete. The full Supervisor backup remains the primary restore artifact; this
complete filesystem archive is the secondary recovery artifact and should be
made while Home Assistant is stopped for exact database consistency.

### 4.3 Record external dependencies

Before cutover, list integrations that depend on the old host address or network
identity:

- MQTT clients and brokers;
- Zigbee2MQTT/ZHA serial paths;
- ESPHome devices;
- NGINX and TLS certificates;
- WireGuard/Tailscale peers;
- reverse proxies and router forwards;
- external webhooks;
- DNS records and DHCP reservations;
- mDNS/LLMNR names;
- integrations that point at `192.168.2.2` or `homeassistant.local`.

Reserve `192.168.2.55` in DHCP or configure the intended static address before
cutover. Do not assign the same address to both hosts simultaneously.

## 5. Phase 1 — prepare CachyOS without installing Home Assistant

All package installation and system changes in this section require root. Use a
local terminal or an SSH session with a reliable way to recover if networking
restarts.

### 5.1 Update and install host packages

Review the transaction first, then install the CachyOS equivalents:

```bash
sudo pacman -Syu
sudo pacman -S --needed \
  docker containerd runc \
  networkmanager systemd dbus dbus-broker \
  libmicrohttpd \
  udisks2 apparmor \
  jq curl wget bash \
  iproute2 iptables nftables \
  bluez cifs-utils nfs-utils
```

Do not install `docker-ce`, `network-manager`, or `nfs-common`; those are Debian
package names. On CachyOS, use `docker`, `networkmanager`, and `nfs-utils`.

If `pacman` reports that `docker`, `containerd`, or `runc` are unavailable,
stop. Do not substitute Docker Desktop, rootless Docker, or Podman for this plan
without redesigning the Supervisor integration.

### 5.2 Enable required baseline services

```bash
sudo systemctl enable --now dbus-broker.service
sudo systemctl enable --now NetworkManager.service
sudo systemctl enable --now systemd-resolved.service
sudo systemctl enable --now udisks2.service
sudo systemctl enable --now systemd-timesyncd.service
```

Confirm that `/etc/resolv.conf` remains a valid symlink or file managed
consistently with NetworkManager and `systemd-resolved`. The Supervised
installer expects `systemd-resolved` to be available and Supervisor requires its
D-Bus interface.

Do not allow a second network manager to compete with NetworkManager. The
audited host uses NetworkManager over the wired `enp0s20f0u8u1` connection;
`wlan0` is disconnected.

### 5.3 Enable the journal gateway socket

The Supervisor launcher mounts `/run/systemd-journal-gatewayd.sock` into the
container. Create it through the distro-provided socket unit rather than
hand-creating a Unix socket:

```bash
sudo systemctl enable --now systemd-journal-gatewayd.socket
sudo systemctl status --no-pager systemd-journal-gatewayd.socket
sudo systemctl start systemd-journal-gatewayd.service
sudo systemctl is-active systemd-journal-gatewayd.service
ls -l /run/systemd-journal-gatewayd.sock
```

A socket file alone is not sufficient: on this CachyOS image,
`systemd-journal-gatewayd` also requires `libmicrohttpd`. Verify the activated
service, not just the socket. The upstream supervised installer adds a socket
drop-in so that the socket listens at `/run/systemd-journal-gatewayd.sock`.
Inspect the current CachyOS unit before adding the drop-in:

```bash
systemctl cat systemd-journal-gatewayd.socket
```

If the unit listens elsewhere, create
`/etc/systemd/system/systemd-journal-gatewayd.socket.d/10-hassio-supervisor.conf`:

```ini
[Socket]
ListenStream=
ListenStream=/run/systemd-journal-gatewayd.sock
```

Then apply it:

```bash
sudo systemctl daemon-reload
sudo systemctl restart systemd-journal-gatewayd.socket
```

Verify the socket exists after a reboot as well as immediately after enabling
it.

### 5.4 Enable AppArmor at boot

The audited target now has AppArmor enabled by the kernel and its securityfs
mounted. The active LSM list includes `apparmor`, and `aa-status` reports the
loader and Supervisor profile successfully.

First inspect the active boot entry and CachyOS boot configuration. The host
uses systemd-boot. Add AppArmor to the kernel command line while preserving the
existing LSMs. A typical setting is:

```text
lsm=landlock,lockdown,yama,apparmor,bpf
```

Use the system’s actual boot-entry editing mechanism; do not overwrite the boot
entry blindly. Reboot during a controlled maintenance window, then verify:

```bash
cat /sys/module/apparmor/parameters/enabled
cat /sys/kernel/security/lsm
sudo aa-status
mount | grep securityfs
```

Expected results:

- AppArmor reports enabled;
- `apparmor` appears in the active LSM list;
- the AppArmor filesystem is mounted;
- `aa-status` runs without reporting that AppArmor is disabled.

Then enable the loader:

```bash
sudo systemctl enable --now apparmor.service
sudo systemctl status --no-pager apparmor.service
```

If enabling AppArmor would materially affect existing desktop applications, test
the reboot with a recovery path first. Do not disable AppArmor simply to make
Supervisor start; that would remove the normal add-on security boundary.

### 5.5 Enable Docker and configure it for Supervisor

Start Docker only after reviewing the configuration. Create
`/etc/docker/daemon.json` based on the upstream supervised installer:

```json
{
  "log-driver": "journald",
  "log-opts": { "tag": "{{.Name}}" },
  "storage-driver": "overlay2"
}
```

Before applying it, check the current Docker version’s supported options.
`experimental` and `ip6tables` may be unnecessary or behave differently on newer
Docker releases. Prefer the smallest configuration that passes Supervisor’s
checks, while retaining:

- journald logging with the container name as `SYSLOG_IDENTIFIER` (required by
  Supervisor's app-log filters);
- the `libmicrohttpd` package, required for `systemd-journal-gatewayd`;
- overlay2/overlayfs storage;
- IPv6 firewall behavior if the workload requires it.

Then:

```bash
sudo systemctl enable --now docker.service
sudo systemctl status --no-pager docker.service
sudo docker info
sudo docker version
```

Required checks:

```bash
sudo docker info --format \
  'Server={{.ServerVersion}} Storage={{.Driver}} Logging={{.LoggingDriver}} Cgroup={{.CgroupVersion}}'
```

Expected values:

```text
Server >= 24.0.0
Storage = overlay2 or overlayfs
Logging = journald
Cgroup = 2
```

The current CachyOS repositories provide Docker `29.7.2`, which is above
Supervisor’s current minimum Docker version of `24.0.0`. Validate the actual
installed version after installation, not only the repository candidate.

### 5.6 Validate Docker networking and capabilities

Run a disposable test before installing Supervisor:

```bash
sudo docker run --rm hello-world
sudo docker run --rm --privileged alpine:latest sh -c \
  'test -e /sys/fs/cgroup && test -e /dev && echo privileged-container-ok'
```

Check that Docker can create bridge networks, veth pairs, NAT rules, and a
container with a published port:

```bash
sudo docker network create ha-preflight
sudo docker run --rm --network ha-preflight alpine:latest ip addr
sudo docker network rm ha-preflight
sudo docker run -d --name ha-preflight-http \
  --publish 127.0.0.1:18080:80 nginx:alpine
curl --fail http://127.0.0.1:18080/
sudo docker rm --force ha-preflight-http
```

Inspect firewall behavior if a host firewall is enabled. Do not run both a
custom firewall policy and Supervisor’s expected Docker gateway rules without
testing container-to-LAN and container-to-internet traffic.

### 5.7 UFW and Docker firewall integration

The source Debian host showed the firewall contract required by this supervised
layout. UFW was installed but inactive, and its persistent configuration still
contained these interface rules:

```text
/etc/ufw/user.rules:
-A ufw-user-input -i hassio -j ACCEPT
-A ufw-user-output -o hassio -j ACCEPT

/etc/ufw/user6.rules:
-A ufw6-user-input -i hassio -j ACCEPT
-A ufw6-user-output -o hassio -j ACCEPT
```

The installed Debian `homeassistant-supervised` package's `postinst` script was
also inspected. It configures systemd-resolved, Docker, Supervisor, AppArmor,
and the journal gateway, but contains no `ufw`, `iptables`, or `nft` command.
The source UFW interface rules therefore cannot be attributed to the Supervisor
runtime or that package's installation hook from the available evidence. Their
UFW file mtime is 2026-05-27, while the supervised package files date to 2024;
they were most likely created by a separate host setup/admin action. The source
has UFW disabled today, but its rules remain persisted in `/etc/ufw/user.rules`
and `/etc/ufw/user6.rules`.

The source's Docker `hassio` network is `172.30.32.0/23`, with gateway
`172.30.32.1` and an app IP range of `172.30.33.0/24`. Docker creates and
maintains the `DOCKER-*` chains, including:

```text
FORWARD -> DOCKER-USER -> DOCKER-FORWARD
DOCKER-FORWARD: -i hassio -j ACCEPT
POSTROUTING: -s 172.30.32.0/23 ! -o hassio -j MASQUERADE
```

The target's initial UFW snapshot was:

```text
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)

Existing inbound allowances included 22/tcp+udp, 8123/tcp+udp,
25565/tcp, 19132/tcp+udp, 60001/udp, 60002/udp, 60003-60009/udp,
and 8100/tcp, plus corresponding IPv6 rules.
```

Its relevant filter-chain order was:

```text
INPUT (DROP) -> ts-input -> ufw-before-* -> ufw-after-* -> ufw-reject-input
FORWARD (DROP) -> ts-forward -> DOCKER-USER -> DOCKER-FORWARD -> ufw-* chains
DOCKER-FORWARD -> DOCKER-CT -> DOCKER-INTERNAL -> DOCKER-BRIDGE
DOCKER-FORWARD: -i hassio -j ACCEPT
```

Thus Docker's normal bridge forwarding was already allowed, but a host-network
add-on's ingress connection terminates at the host's `INPUT` path. The missing
UFW `-i hassio` input rule blocked that path. The target initially had UFW
active with `deny (routed)` and no `hassio` interface rules. This blocked
Supervisor ingress to host-network apps. The failure appeared as Supervisor
errors such as:

```text
Ingress error: Cannot connect to host 172.30.32.1:65254
Ingress error: Cannot connect to host 172.30.32.1:64244
```

The SSH add-on itself was healthy and listening on `172.30.32.1:65254`; Node-RED
was healthy and listening on `172.30.32.1:64244`. The host firewall dropped the
Supervisor SYN packets, confirmed by kernel logs:

```text
[UFW BLOCK] IN=hassio SRC=172.30.32.2 DST=172.30.32.1 DPT=65254
```

The target was corrected with the source-equivalent persistent rules:

```bash
sudo ufw allow in on hassio
sudo ufw allow out on hassio
sudo ufw reload
```

This produces the following effective rules:

```text
-A ufw-user-input -i hassio -j ACCEPT
-A ufw-user-output -o hassio -j ACCEPT
-A ufw6-user-input -i hassio -j ACCEPT
-A ufw6-user-output -o hassio -j ACCEPT
```

The earlier diagnostic rule allowing only SSH ingress was retained but is now
redundant and may be removed after review:

```text
-A ufw-user-input -i hassio -p tcp --dport 65254 -s 172.30.32.0/23 -j ACCEPT
```

Do not add an arbitrary broad LAN port range for Supervisor ingress. The
interface-scoped rule allows traffic arriving from Docker's internal `hassio`
bridge, while UFW continues to control traffic arriving on the physical LAN
interface. Docker continues to manage forwarding to bridge-network containers.
Host-network add-ons still require this interface rule because their dynamic
Supervisor ingress ports are bound on the host-side gateway address.

The original target diagnosis also used temporary rules:

```bash
iptables -I FORWARD 3 -i hassio -j ACCEPT
iptables -I INPUT 1 -i hassio -p tcp --dport 65254 -j ACCEPT
```

Both temporary rules were removed; the persistent UFW rules above are the
current fix. The resulting direct tests returned non-empty responses for SSH
`65254` and Node-RED `64244`, and the browser successfully loaded both ingress
applications.

UFW is independent of OS Agent and Supervisor at runtime. Future add-on
installation does not reliably modify host UFW rules. On this CachyOS bundle,
keep the `hassio` UFW rules as an explicit host-integration requirement and
verify them during preflight if UFW is enabled.

## 6. Phase 2 — install and validate OS Agent

### 6.1 Prefer upstream source or reviewed AUR packaging

The upstream OS Agent is a Go program with a D-Bus service. The AUR package
currently available is:

```text
homeassistant-osagent 1.8.1-1
```

The AUR package builds the upstream repository and installs:

```text
/usr/bin/os-agent
/usr/lib/systemd/system/haos-agent.service
/etc/dbus-1/system.d/io.hass.conf
```

Review the PKGBUILD and source revision before installation. If it is stale
relative to the upstream release required by the Supervisor version, build from
the upstream repository at the matching release/tag instead.

Do not install an AUR package directly with `paru -S`. Treat the AUR repository,
PKGBUILD, build functions, `.install` files, source URLs, and generated package
as untrusted input. Before any privileged installation:

1. inspect the PKGBUILD and every referenced install/build script;
2. compare the source URL, pinned revision, and release contents with upstream;
3. reject skipped or weak source checksums where a real checksum or signature is
   available;
4. build as an unprivileged user in a clean, isolated Arch build environment;
5. inspect the resulting package file list, dependencies, systemd units, D-Bus
   policy, and install scripts; and
6. install only the reviewed local package, recording its source revision and
   package checksum.

For OS Agent, the package must install only the expected agent binary, D-Bus
policy, and service unit, without adding unwanted boot, disk, network, or system
configuration behavior. Build from the pinned upstream release instead of using
the AUR package if the review cannot establish that provenance.

### 6.2 Adapt OS Agent for CachyOS only where necessary

The upstream service is:

```ini
[Unit]
Description=Home Assistant OS Agent
DefaultDependencies=no
Requires=dbus.socket udisks2.service
After=dbus.socket sysinit.target

[Service]
BusName=io.hass.os
Type=notify
Restart=always
RestartSec=5s
Environment="DBUS_SYSTEM_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket"
ExecStart=/usr/bin/os-agent

[Install]
WantedBy=multi-user.target
```

The upstream agent contains HAOS-specific methods such as data-disk movement and
boot-file handling. On CachyOS:

- preserve the D-Bus interface and return correct errors for HAOS-only
  operations;
- do not pretend that `/mnt/data`, `/mnt/boot`, RAUC slots, or HAOS boot markers
  exist;
- make `CurrentDevice` and data-disk methods safe or unavailable on a normal
  CachyOS filesystem;
- ensure CGroup device updates use the installed Docker/runc paths and cgroup v2
  layout;
- keep AppArmor methods functional if AppArmor is enabled;
- keep `io.hass.os` version and diagnostics properties functional.

Start the upstream agent first. Fork only after an observed incompatibility and
add a regression test for each forked behavior.

### 6.3 Enable and test the agent

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now haos-agent.service
sudo systemctl status --no-pager haos-agent.service
sudo busctl introspect --system io.hass.os /io/hass/os
```

The introspection must expose the base service and the interfaces Supervisor
expects. Also check:

```bash
busctl get-property --system io.hass.os /io/hass/os \
  io.hass.os Version
busctl introspect --system io.hass.os /io/hass/os/AppArmor
busctl introspect --system io.hass.os /io/hass/os/CGroup
busctl introspect --system io.hass.os /io/hass/os/System
busctl introspect --system io.hass.os /io/hass/os/DataDisk
```

If a method is intentionally unavailable on CachyOS, document the expected error
and confirm Supervisor treats the feature as unavailable rather than failing
initialization.

## 7. Phase 3 — install the Supervised host integration

### 7.1 Do not use the Debian installer unchanged

The upstream installer assumes Debian package names and conventions, including:

- `docker-ce`;
- `network-manager`;
- `nfs-common`;
- Debian package lifecycle hooks;
- Debian filesystem and service paths;
- systemd unit installation from a `.deb`.

Do not install the current AUR `homeassistant-supervised` package directly. Its
reviewed revision contains root-privileged side effects, including configuration
overwrites, service restarts, and automatic startup, and uses weak source
verification. Use the tracked local bundle instead, after reviewing its diff and
running its validation script.

Review its PKGBUILD against the current upstream installer and verify that it
installs all required files:

```text
homeassistant-supervised-cachyos/bin/hassio-supervisor
homeassistant-supervised-cachyos/bin/hassio-apparmor
homeassistant-supervised-cachyos/config/hassio.json
homeassistant-supervised-cachyos/docker/daemon.json
homeassistant-supervised-cachyos/dbus/io.hass.conf
homeassistant-supervised-cachyos/systemd/*.service
homeassistant-supervised-cachyos/systemd/systemd-journal-gatewayd.socket.d/10-hassio-supervisor.conf
homeassistant-supervised-cachyos/apparmor/hassio-supervisor
homeassistant-supervised-cachyos/install-host-integration.sh
homeassistant-supervised-cachyos/preflight.sh
```

The AUR package currently bypasses the Debian OS check and uses Arch paths. The
package revision audited for this runbook also contains root-privileged
installation behavior that must not be accepted unchanged. Review every hook and
reject or replace the package if it:

- changes `kernel.dmesg_restrict`;
- overwrites Docker, NetworkManager, or systemd-resolved configuration without
  an explicit local diff and approval;
- restarts networking or Docker as an installation side effect; or
- starts Supervisor automatically before the staged preflight is complete.

The audited package also uses `md5sums=('SKIP')` for source verification. Prefer
a local package built from a pinned upstream revision with cryptographic
checksums or signatures. Install only after the generated package and its
root-executed install hooks have been reviewed.

### 7.2 Build a local package or explicit host integration

For reproducibility, create a local package or tracked deployment directory
containing:

- the exact upstream installer revision;
- CachyOS dependency mapping;
- the reviewed service units;
- the Supervisor launcher;
- the AppArmor loader;
- `/etc/hassio.json` template;
- Docker and NetworkManager configuration;
- a version/commit record;
- a validation script.

Do not make ad hoc edits under `/usr` that cannot be rebuilt. Keep the local
packaging source outside the Home Assistant data directory, for example:

```text
/etc/homeassistant-supervised/
/usr/local/src/homeassistant-supervised-cachyos/
```

### 7.3 Create the Supervisor configuration

The target is x86_64 and should use the same machine type as the source unless a
restored app requires a different supported type:

```json
{
  "supervisor": "ghcr.io/home-assistant/amd64-hassio-supervisor",
  "machine": "qemux86-64",
  "data": "/var/lib/homeassistant"
}
```

Create the data directory with root ownership initially:

```bash
sudo install -d -m 0755 /var/lib/homeassistant
sudo install -d -m 0755 /var/lib/homeassistant/apparmor
```

Do not copy the source Docker data root into this path.

### 7.4 Install the Supervisor launcher

Adapt the upstream `hassio-supervisor` launcher to the CachyOS paths. It must:

1. read `/etc/hassio.json`;
2. read the Supervisor data path and machine type;
3. obtain the Supervisor image/version;
4. pull the image through `/usr/bin/docker`;
5. create or recreate `hassio_supervisor` when the image or launcher changes;
6. run it privileged;
7. mount the required host interfaces;
8. restart it if it exits.

The required mounts in the current upstream launcher are:

```text
/run/docker.sock -> /run/docker.sock
/run/containerd/containerd.sock -> /run/containerd/containerd.sock
/run/systemd-journal-gatewayd.sock -> /run/systemd-journal-gatewayd.sock
/run/dbus -> /run/dbus
/run/supervisor -> /run/os
/run/udev -> /run/udev
/etc/machine-id -> /etc/machine-id
/var/lib/homeassistant -> /data
```

The Supervisor container must be launched with:

```text
--privileged
--security-opt apparmor=hassio-supervisor
```

Use an explicit systemd service, based on the upstream unit:

```ini
[Unit]
Description=Home Assistant Supervisor
Requires=docker.service dbus.service
Wants=network-online.target hassio-apparmor.service time-sync.target systemd-journal-gatewayd.socket systemd-resolved.service
After=docker.service dbus.service network-online.target hassio-apparmor.service time-sync.target systemd-journal-gatewayd.socket systemd-resolved.service
ConditionPathExists=/run/dbus/system_bus_socket
ConditionPathExists=/run/docker.sock

[Service]
Type=simple
Restart=always
RestartSec=5s
ExecStartPre=-/usr/bin/docker stop hassio_supervisor
ExecStart=/usr/local/lib/homeassistant-supervised/hassio-supervisor
ExecStop=-/usr/bin/docker stop hassio_supervisor

[Install]
WantedBy=multi-user.target
```

Keep the launcher outside the data directory so restoring a backup cannot
overwrite the host bootstrap mechanism.

### 7.5 Install the Supervisor AppArmor profile

The upstream profile is fetched from the Home Assistant version service by the
installer. Pin or record the URL and downloaded version. Store it at:

```text
/var/lib/homeassistant/apparmor/hassio-supervisor
```

The AppArmor loader should:

```text
create /var/lib/homeassistant/apparmor/cache
run apparmor_parser -r -W -L <cache> <profile>
```

Create the `hassio-apparmor.service` unit and run it before Supervisor. Validate
that the profile loads successfully:

```bash
sudo systemctl enable --now hassio-apparmor.service
sudo journalctl -u hassio-apparmor.service --no-pager
sudo aa-status | grep -i hassio
```

If the profile fails because of a CachyOS/AppArmor syntax or policy difference,
stop the migration and fix the profile. Do not silently run Supervisor
unconfined in the production migration.

## 8. Phase 4 — staged first boot

Before restoring the live backup, start an empty Supervisor installation.

### 8.1 Preflight gate

Require all of these:

```bash
systemctl is-active docker
systemctl is-active NetworkManager
systemctl is-active systemd-resolved
systemctl is-active dbus-broker
systemctl is-active udisks2
systemctl is-active systemd-journal-gatewayd.socket
systemctl is-active systemd-journal-gatewayd.service
systemctl is-active haos-agent
systemctl is-active apparmor
systemctl is-active hassio-apparmor
ls -l /run/docker.sock
ls -l /run/dbus/system_bus_socket
ls -l /run/systemd-journal-gatewayd.sock
sudo docker info
busctl introspect --system io.hass.os /io/hass/os
```

### 8.2 Start Supervisor

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hassio-supervisor.service
sudo systemctl status --no-pager hassio-supervisor.service
sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
```

Watch logs:

```bash
sudo journalctl -fu hassio-supervisor.service
sudo docker logs -f hassio_supervisor
```

Wait for the Supervisor to create its internal network and built-in plugins.
Confirm the Supervisor API responds before restoring data:

```bash
sudo docker exec hassio_supervisor curl -fsS http://127.0.0.1/supervisor/ping
```

Use the target host’s local address and port 8123 to reach Home Assistant. Do
not expose the target externally until authentication and TLS are configured.

### 8.3 Resolve unsupported/failed checks before restore

Inspect the Supervisor resolution state through the UI or CLI:

```bash
sudo docker exec hassio_cli ha supervisor info --no-progress --raw-json
sudo docker exec hassio_cli ha resolution info --no-progress --raw-json
```

Expected unsupported warnings may include:

- operating system / HAOS not available;
- unavailable HAOS update features;
- unsupported installation method.

These are expected in this design. The following are **not** acceptable to
ignore:

- Docker version/configuration failures;
- missing OS Agent;
- missing D-Bus;
- missing systemd;
- missing NetworkManager;
- missing systemd-resolved;
- missing AppArmor when the security profile is intended to be active;
- failed Supervisor, Core, DNS, or network plugin startup;
- storage or cgroup errors;
- failed container network creation.

## 9. Phase 5 — migrate the data

### 9.1 Transfer and verify the full backup

The target staging directory is root-owned and mode `0700`, so upload to the
user's home directory first. Compare the source checksum with the recorded
value, then move the verified file into root-only staging:

```bash
# Run on the source or transfer machine.
sha256sum <full-backup>.tar
scp <full-backup>.tar <user>@192.168.2.55:~/

# Run on the target, after comparing this checksum with the source value.
sha256sum ~/<full-backup>.tar
sudo install -d -o root -g root -m 0700 /var/lib/homeassistant-import
sudo install -o root -g root -m 0600 \
  ~/<full-backup>.tar /var/lib/homeassistant-import/<full-backup>.tar
sudo sha256sum /var/lib/homeassistant-import/<full-backup>.tar
rm -- ~/<full-backup>.tar
```

Do not place secrets in shell history. Use SSH keys or an encrypted transfer.

### 9.2 Restore through Supervisor

Use the Supervisor UI to upload and restore the full backup. Prefer restoring
the complete system while the target instance is otherwise empty.

Restore in this order if a complete restore is not possible:

1. Home Assistant Core;
2. Mosquitto;
3. Zigbee2MQTT/ZHA state;
4. Node-RED and automation services;
5. TLS/NGINX and external access services;
6. remaining apps/add-ons;
7. `share` and other explicitly selected folders.

Do not restore both a complete backup and manually copied live data over the
same paths without a documented precedence rule.

### 9.3 Hardware and serial migration

Move the ConBee II to the CachyOS host, then identify it:

```bash
lsusb
ls -l /dev/serial/by-id
```

The preferred stable path is the `/dev/serial/by-id/...` symlink. If the symlink
differs from the source, update Zigbee2MQTT/ZHA configuration to the target
path.

Confirm the device is visible inside the relevant app container. Do not expose
all of `/dev` unnecessarily; use the app’s configured device mapping.

The target currently has an internal Bluetooth adapter but no ConBee II.
Bluetooth-based integrations need separate acceptance testing.

## 10. Phase 6 — network and external-access cutover

### 10.1 LAN behavior

The target currently uses wired Ethernet via `enp0s20f0u8u1` at 100 Mb/s;
`wlan0` is disconnected. Verify:

- Home Assistant is reachable from another LAN device;
- mDNS name resolution works;
- LLMNR/mDNS traffic is not blocked by the host firewall or Wi-Fi isolation;
- Docker bridge containers can reach the LAN and internet;
- integrations can reach multicast/SSDP devices as required.

A wired Ethernet adapter is preferable for an always-on home automation host,
especially for multicast-heavy integrations and stable operation while the
laptop sleeps.

### 10.2 Move service ownership

Only after the target passes the internal checklist:

1. stop or isolate the old Home Assistant instance;
2. move the ConBee II and any other USB device;
3. update DHCP reservation/DNS to point the desired name at `192.168.2.55`;
4. move router forwards for 80/443/8123 and any intentionally exposed app ports;
5. update WireGuard/Tailscale routes and ACLs;
6. verify TLS certificates and reverse-proxy upstreams;
7. test local and remote access.

The migration-window overlap described above is accepted only until final
service ownership changes. Keep the target's external endpoints and duplicate
advertised identities disabled where practical, do not attach shared hardware to
both hosts, and stop or isolate the source before moving the ConBee II or other
exclusive devices. Do not leave two MQTT brokers, Zigbee coordinators, WireGuard
endpoints, or reverse proxies with the same network identity active after
cutover.

## 11. Acceptance checklist

### Host

- [ ] Host remains stable after reboot.
- [ ] Docker starts automatically.
- [ ] NetworkManager and systemd-resolved start automatically.
- [ ] D-Bus and UDisks2 are available.
- [ ] journal gateway socket exists after reboot.
- [ ] AppArmor is enabled and the Supervisor profile loads.
- [ ] cgroups v2 remains enabled.
- [ ] Docker reports journald logging and overlay2/overlayfs.
- [ ] Docker bridge/veth/NAT networking works.
- [ ] If UFW is active, persistent `hassio` interface input/output rules exist.

### Agent and Supervisor

- [ ] `io.hass.os` introspection succeeds.
- [ ] OS Agent starts automatically and reports its version.
- [ ] Supervisor starts automatically.
- [ ] Supervisor can pull and update images.
- [ ] Supervisor API ping succeeds.
- [ ] Supervisor, Core, and add-on log endpoints return non-empty logs.
- [ ] Home Assistant Core starts.
- [ ] built-in Supervisor plugins start.
- [ ] no unexpected unsupported or unhealthy resolution issues remain.
- [ ] Supervisor backup creation works.
- [ ] Supervisor backup restore works in a test cycle.

### Home Assistant workload

- [ ] Login and users work.
- [ ] dashboards and frontend resources load.
- [ ] automations, scripts, scenes, and blueprints load.
- [ ] history/statistics and recorder database are usable.
- [ ] secrets and TLS work.
- [ ] MQTT works.
- [ ] Zigbee coordinator and Zigbee2MQTT/ZHA work.
- [ ] Node-RED works.
- [ ] custom integrations load or are explicitly remediated.
- [ ] all critical apps/add-ons start and retain their configuration.
- [ ] external access and webhooks work.
- [ ] mDNS/SSDP/UPnP integrations work where required.
- [ ] backup to the intended remote destination works.

### Operational

- [ ] documented local package/source revisions exist;
- [ ] Docker, OS Agent, launcher, AppArmor profile, and Supervisor versions are
      recorded;
- [ ] a tested rollback path exists;
- [ ] the target has a fixed/reserved LAN address;
- [ ] laptop sleep/hibernation policy is understood and disabled if this is an
      always-on service;
- [ ] monitoring and alerting are configured.

## 12. Rollback plan

Rollback remains possible until the final network cutover:

1. Stop the target Supervisor:
   ```bash
   sudo systemctl disable --now hassio-supervisor.service
   ```
2. Stop target apps if necessary:
   ```bash
   sudo docker ps
   sudo docker stop <target-containers>
   ```
3. Reattach the ConBee II to the old host.
4. Restore the old DHCP/DNS/router forwarding state.
5. Start the old Supervisor and verify Home Assistant.
6. Do not delete the target data directory or backup artifacts until the target
   has run successfully for an agreed observation period. Treat any target-side
   writes made after restore as disposable until that observation period ends;
   if rollback is needed, restore the source and explicitly reconcile or discard
   those writes.

Keep the source host intact and powered off or isolated rather than uninstalling
it during the migration window.

## 13. Update and maintenance policy

Because CachyOS is not an upstream-supported Supervised host, updates need a
deliberate process:

1. snapshot or back up the Supervisor data before updates;
2. record the current Supervisor/Core/App/OS Agent versions;
3. update CachyOS packages in a controlled window;
4. reboot and run the host preflight checks;
5. update OS Agent only after checking its D-Bus interface against the current
   Supervisor;
6. allow Supervisor/Core/app updates one class at a time;
7. monitor logs and resolution state;
8. retain the previous package/source revisions and a known-good backup.

Do not update the host kernel, Docker, OS Agent, and Home Assistant Core
simultaneously when diagnosing a failure. The likely future maintenance burden
is compatibility repair when upstream changes any of:

- Docker API or container runtime behavior;
- cgroup v2/runc paths;
- AppArmor profile syntax;
- systemd journal gateway behavior;
- D-Bus interface methods/properties;
- Supervisor host feature checks;
- app/add-on device or network assumptions.

## 14. Known limitations and explicit risk decisions

### Unsupported upstream platform

The system can be made technically compatible, but Home Assistant will not
accept CachyOS-specific bug reports as supported-environment issues. Maintain a
local compatibility layer and test before upgrades.

### AUR packaging

The available AUR packages are useful but have small maintainer/user bases and
may lag upstream. Pin the package revisions or build from reviewed source in a
local package repository.

### No HAOS updates

Supervisor will not provide a meaningful HAOS update path on CachyOS.
HAOS-specific operations should remain disabled or return unavailable. CachyOS
itself is maintained separately through its normal package/kernel update
process.

### Laptop availability

A laptop can sleep, hibernate, lose Wi-Fi, run out of battery, or change network
identity. Configure:

- AC power operation;
- sleep/hibernate inhibition for the service;
- automatic restart after reboot;
- stable DHCP reservation;
- preferably wired networking;
- monitoring for host reachability and Docker/Supervisor health.

### AppArmor and security

Supervisor-managed apps can request powerful capabilities, host networking, host
PID, hardware access, and Docker access. Keep protection mode enabled unless an
individual app requires an exception and its risk is understood.

## 15. Suggested implementation order

Use this order to minimize irreversible changes:

1. Create and verify a new **full** source backup and a complete
   metadata-preserving `/usr/share/hassio` filesystem archive.
2. Record the source workload, ports, hardware, and external dependencies.
3. Review the pinned upstream revisions and the tracked local host bundle.
4. Enable AppArmor at boot and verify it after reboot.
5. Install Docker and the host packages.
6. Configure and validate Docker.
7. Enable the journal gateway socket.
8. Install and validate OS Agent.
9. Install the reviewed local Supervised host integration.
10. Start an empty Supervisor instance.
11. Resolve all non-expected health failures.
12. Restore the full backup.
13. Attach and validate the ConBee II and other hardware.
14. Test every critical app/integration.
15. Perform a controlled network cutover.
16. Run the acceptance checklist.
17. Document versions, local patches, rollback, and update procedure.

The first implementation task should be a **staging/preflight package and
service setup**, not the production backup restore. This will reveal whether the
current CachyOS kernel, AppArmor policy, Docker configuration, and OS Agent
behavior satisfy Supervisor before the live workload is moved.
