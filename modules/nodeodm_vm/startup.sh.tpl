#!/bin/bash
# ---------------------------------------------------------------------------
# NodeODM Spot VM startup script — Debian 12
#
# Installs NVIDIA drivers + Docker, fetches the NodeODM auth token from
# Secret Manager, and starts opendronemap/nodeodm on port 3000.
# Logs are forwarded to Cloud Logging via the gcplogs Docker driver.
#
# The script is idempotent: if NVIDIA drivers are already present (e.g. after
# a Spot preemption and restart), it skips driver installation and reboot.
# ---------------------------------------------------------------------------

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

PROJECT_ID="${project_id}"
NODEODM_TOKEN_SECRET="${nodeodm_token_secret_id}"
STARTUP_LOG="/var/log/flowterra-startup.log"

log() { echo "[startup] $*" | tee -a "$STARTUP_LOG"; }

log "=== Flowterra NodeODM startup: $(date) ==="

# ---------------------------------------------------------------------------
# 1. NVIDIA driver installation (skipped if already loaded)
# ---------------------------------------------------------------------------
if nvidia-smi &>/dev/null; then
  log "NVIDIA driver already active: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo unknown)"
else
  log "Installing NVIDIA drivers..."
  apt-get update -qq
  apt-get install -y -qq linux-headers-amd64 gcc make dkms curl gnupg lsb-release

  # Add NVIDIA CUDA repo for Debian 12
  curl -fsSL "https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/3bf863cc.pub" \
    | gpg --dearmor -o /usr/share/keyrings/nvidia-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/nvidia-keyring.gpg] \
    https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /" \
    > /etc/apt/sources.list.d/nvidia-cuda.list
  apt-get update -qq
  apt-get install -y -qq cuda-drivers

  log "NVIDIA drivers installed — rebooting to load kernel module..."
  reboot
  exit 0
fi

# Confirm driver is functional; output captured in startup log for AC validation
nvidia-smi | tee -a "$STARTUP_LOG"

# ---------------------------------------------------------------------------
# 2. Docker CE + NVIDIA container toolkit (idempotent)
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
  log "Installing Docker CE..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io
  log "Docker installed."
else
  log "Docker already present — skipping install."
fi

if ! dpkg -l nvidia-docker2 &>/dev/null; then
  log "Installing NVIDIA Docker runtime..."
  apt-get install -y -qq nvidia-docker2
  systemctl restart docker
  log "NVIDIA Docker runtime installed."
fi

# ---------------------------------------------------------------------------
# 3. Fetch NodeODM auth token from Secret Manager
# ---------------------------------------------------------------------------
log "Fetching NodeODM token from Secret Manager..."
NODE_ODM_TOKEN=$(gcloud secrets versions access latest \
  --secret="$NODEODM_TOKEN_SECRET" \
  --project="$PROJECT_ID" 2>/dev/null || true)

if [[ -z "$NODE_ODM_TOKEN" ]]; then
  log "WARNING: NodeODM token not found — running without token auth (dev only)."
fi

# ---------------------------------------------------------------------------
# 4. Start NodeODM (restart if already running with stale config)
# ---------------------------------------------------------------------------
if docker ps -q --filter "name=nodeodm" | grep -q .; then
  log "NodeODM already running — stopping for restart."
  docker stop nodeodm && docker rm nodeodm
fi

log "Starting NodeODM..."
DOCKER_ARGS=(
  --name nodeodm
  --restart unless-stopped
  -p 3000:3000
  --gpus all
  --log-driver=gcplogs
  --log-opt "gcp-project=$PROJECT_ID"
  --log-opt "labels=service=flowterra-nodeodm"
  opendronemap/nodeodm
)
[[ -n "$NODE_ODM_TOKEN" ]] && DOCKER_ARGS+=(--token "$NODE_ODM_TOKEN")

docker run -d "${DOCKER_ARGS[@]}"
log "NodeODM started on port 3000."
log "=== Startup complete ==="
