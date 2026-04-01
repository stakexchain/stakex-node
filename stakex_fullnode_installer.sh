#!/usr/bin/env bash
set -euo pipefail

# StakeX Chain Full Node Installer
# Usage:
#   bash stakex_fullnode_installer.sh
# Optional env vars:
#   DATA_DIR=/data/stakex-fullnode
#   GETH_VERSION=1.13.15-c5ba367e
#   HTTP_PORT=8545
#   P2P_PORT=30303
#   GETH_BIN=/usr/local/bin/geth

DATA_DIR="${DATA_DIR:-/data/stakex-fullnode}"
GETH_VERSION="${GETH_VERSION:-1.13.15-c5ba367e}"
HTTP_PORT="${HTTP_PORT:-8545}"
P2P_PORT="${P2P_PORT:-30303}"
GETH_BIN="${GETH_BIN:-/usr/local/bin/geth}"
SERVICE_NAME="stakex-fullnode"
GENESIS_PATH="$DATA_DIR/genesis.json"
STATIC_NODES_PATH="$DATA_DIR/geth/static-nodes.json"
TMP_DIR="/tmp/geth-${GETH_VERSION}"

VPS1_ENODE="enode://877d43c3595685d54c05e4d2aa1083377961a96e64b58702150e7743856210650ed1aa40af5f8ce0e503aecb4c39b7c14536834ed3826dae81df01bc05698ae4@68.168.222.57:30303"
VPS2_ENODE="enode://539faa492b5d1938a6f1878ef17b0ea2257820333ec640269af765bef7b593f0903e27df547189ad0cc7d1e08a6082337b4a47cd5f4871f8f914df5a6785e270@209.159.159.238:30303"
VPS3_ENODE="enode://116d9ef29e5b4fbce66c5cc03d2f5f90df8a17c79317080e61796d88a15d7f52302ef0f550ba170e066d4b730f528f97ca3458c2d3c67fda1525f50e2d53aa4f@163.245.208.128:30303"

log() {
  echo "[$(date '+%F %T')] $*"
}

require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "Run as root: sudo bash $0"
    exit 1
  fi
}

install_prereqs() {
  log "Installing prerequisites..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y wget tar ufw curl
}

install_geth() {
  if command -v geth >/dev/null 2>&1; then
    local current
    current="$(geth version 2>/dev/null | awk -F': ' '/Version:/ {print $2}' | head -n1 || true)"
    log "Existing geth detected: ${current:-unknown}"
  fi

  log "Installing geth ${GETH_VERSION}..."
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  cd /tmp
  wget -q --show-progress "https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-${GETH_VERSION}.tar.gz" -O "/tmp/geth-${GETH_VERSION}.tar.gz"
  tar -xzf "/tmp/geth-${GETH_VERSION}.tar.gz" -C /tmp
  cp "/tmp/geth-linux-amd64-${GETH_VERSION}/geth" "$GETH_BIN"
  chmod +x "$GETH_BIN"
  ln -sf "$GETH_BIN" /usr/bin/geth
  hash -r || true
  log "Installed: $(geth version | awk -F': ' '/Version:/ {print $2}' | head -n1)"
}

write_files() {
  log "Writing genesis and static nodes..."
  mkdir -p "$DATA_DIR/geth"

  cat > "$GENESIS_PATH" <<'JSON'
{
  "config": {
    "chainId": 2007,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "berlinBlock": 0,
    "londonBlock": 0,
    "clique": {
      "period": 2,
      "epoch": 30000
    }
  },
  "difficulty": "0x1",
  "gasLimit": "0x7A1200",
  "extradata": "0x0000000000000000000000000000000000000000000000000000000000000000c294693ed5244c40f66d4d6ed7a35490fa297ce3d854946a950f9fabf677de653359e110daa4cd517f4402322da158afb9523214b5507778869afd700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "alloc": {
    "0x54FFE13ef6d79Ca78D5dEaC284e96618F0b704D9": {
      "balance": "0x116c4b4395810624000000"
    }
  }
}
JSON

  cat > "$STATIC_NODES_PATH" <<JSON
[
  "$VPS1_ENODE",
  "$VPS2_ENODE",
  "$VPS3_ENODE"
]
JSON
}

init_chain() {
  log "Initializing chain data..."
  rm -rf "$DATA_DIR/geth/chaindata" "$DATA_DIR/geth/lightchaindata" "$DATA_DIR/geth/nodes" || true
  geth --datadir "$DATA_DIR" init "$GENESIS_PATH"
}

create_service() {
  log "Creating systemd service..."
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF2
[Unit]
Description=StakeX Chain Full Node
After=network.target

[Service]
User=root
ExecStart=/usr/bin/geth --datadir $DATA_DIR --networkid 2007 --http --http.addr 0.0.0.0 --http.port $HTTP_PORT --http.api eth,net,web3 --port $P2P_PORT --syncmode full
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF2

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
}

open_firewall() {
  log "Opening firewall ports..."
  ufw allow ${P2P_PORT}/tcp || true
  ufw allow ${P2P_PORT}/udp || true
  ufw allow ${HTTP_PORT}/tcp || true
  ufw --force enable || true
}

health_check() {
  log "Waiting for service..."
  sleep 8
  systemctl --no-pager --full status "$SERVICE_NAME" || true
  echo
  log "Peer count:"
  geth attach --exec 'net.peerCount' "$DATA_DIR/geth.ipc" || true
  log "Block number:"
  geth attach --exec 'eth.blockNumber' "$DATA_DIR/geth.ipc" || true
  echo
  log "RPC URL: http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}'):${HTTP_PORT}"
}

main() {
  require_root
  install_prereqs
  install_geth
  write_files
  init_chain
  create_service
  open_firewall
  health_check
  log "Done. StakeX full node installed."
}

main "$@"
