# pfSense-pkg-speedtest

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![pfSense](https://img.shields.io/badge/pfSense-2.7.x-orange.svg)](https://www.pfsense.org/)
[![FreeBSD](https://img.shields.io/badge/FreeBSD-14.x-red.svg)](https://www.freebsd.org/)
[![Platform: NO_ARCH](https://img.shields.io/badge/arch-NO__ARCH-lightgrey.svg)](#)

A pfSense package that integrates the [Ookla Speedtest CLI](https://www.speedtest.net/apps/cli) into the pfSense web GUI. Run on-demand and scheduled internet speed tests directly from **Services → Speed Test**.

> **Trademark notice:** Speedtest® is a registered trademark of Ookla, LLC. This project is an independent integration and is not affiliated with or endorsed by Ookla.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Install the Ookla CLI on pfSense](#install-the-ookla-cli-on-pfsense)
- [Install this Package](#install-this-package)
- [First-Time Setup](#first-time-setup)
- [Configuration](#configuration)
- [Dashboard Widget](#dashboard-widget)
- [Uninstalling](#uninstalling)
- [Development](#development)
- [Project Structure](#project-structure)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Run on demand** — single-click speed test from the browser
- **Scheduled tests** — cron-based scheduling (hourly / 6 h / 12 h / daily / custom)
- **Live results panel** — download, upload, ping, jitter, server name, ISP
- **History** — last 14 results in a sortable table with direct links to Speedtest.net result pages
- **Dashboard widget** — at-a-glance latest result on the pfSense home dashboard

---

## Requirements

### pfSense / router

| Requirement | Version |
|---|---|
| pfSense CE or Plus | **2.7.x** (FreeBSD 14.x base) |
| Ookla Speedtest CLI | any recent version — see [install instructions](#install-the-ookla-cli-on-pfsense) |

> Earlier pfSense versions (2.6.x / FreeBSD 13.x) are untested. They may work but are not supported.

### Developer machine (to build or deploy)

| Requirement | Notes |
|---|---|
| macOS or Linux | Windows via WSL2 should work but is untested |
| `make`, `ssh`, `scp` | Pre-installed on macOS; `build-essential` + `openssh-client` on Debian/Ubuntu |
| `xz` | `brew install xz` on macOS; `apt install xz-utils` on Debian/Ubuntu (needed for `make build`) |
| SSH access to pfSense | **System → Advanced → Admin Access → Enable Secure Shell** |

For native FreeBSD package builds (optional — recommended for releases):

| Tool | Platform | Install |
|---|---|---|
| [Lima](https://lima-vm.io/) v2.1+ | macOS (Intel + Apple Silicon) | `brew install lima` |
| [Vagrant](https://www.vagrantup.com/) + `vagrant-qemu` plugin | macOS | `brew install vagrant && vagrant plugin install vagrant-qemu` |

---

## Install the Ookla CLI on pfSense

The Ookla CLI binary must be present at `/usr/local/bin/speedtest` on pfSense **before** this package will function. SSH into your pfSense box and follow one of the methods below.

### Method A — Direct download from Ookla (recommended)

Visit https://www.speedtest.net/apps/cli, select **FreeBSD**, and copy the download link for the latest version.

**pfSense 2.7.x on amd64:**

```sh
# Replace X.Y.Z with the version from Ookla's download page
SPEEDTEST_VER="1.2.0"
fetch https://install.speedtest.net/app/cli/ookla-speedtest-${SPEEDTEST_VER}-freebsd13-x86_64.pkg
setenv IGNORE_OSVERSION yes
pkg add --force ookla-speedtest-${SPEEDTEST_VER}-freebsd13-x86_64.pkg
rehash
```

> `IGNORE_OSVERSION` and `--force` are needed because pfSense's FreeBSD version may not exactly match the package's declared ABI. This is safe for the Speedtest binary.

**pfSense on ARM64 (e.g. Netgate 1100/2100/4200):**

```sh
fetch https://install.speedtest.net/app/cli/ookla-speedtest-${SPEEDTEST_VER}-freebsd14-aarch64.pkg
pkg add ookla-speedtest-${SPEEDTEST_VER}-freebsd14-aarch64.pkg
```

### Method B — `pkg install` (if available in your pfSense repo)

```sh
pkg install ookla-speedtest
```

### Verify

```sh
speedtest --accept-license --accept-gdpr
```

You should see download/upload results printed to the terminal. If this command works, the pfSense package will work.

---

## Install this Package

### Option A — `pkg add` from a release (recommended for end-users)

Download the latest `.pkg` from the [Releases](https://github.com/johnathanvidu/pfSense-pkg-SpeedTest/releases) page, upload it to pfSense, and install it:

```sh
scp pfSense-pkg-speedtest-1.0.0.pkg admin@192.168.1.1:/tmp/
ssh admin@192.168.1.1 "pkg add /tmp/pfSense-pkg-speedtest-1.0.0.pkg"
```

The post-install script registers the **Services → Speed Test** menu entry automatically.

### Option B — One-command build and install (from source)

```sh
git clone https://github.com/johnathanvidu/pfSense-pkg-SpeedTest.git
cd pfSense-pkg-SpeedTest
cp .env.example .env          # edit HOST, SSH_USER as needed
make install HOST=192.168.1.1
```

`make install` builds the `.pkg` natively on pfSense via SSH (no VM required) and installs it in one step.

### Option C — Direct file deploy (fastest for development)

No `.pkg` build at all — files are SCPed directly into place:

```sh
make deploy HOST=192.168.1.1
```

Refresh the browser to see changes immediately. Use this during active development.

---

## First-Time Setup

1. Navigate to **Services → Speed Test → Settings**
2. Check **Accept Ookla License Agreement** — required by Ookla; passes `--accept-license --accept-gdpr` to the CLI automatically
3. Optionally enable **Scheduled Tests** and pick a cron interval
4. Click **Save Settings**
5. Switch to the **Dashboard** tab and click **Run Speed Test Now**

---

## Configuration

All settings live under **Services → Speed Test → Settings**.

| Setting | Description |
|---|---|
| Accept Ookla License | **Must be checked.** No tests will run without it. |
| Enable Scheduled Tests | Registers a cron job to run tests automatically. |
| Schedule | **Hourly** / **Every 6 h** / **Every 12 h** / **Once Daily** (3 AM) / **Custom** |
| Custom Schedule | Two cron fields: `minute hour`. Example: `30 */4` = every 4 hours at :30. |
| Speedtest Server ID | Pin tests to a specific Ookla server. Find IDs with `speedtest --servers`. Leave blank for automatic selection. |

---

## Dashboard Widget

After installing the package, a **Speed Test** widget is available on the pfSense home dashboard:

1. Go to the pfSense **Dashboard**
2. Click **+ Add widgets** (top-right)
3. Select **Speed Test**

The widget shows the last recorded download speed, upload speed, ping, jitter, ISP, and server — with a link to the full results page. No extra configuration required.

---

## Uninstalling

```sh
ssh admin@<pfsense-ip> "pkg delete pfSense-pkg-speedtest"
```

The cron job and `config.xml` entries (`installedpackages/speedtest`, `installedpackages/menu`) are removed automatically by the pre-deinstall hook. Test history at `/var/db/speedtest/` is intentionally preserved.

To also remove history:

```sh
ssh admin@<pfsense-ip> "rm -rf /var/db/speedtest"
```

---

## Development

### 1. Clone and configure

```sh
git clone https://github.com/johnathanvidu/pfSense-pkg-SpeedTest.git
cd pfSense-pkg-SpeedTest
cp .env.example .env
```

Edit `.env`:

```sh
HOST=192.168.1.1      # your pfSense IP
SSH_USER=admin        # SSH user (default: admin)
# SSH_PASS=           # optional: password auth via sshpass (brew install sshpass)
                      # leave blank to use SSH key auth (recommended)
VERSION=1.0.0
```

### 2. Recommended workflow

```
edit PHP/shell file
        ↓
make deploy HOST=192.168.1.1     ← fastest: ~2s, no build needed
        ↓
refresh browser
```

`make deploy` SCPs files directly into the correct pfSense paths and registers the package via a PHP call. Since pfSense doesn't cache PHP files, changes are live immediately.

### 3. Building a `.pkg`

Three options, in order of fidelity:

#### On macOS/Linux (no VM)

```sh
make build
```

Produces a `.pkg` using standard `tar` + `xz` + hand-crafted JSON manifests. Valid for this `NO_ARCH` package (pure PHP + shell, no compiled code). Good for CI or quick local testing.

#### On pfSense itself (highest fidelity)

```sh
make install HOST=192.168.1.1
```

Uploads sources, runs `pkg create` natively on pfSense, installs the result. No VM required. This is what the native package manager uses.

#### Inside a FreeBSD 14 VM (recommended for releases)

Produces a byte-perfect package using FreeBSD's native `pkg create`:

**Lima (macOS, recommended for Apple Silicon):**

```sh
brew install lima
make vm-start         # creates the FreeBSD 14.3 VM (~5 min first run)
make lima-fix-ssh     # one-time: inject SSH key via serial console
make build-vm         # build the .pkg inside the VM
```

> If `limactl shell` returns `Permission denied` after `make vm-start`, run `make lima-fix-ssh` once. This is a known Lima + FreeBSD cloud-init issue; see [lima/freebsd14.yaml](lima/freebsd14.yaml) for details.

**Vagrant + QEMU (macOS alternative):**

```sh
brew install vagrant
vagrant plugin install vagrant-qemu
make vagrant-up
make build-vagrant
```

### 4. Makefile reference

| Target | Description |
|---|---|
| `make build` | Build `.pkg` locally (macOS/Linux, no VM) |
| `make deploy HOST=<ip>` | Push files to pfSense over SSH (fastest dev loop) |
| `make deploy-delete HOST=<ip>` | Remove deployed files and deregister the package |
| `make install HOST=<ip>` | Build on pfSense natively + install in one step |
| `make build-vm` | Build `.pkg` inside the FreeBSD 14 Lima VM |
| `make build-vagrant` | Build `.pkg` inside the FreeBSD 14 Vagrant VM |
| `make vm-start` | Create/start the Lima VM |
| `make vm-stop` | Stop the Lima VM |
| `make vm-shell` | Open a shell inside the Lima VM |
| `make vm-destroy` | Delete the Lima VM (frees ~8 GiB) |
| `make lima-fix-ssh` | One-time SSH key injection via QEMU serial console |
| `make vagrant-up` | Create/start the Vagrant VM |
| `make vagrant-halt` | Stop the Vagrant VM |
| `make vagrant-destroy` | Delete the Vagrant VM |
| `make clean` | Remove `.pkg` files and build staging directories |
| `make help` | Print all targets with descriptions |

### 5. SSH authentication

| Method | How to enable |
|---|---|
| **SSH key** (recommended) | Add your public key to pfSense: **System → User Manager → admin → Authorized SSH Keys** |
| Password via `sshpass` | `brew install sshpass`, then set `SSH_PASS=yourpassword` in `.env` |

### 6. Installed file locations

| Path on pfSense | Purpose |
|---|---|
| `/usr/local/pkg/speedtest.inc` | PHP backend (config, cron, test execution, history) |
| `/usr/local/pkg/speedtest.xml` | Package descriptor (menu and hook registration) |
| `/usr/local/www/speedtest/speedtest.php` | Web UI (three-tab: Dashboard / History / Settings) |
| `/usr/local/www/widgets/widgets/speedtest.widget.php` | Dashboard widget |
| `/usr/local/bin/speedtest_runner.sh` | Shell wrapper — runs the Ookla CLI, writes JSON results |
| `/etc/inc/priv/speedtest.priv.inc` | pfSense privilege descriptor (controls page access) |
| `/var/db/speedtest/history.json` | Test history (last 14 results, persisted across reboots) |
| `/var/db/speedtest/current.json` | Latest raw result from the Ookla CLI |
| `/var/run/speedtest_running.pid` | PID file (present only while a test is in progress) |

---

## Project Structure

```
pfSense-pkg-speedtest/
├── Makefile                        # Developer workflow (build, deploy, VM management)
├── .env.example                    # Config template — copy to .env
├── lima/
│   └── freebsd14.yaml              # Lima VM definition (FreeBSD 14.3, QEMU)
├── vagrant/
│   └── Vagrantfile                 # Vagrant VM definition (FreeBSD 14, QEMU)
├── scripts/
│   ├── build-local.sh              # Build .pkg on macOS/Linux without a VM
│   ├── deploy.sh                   # Push files to pfSense over SSH
│   ├── remote-install.sh           # Build + install on pfSense via SSH
│   ├── vm-build.sh                 # Build script that runs inside the FreeBSD VM
│   └── lima-fix-ssh.sh             # One-time SSH key injection via QEMU serial console
└── pfSense-pkg-speedtest/
    ├── Makefile                    # Package-level build (ports-style)
    ├── pkg-descr                   # Short package description
    ├── pkg-plist                   # File manifest
    └── files/
        ├── etc/inc/priv/
        │   └── speedtest.priv.inc  # pfSense privilege descriptor
        └── usr/local/
            ├── bin/
            │   └── speedtest_runner.sh
            ├── pkg/
            │   ├── speedtest.inc
            │   └── speedtest.xml
            └── www/
                ├── speedtest/
                │   └── speedtest.php
                └── widgets/widgets/
                    └── speedtest.widget.php
```

---

## Contributing

Contributions are welcome. Please follow these steps:

1. **Fork** the repository and create a feature branch:
   ```sh
   git checkout -b feature/my-improvement
   ```

2. **Test your changes** against a real pfSense 2.7.x instance using `make deploy`.

3. **Keep commits focused** — one logical change per commit with a clear message.

4. **Open a pull request** against `main`. Describe what changed and why.

### Guidelines

- This package targets **pfSense 2.7.x** (FreeBSD 14.x). Avoid PHP features or pfSense APIs not available on that platform.
- The Ookla CLI is a dependency, not bundled here. Do not include the binary or redistribute it.
- Keep the package `NO_ARCH` — no compiled code. All logic must be PHP or POSIX shell.
- Test history (`/var/db/speedtest/`) must survive package upgrades (never delete it in post-install hooks).

### Reporting bugs

Please open a [GitHub Issue](https://github.com/johnathanvidu/pfSense-pkg-SpeedTest/issues) and include:
- pfSense version and architecture
- Steps to reproduce
- Any relevant output from **Diagnostics → System Logs → System** or the browser console

---

## License

This project is licensed under the [MIT License](LICENSE).

**Speedtest®** is a registered trademark of Ookla, LLC. This project is an independent integration and is not affiliated with, sponsored by, or endorsed by Ookla. Use of the Speedtest CLI is subject to [Ookla's terms and license](https://www.speedtest.net/apps/cli).

**pfSense®** is a registered trademark of Rubicon Communications, LLC (Netgate). This project is not affiliated with or endorsed by Netgate.
