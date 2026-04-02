#!/usr/bin/env bash
set -e

echo "🚀 Installing StakeX Full Node..."

# Install dependencies
apt update
apt install -y software-properties-common curl ufw
add-apt-repository -y ppa:ethereum/ethereum
apt update
apt install -y geth

# Setup directories
mkdir -p /data/stakex/geth

# ================= GENESIS =================
cat > /data/stakex/genesis.json <<'EOF'
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
  "gasLimit": "0x7a1200",
  "extradata": "0x0000000000000000000000000000000000000000000000000000000000000000c294693ed5244c40f66d4d6ed7a35490fa297ce3d854946a950f9fabf677de653359e110daa4cd517f4402322da158afb9523214b5507778869afd70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
  "alloc": {}
}
EOF

# ================= STATIC PEERS =================
cat > /data/stakex/geth/static-nodes.json <<'EOF'
[
  "enode://68d7c1a3642160696e78f8b2ff86b9523d2d3d450fe15bf728717726c528e6da30a36dda197b71b57ef1f257c0d116a08ac0cbb36831fda98167e680fe1eae4f@68.168.222.57:30303"
]
EOF

# ================= INIT =================
systemctl stop stakex 2>/dev/null || true
pkill -9 geth 2>/dev/null || true
rm -rf /data/stakex/geth/chaindata

geth --datadir /data/stakex init /data/stakex/genesis.json

# ================= SERVICE =================
PUBLIC_IP=$(curl -s ifconfig.me || echo "0.0.0.0")

cat > /etc/systemd/system/stakex.service <<EOF
[Unit]
Description=StakeX Full Node
After=network.target

[Service]
User=root
ExecStart=/usr/bin/geth \\
  --datadir /data/stakex \\
  --networkid 2007 \\
  --http \\
  --http.addr 0.0.0.0 \\
  --http.port 8545 \\
  --http.api eth,net,web3,admin \\
  --port 30303 \\
  --ipcpath /data/stakex/geth.ipc \\
  --syncmode full \\
  --nat extip:$PUBLIC_IP
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# ================= FIREWALL =================
ufw allow 30303/tcp || true
ufw allow 30303/udp || true
ufw allow 8545/tcp || true

# ================= START =================
systemctl daemon-reload
systemctl enable stakex
systemctl restart stakex

sleep 5

echo "✅ StakeX node installed successfully!"
echo ""
echo "Check status:"
echo "systemctl status stakex"
echo ""
echo "Check sync:"
echo "geth attach --exec 'net.peerCount' /data/stakex/geth.ipc"
echo "geth attach --exec 'eth.blockNumber' /data/stakex/geth.ipc"
