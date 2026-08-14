#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  printf '%s\n' 'Run this installer as root.' >&2
  exit 1
fi

readonly root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly lib_dir=/usr/local/lib/homeassistant-supervised
readonly data_dir=/var/lib/homeassistant
readonly config=/etc/hassio.json

install -d -m 0755 "$lib_dir" "$lib_dir/apparmor" "$data_dir" "$data_dir/apparmor"
install -m 0755 "$root_dir/bin/hassio-supervisor" "$lib_dir/hassio-supervisor"
install -m 0755 "$root_dir/bin/hassio-apparmor" "$lib_dir/hassio-apparmor"
install -m 0644 "$root_dir/apparmor/hassio-supervisor" "$lib_dir/apparmor/hassio-supervisor"
install -m 0644 "$root_dir/apparmor/hassio-supervisor" "$data_dir/apparmor/hassio-supervisor"
install -m 0644 "$root_dir/config/hassio.json" "$config"
install -d -m 0755 /etc/docker
if [[ -e /etc/docker/daemon.json ]] && ! cmp -s "$root_dir/docker/daemon.json" /etc/docker/daemon.json; then
  cp -a /etc/docker/daemon.json "/etc/docker/daemon.json.pre-homeassistant-$(date +%Y%m%d%H%M%S)"
fi
install -m 0644 "$root_dir/docker/daemon.json" /etc/docker/daemon.json
install -d -m 0755 /etc/dbus-1/system.d
install -m 0644 "$root_dir/dbus/io.hass.conf" /etc/dbus-1/system.d/io.hass.conf
install -d -m 0755 /etc/systemd/system/systemd-journal-gatewayd.socket.d
install -m 0644 "$root_dir/systemd/systemd-journal-gatewayd.socket.d/10-hassio-supervisor.conf" \
  /etc/systemd/system/systemd-journal-gatewayd.socket.d/10-hassio-supervisor.conf
install -d -m 0755 /etc/systemd/logind.conf.d
install -m 0644 "$root_dir/systemd/logind.conf.d/hassio.conf" /etc/systemd/logind.conf.d/hassio.conf
install -m 0644 "$root_dir/systemd/haos-agent.service" /etc/systemd/system/haos-agent.service
install -m 0644 "$root_dir/systemd/hassio-apparmor.service" /etc/systemd/system/hassio-apparmor.service
install -m 0644 "$root_dir/systemd/hassio-supervisor.service" /etc/systemd/system/hassio-supervisor.service

systemctl daemon-reload
systemctl enable haos-agent.service hassio-apparmor.service hassio-supervisor.service systemd-journal-gatewayd.socket

printf '%s\n' 'Host integration installed and enabled but not started.'
printf '%s\n' 'Run systemctl start hassio-apparmor.service before starting Supervisor.'
printf '%s\n' 'Changing Docker configuration requires an explicit Docker restart.'
