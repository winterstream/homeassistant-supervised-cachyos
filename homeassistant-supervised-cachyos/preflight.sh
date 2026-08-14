#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  printf '%s\n' 'Run this preflight as root.' >&2
  exit 1
fi

require_active() {
  local unit=$1
  systemctl is-active --quiet "$unit" || {
    printf 'Required unit is not active: %s\n' "$unit" >&2
    return 1
  }
}

for unit in docker.service containerd.service dbus.service NetworkManager.service \
  systemd-resolved.service udisks2.service systemd-journal-gatewayd.socket \
  haos-agent.service apparmor.service hassio-apparmor.service; do
  require_active "$unit"
done

# Socket activation can leave the gateway socket present while its service
# dependency is broken, so start it explicitly and verify the executable runs.
systemctl start systemd-journal-gatewayd.service
require_active systemd-journal-gatewayd.service

[[ -S /run/docker.sock ]]
[[ -S /run/dbus/system_bus_socket ]]
[[ -S /run/systemd-journal-gatewayd.sock ]]
[[ "$(cat /sys/fs/cgroup/cgroup.controllers)" == *cpu* ]]
[[ "$(cat /sys/module/apparmor/parameters/enabled)" == Y ]]

docker info --format 'Server={{.ServerVersion}} Storage={{.Driver}} Logging={{.LoggingDriver}} Cgroup={{.CgroupVersion}}'
busctl introspect --system io.hass.os /io/hass/os >/dev/null
aa-status | awk '$1 == "hassio-supervisor" { found = 1 } END { exit !found }'

printf '%s\n' 'Home Assistant Supervised CachyOS host preflight passed.'
