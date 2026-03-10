# pfSense-pkg-speedtest — macOS developer Makefile (GNU make)
#
# ---------------------------------------------------------------------------
# Quick reference
# ---------------------------------------------------------------------------
#
#   make build                  Build .pkg on macOS (no VM — works today)
#   make deploy        HOST=<ip>  Push files to pfSense via SSH (fastest)
#   make deploy-delete HOST=<ip>  Remove deployed files and deregister
#   make install HOST=<ip>      Build .pkg and install on pfSense
#
#   make build-vm               Build .pkg inside FreeBSD 14 Lima VM
#                               Requires Lima v2.1+ (in beta, March 2026)
#                               See lima/freebsd14.yaml for setup notes
#
# ---------------------------------------------------------------------------
# Configuration — copy .env.example to .env and fill in your values.
# Variables defined in .env override the defaults below.
# ---------------------------------------------------------------------------

-include .env

# Project identity — fixed, not deployment-specific.
MAINTAINER := Johnathan Viduchinsky
PKG_WWW    := https://github.com/johnathanvidu/pfSense-pkg-SpeedTest

# Deployment config — override in .env or on the command line.
VERSION   ?= 1.0.0
HOST      ?=
SSH_USER  ?=
LIMA_INST ?= freebsd14

# sshpass support: set SSH_PASS in .env to enable password auth.
# Key-based auth is used when SSH_PASS is unset.
ifneq ($(SSH_PASS),)
export SSHPASS := $(SSH_PASS)
SSH_CMD  = sshpass -e ssh
SCP_CMD  = sshpass -e scp
else
SSH_CMD  = ssh
SCP_CMD  = scp
endif
SSH_OPTS = -o StrictHostKeyChecking=no -o BatchMode=no

PKG_FILE  := pfSense-pkg-speedtest-$(VERSION).pkg

.PHONY: build build-vm deploy deploy-delete install \
        vm-start vm-stop vm-shell vm-destroy lima-fix-ssh \
        build-vagrant vagrant-up vagrant-halt vagrant-destroy \
        clean help _vm-ensure _vagrant-ensure

# ---------------------------------------------------------------------------
# build — build .pkg on macOS using standard tools (no VM required)
# ---------------------------------------------------------------------------
# Valid for NO_BUILD + NO_ARCH packages (pure PHP + shell, no compiled code).
# The .pkg format is a well-defined tar.xz + JSON manifest; this script
# produces a byte-identical result to what FreeBSD's `pkg create` would.

build:
	@sh scripts/build-local.sh $(VERSION)
	@echo ""
	@ls -lh $(PKG_FILE)

# ---------------------------------------------------------------------------
# deploy — push files directly to pfSense over SSH (no .pkg, no VM)
# ---------------------------------------------------------------------------
# Fastest iteration loop: edit a PHP file, run make deploy, reload browser.
# SSH auth: key-based preferred; set SSHPASS env var or use ./sshpassword.

deploy:
	@test -n "$(HOST)" || (echo "ERROR: set HOST=<pfsense-ip>  e.g. make deploy HOST=192.168.1.1"; exit 1)
	@sh scripts/deploy.sh $(HOST) $(SSH_USER)

# ---------------------------------------------------------------------------
# deploy-delete — remove deployed files from pfSense and deregister package
# ---------------------------------------------------------------------------
# Mirrors deploy in reverse: removes every file that deploy copied, then
# calls speedtest_deinstall() to clean up menu entries and config.xml.
# History files at /var/db/speedtest/ are preserved (user data).

deploy-delete:
	@test -n "$(HOST)" || (echo "ERROR: set HOST=<pfsense-ip>  e.g. make deploy-delete HOST=192.168.1.1"; exit 1)
	@echo "==> Deregistering package on $(HOST)..."
	@$(SSH_CMD) $(SSH_OPTS) $(SSH_USER)@$(HOST) \
	    "php -r \"require_once('/etc/inc/config.inc'); require_once('/etc/inc/util.inc'); require_once('/usr/local/pkg/speedtest.inc'); speedtest_deinstall(); echo 'Deregistration: OK' . PHP_EOL;\" 2>/dev/null || true"
	@echo "==> Removing deployed files..."
	@$(SSH_CMD) $(SSH_OPTS) $(SSH_USER)@$(HOST) \
	    "rm -f \
	        /usr/local/pkg/speedtest.xml \
	        /usr/local/pkg/speedtest.inc \
	        /usr/local/www/speedtest/speedtest.php \
	        /usr/local/www/widgets/widgets/speedtest.widget.php \
	        /usr/local/bin/speedtest_runner.sh \
	        /etc/inc/priv/speedtest.priv.inc && \
	     rmdir /usr/local/www/speedtest 2>/dev/null || true"
	@echo "==> Done. Files removed from $(HOST)."

# ---------------------------------------------------------------------------
# install — build .pkg then install it on pfSense via pkg add
# ---------------------------------------------------------------------------

install:
	@test -n "$(HOST)" || (echo "ERROR: set HOST=<pfsense-ip>  e.g. make install HOST=192.168.1.1"; exit 1)
	@sh scripts/remote-install.sh $(HOST) $(SSH_USER) $(VERSION)

# ---------------------------------------------------------------------------
# build-vm — build .pkg inside a native FreeBSD 14 Lima VM
# ---------------------------------------------------------------------------
# Requires Lima v2.1+ (FreeBSD guest support is experimental, added in v2.1).
# As of March 2026, Lima v2.1 is in beta. See lima/freebsd14.yaml for details.
#
# Workflow:
#   1. Ensure Lima VM is running (creates it on first run, ~5 min)
#   2. Upload package source files into the VM via limactl cp
#   3. Run scripts/vm-build.sh inside the VM (uses native pkg create)
#   4. Download the resulting .pkg back to the host

build-vm: _vm-ensure
	@echo "==> Uploading source files to VM..."
	@limactl shell $(LIMA_INST) -- rm -rf /tmp/pkg-files
	@limactl cp -r pfSense-pkg-speedtest/files $(LIMA_INST):/tmp/pkg-files
	@limactl cp scripts/vm-build.sh $(LIMA_INST):/tmp/vm-build.sh
	@echo "==> Building $(PKG_FILE) inside FreeBSD VM..."
	@limactl shell $(LIMA_INST) -- sh /tmp/vm-build.sh $(VERSION) $(MAINTAINER) $(PKG_WWW)
	@echo "==> Downloading $(PKG_FILE)..."
	@limactl cp $(LIMA_INST):/tmp/$(PKG_FILE) $(PKG_FILE)
	@echo ""
	@ls -lh $(PKG_FILE)
	@echo "==> Build complete: $(PKG_FILE)"

# ---------------------------------------------------------------------------
# Lima VM management (for build-vm target)
# ---------------------------------------------------------------------------

vm-start: _vm-ensure

vm-stop:
	limactl stop $(LIMA_INST)

vm-shell:
	limactl shell $(LIMA_INST)

vm-destroy:
	limactl delete --force $(LIMA_INST)

# lima-fix-ssh — one-time SSH key injection via the QEMU serial console.
# Run this once if `limactl shell` returns "Permission denied".
# Requires: brew install expect
lima-fix-ssh:
	@sh scripts/lima-fix-ssh.sh $(LIMA_INST)

# ---------------------------------------------------------------------------
# build-vagrant — build .pkg inside a FreeBSD 14 Vagrant/QEMU VM
# ---------------------------------------------------------------------------
# Requires:
#   brew install vagrant
#   vagrant plugin install vagrant-qemu
#
# On Apple Silicon: runs x86_64 FreeBSD under QEMU software emulation.
# Slower than Lima but avoids the cloud-init SSH key injection bug.

build-vagrant: _vagrant-ensure
	@echo "==> Generating Vagrant SSH config..."
	@cd vagrant && vagrant ssh-config > /tmp/speedtest-vssh.config
	@echo "==> Uploading source files to Vagrant VM..."
	@ssh -F /tmp/speedtest-vssh.config default "rm -rf /tmp/pkg-files && mkdir -p /tmp/pkg-files"
	@scp -F /tmp/speedtest-vssh.config -r pfSense-pkg-speedtest/files/. default:/tmp/pkg-files/
	@scp -F /tmp/speedtest-vssh.config scripts/vm-build.sh default:/tmp/vm-build.sh
	@echo "==> Building $(PKG_FILE) inside Vagrant VM..."
	@ssh -F /tmp/speedtest-vssh.config default "sh /tmp/vm-build.sh $(VERSION) '$(MAINTAINER)' '$(PKG_WWW)'"
	@echo "==> Downloading $(PKG_FILE)..."
	@scp -F /tmp/speedtest-vssh.config default:/tmp/$(PKG_FILE) $(PKG_FILE)
	@rm -f /tmp/speedtest-vssh.config
	@echo ""
	@ls -lh $(PKG_FILE)
	@echo "==> Build complete: $(PKG_FILE)"

# ---------------------------------------------------------------------------
# Vagrant VM management
# ---------------------------------------------------------------------------

vagrant-up: _vagrant-ensure

vagrant-halt:
	@cd vagrant && vagrant halt

vagrant-destroy:
	@cd vagrant && vagrant destroy -f

# Internal: verify vagrant + plugin, start VM if not running.
_vagrant-ensure:
	@command -v vagrant >/dev/null 2>&1 || \
	    (echo "ERROR: vagrant not found.  Install: brew install vagrant"; exit 1)
	@vagrant plugin list 2>/dev/null | grep -q vagrant-qemu || \
	    (echo "ERROR: vagrant-qemu plugin missing.  Install: vagrant plugin install vagrant-qemu"; exit 1)
	@cd vagrant && (vagrant status 2>/dev/null | grep -q running || vagrant up)

# Internal: create the VM if it doesn't exist, start it if stopped.
_vm-ensure:
	@if limactl ls 2>/dev/null | awk 'NR>1 {print $$1, $$2}' \
	        | grep -q "^$(LIMA_INST) Running$$"; then \
	    true; \
	elif limactl ls 2>/dev/null | awk 'NR>1 {print $$1}' \
	        | grep -q "^$(LIMA_INST)$$"; then \
	    echo "==> Starting Lima VM: $(LIMA_INST)"; \
	    limactl start $(LIMA_INST); \
	else \
	    echo "==> Creating Lima VM: $(LIMA_INST) (first run — downloads FreeBSD 14 image)"; \
	    limactl start --name=$(LIMA_INST) lima/freebsd14.yaml; \
	fi

# ---------------------------------------------------------------------------

clean:
	rm -f $(PKG_FILE)
	rm -rf _build/

help:
	@echo ""
	@echo "pfSense-pkg-speedtest build targets:"
	@echo ""
	@echo "  make build                    Build .pkg on macOS (no VM required)"
	@echo "  make deploy        HOST=<ip>  Push files to pfSense via SSH (no build)"
	@echo "  make deploy-delete HOST=<ip>  Remove deployed files and deregister"
	@echo "  make install  HOST=<ip>       Build .pkg on pfSense via SSH and install"
	@echo "  make build-vm                 Build .pkg in FreeBSD 14 Lima VM (requires Lima v2.1+)"
	@echo "  make build-vagrant            Build .pkg in FreeBSD 14 Vagrant/QEMU VM"
	@echo ""
	@echo "Lima VM management:"
	@echo "  make vm-start               Start (or create) FreeBSD 14 Lima VM"
	@echo "  make vm-stop                Stop the Lima VM"
	@echo "  make vm-shell               Open an interactive shell in the Lima VM"
	@echo "  make vm-destroy             Delete Lima VM and free disk space"
	@echo "  make lima-fix-ssh           Fix SSH (run once if limactl shell gives Permission denied)"
	@echo ""
	@echo "Vagrant VM management (alternative to Lima):"
	@echo "  make vagrant-up             Start (or create) FreeBSD 14 Vagrant VM"
	@echo "  make vagrant-halt           Suspend the Vagrant VM"
	@echo "  make vagrant-destroy        Delete Vagrant VM and free disk space"
	@echo ""
	@echo "Variables (set in .env or override on command line):"
	@echo "  HOST=$(HOST)   SSH_USER=$(SSH_USER)   VERSION=$(VERSION)"
	@echo "  LIMA_INST=$(LIMA_INST)"
	@echo ""
	@echo "SSH auth: key-based auth preferred; set SSH_PASS in .env for password auth"
	@echo "  Copy .env.example to .env and fill in SSH_PASS (requires: brew install sshpass)"
	@echo ""
