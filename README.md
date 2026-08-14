# Home Assistant Supervised on CachyOS

A reviewed, local host-integration bundle and migration runbook for running
**Home Assistant Supervised on an x86_64 CachyOS host**.

> **Unsupported deployment:** Home Assistant Supervised officially targets
> Debian. CachyOS is not an upstream-supported host OS. Use this repository only
> when you accept the maintenance and rollback burden of carrying the
> compatibility layer yourself.

## Start here

1. Read
   [`cachyos_supervisord_installation.md`](./cachyos_supervisord_installation.md)
   completely. It is the authoritative runbook and includes the rationale,
   migration gates, validation commands, rollback procedure, and known risks.
2. Treat host names, addresses, versions, USB paths, and audit results in that
   runbook as **examples from one CachyOS machine**, not as defaults for a new
   machine. Replace them with values gathered from the actual source and target.
3. Review every file in
   [`homeassistant-supervised-cachyos/`](./homeassistant-supervised-cachyos/)
   before running it as root. The scripts configure the host integration; they
   do not install CachyOS packages or OS Agent for you.
4. Stage and validate an empty Supervisor instance before restoring any live
   Home Assistant data or moving shared hardware.

## What is included

```text
homeassistant-supervised-cachyos/
├── apparmor/hassio-supervisor              Supervisor AppArmor profile
├── bin/hassio-apparmor                     AppArmor profile loader
├── bin/hassio-supervisor                   CachyOS Supervisor launcher
├── config/hassio.json                      Supervisor image, machine, data path
├── dbus/io.hass.conf                       io.hass.os D-Bus policy
├── docker/daemon.json                      journald + overlay2 Docker config
├── install-host-integration.sh             Install files and enable units
├── preflight.sh                            Host readiness gate
├── sources.lock                            Reviewed upstream input records
└── systemd/                                Agent, AppArmor, Supervisor, socket units
```

The bundle installs the local integration under
`/usr/local/lib/homeassistant-supervised` and uses `/var/lib/homeassistant` for
Supervisor data. It deliberately keeps the launcher and host files outside the
data directory so a Home Assistant restore cannot overwrite the host bootstrap
mechanism.

## Supported shape of the target

The bundle assumes all of the following are available and have been tested on
the target:

- x86_64 CachyOS with cgroups v2 and a systemd boot;
- rootful Docker Engine, containerd, and runc;
- NetworkManager and `systemd-resolved`;
- D-Bus, `dbus-broker`, and UDisks2;
- AppArmor enabled at boot and `apparmor_parser` available;
- `systemd-journal-gatewayd` plus its runtime dependency `libmicrohttpd`;
- the upstream Home Assistant OS Agent installed as `/usr/bin/os-agent`, with
  the `io.hass.os` D-Bus interface working;
- a stable wired or otherwise reliable network connection.

The default configuration is for an amd64 Supervisor image and `qemux86-64`
machine type. Change `config/hassio.json` only after checking the source machine
type and Supervisor compatibility.

## Safe installation sequence

The detailed runbook is the source of truth; this is the condensed order:

### 1. Protect the source

Create and checksum a **full** Home Assistant backup, including required apps,
`ssl`, and `share`. Separately create a metadata-preserving archive or snapshot
of the complete source Supervisor state while the source is stopped. Keep the
source authoritative and available for rollback.

Do not use a partial backup as a substitute for a full backup, and do not copy
the source Docker data root or running container IDs.

### 2. Prepare CachyOS

Install and review the required host packages, enable the baseline services,
configure AppArmor, configure rootful Docker for journald logging and overlay2,
and validate bridge networking, published ports, cgroups, and the journal
gateway socket. If a host firewall is enabled, test Docker's `hassio` bridge
rules and Supervisor ingress explicitly.

The package names are CachyOS/Arch names (`docker`, `networkmanager`, and
`nfs-utils`), not Debian names such as `docker-ce`, `network-manager`, or
`nfs-common`.

### 3. Install and verify OS Agent

Use the release and checksum recorded in `sources.lock`, or update that file
only after reviewing a newer upstream release. Prefer an upstream release or a
locally reviewed package over an unreviewed AUR package. Verify:

```bash
sudo systemctl enable --now haos-agent.service
sudo busctl introspect --system io.hass.os /io/hass/os
```

The host integration bundle contains a service unit and D-Bus policy, but it
does not contain the OS Agent binary.

### 4. Install the local host integration

From this repository, after reviewing the diff between the bundle and the
machine's current configuration:

```bash
cd homeassistant-supervised-cachyos
sudo ./install-host-integration.sh
```

This installs and enables the units but intentionally does **not** start
Supervisor. It also installs the bundled Docker configuration and can back up a
pre-existing `/etc/docker/daemon.json`; review the resulting Docker diff before
restarting Docker.

The installer unconditionally replaces `/etc/hassio.json`,
`/etc/docker/daemon.json`, the `io.hass.os` D-Bus policy, the systemd units, and
the journal/logind drop-ins. Save and review the current versions of all of
those files first; run this only on the intended target during a maintenance
window.

Run the staged checks only after all dependencies and the OS Agent are active:

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker.service
sudo systemctl enable --now systemd-journal-gatewayd.socket
sudo systemctl enable --now hassio-apparmor.service
sudo ./preflight.sh
```

Resolve every unexpected failure before starting Supervisor. Expected warnings
about the unsupported OS are not a substitute for fixing missing Docker,
AppArmor, D-Bus, systemd, networking, storage, or cgroup functionality.

### 5. Boot an empty Supervisor first

```bash
sudo systemctl enable --now hassio-supervisor.service
sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
sudo docker exec hassio_supervisor curl -fsS http://127.0.0.1/supervisor/ping
```

Confirm the Supervisor API, Core, built-in plugins, logging endpoints, and
container networking before importing state.

### 6. Restore, validate, and cut over

Transfer the full backup over a protected channel, compare its checksum on both
ends, and restore it through Supervisor. Then validate Core, every critical app,
custom integrations, history, secrets, TLS, MQTT, serial hardware, and backups
while external access and duplicate identities remain disabled.

Only then stop or isolate the old host, move exclusive USB hardware, update DNS,
DHCP, router forwards, reverse proxies, and remote-access configuration, and run
the acceptance checklist. Keep the old host and recovery artifacts intact for
the agreed observation period.

## Operational notes

- `sources.lock` records external inputs but the Supervisor image channel is the
  Home Assistant stable channel; review upstream changes before upgrades.
- CachyOS updates, Docker/runtime updates, OS Agent updates, Supervisor/Core
  updates, and AppArmor changes should not all be introduced in one diagnostic
  window.
- HAOS-only operations such as RAUC boot management and HAOS data-disk updates
  are not available on CachyOS.
- Supervisor-managed apps can request privileged access, host networking, host
  PID, hardware access, or Docker access. Keep AppArmor enforcement enabled and
  review exceptions deliberately.
- The repository contains no Home Assistant secrets, backups, Docker state, or
  machine-specific runtime data. Do not add any of those artifacts.

## Files for an implementing agent

| Need                            | Read / run                                                                                                                                                                                          |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Full procedure and safety gates | [`cachyos_supervisord_installation.md`](./cachyos_supervisord_installation.md)                                                                                                                      |
| Host deployment                 | [`install-host-integration.sh`](./homeassistant-supervised-cachyos/install-host-integration.sh)                                                                                                     |
| Readiness validation            | [`preflight.sh`](./homeassistant-supervised-cachyos/preflight.sh)                                                                                                                                   |
| Supervisor launch contract      | [`bin/hassio-supervisor`](./homeassistant-supervised-cachyos/bin/hassio-supervisor) and [`systemd/hassio-supervisor.service`](./homeassistant-supervised-cachyos/systemd/hassio-supervisor.service) |
| Security boundary               | [`apparmor/hassio-supervisor`](./homeassistant-supervised-cachyos/apparmor/hassio-supervisor) and [`bin/hassio-apparmor`](./homeassistant-supervised-cachyos/bin/hassio-apparmor)                   |
| Pinned input provenance         | [`sources.lock`](./homeassistant-supervised-cachyos/sources.lock)                                                                                                                                   |

There is intentionally no one-command production installer. The target must pass
the infrastructure gate before a live backup is restored.
