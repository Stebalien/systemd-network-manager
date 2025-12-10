# systemd-network-manager

A daemon that monitors network connectivity and manages systemd targets based on network state.

## Overview

This tool bridges systemd-networkd's network state monitoring with systemd's target system, automatically activating different targets based on actual network connectivity:

- `offline.target` - Activated when the network is not available.
- `captive-portal.target` - Activated when network is connected but internet access is blocked (e.g., captive portal).
- `online.target` - Activated when full internet connectivity is available.

This daemon can be used as both a system daemon and as a user daemon.

## Installation

```bash
git clone https://github.com/Stebalien/systemd-network-manager
cd systemd-network-manager
make
sudo make install
```

## Usage

To manage the system network-state targets, enable and start the system service.

```bash
sudo systemctl enable --now systemd-network-manager
```

Optionally enable the user service to manage the per-user offline/captive-portal/online targets.

```bash
systemctl enable --user --now systemd-network-manager
```

## License

MIT
