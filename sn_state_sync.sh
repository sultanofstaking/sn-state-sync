#!/bin/bash

set -e

echo "Starting Supernova Node Setup with State Sync..."

# Step 1: Install dependencies
echo "Installing necessary dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential jq ufw git wget curl

# Step 2: Configure firewall
echo "Configuring firewall..."
sudo ufw enable
sudo ufw allow 22/tcp     # SSH
sudo ufw allow 26656/tcp  # Tendermint P2P
sudo ufw allow 26657/tcp  # Tendermint RPC
sudo ufw allow 1317/tcp   # Cosmos SDK REST API
sudo ufw allow 8545/tcp   # EVM HTTP RPC
sudo ufw allow 8546/tcp   # EVM WS RPC
sudo ufw reload

# Step 3: Setup swap space (8GB for Sentry Node)
echo "Checking for existing swap space..."
if swapon --show | grep -q '/swapfile'; then
    echo "Swap space is already configured. Skipping swap setup."
else
    echo "Setting up swap space..."
    sudo fallocate -l 8G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "Swap space configured successfully."
fi

# Step 4: Download and extract the latest Supernova binary
echo "Downloading latest Supernova binary..."
LATEST_RELEASE=$(curl -s https://api.github.com/repos/AliensZone/supernova/releases/latest)
DOWNLOAD_URL=$(echo $LATEST_RELEASE | jq -r '.assets[] | select(.name | test("Linux_arm64")).browser_download_url')
wget $DOWNLOAD_URL -O supernova_Linux_arm64.tar.gz
tar -xvf supernova_Linux_arm64.tar.gz
sudo mv ./bin/supernovad /usr/local/bin/supernovad

# Step 5: Initialize the node
echo "Initializing Supernova node..."
supernovad init supernova_node --chain-id supernova_73405-1

# Step 6: Configure state sync
echo "Configuring state sync..."
LATEST_HEIGHT=$(curl -s https://sync.novascan.io/block | jq -r .result.block.header.height)
BLOCK_HEIGHT=$((LATEST_HEIGHT - 1000))
TRUST_HASH=$(curl -s "https://sync.novascan.io/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

# Update config.toml for state sync settings
sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ; \
s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"https://sync.novascan.io,https://sync.supernova.zenon.red\"| ; \
s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT| ; \
s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"| ; \
s|^(seeds[[:space:]]+=[[:space:]]+).*$|\1\"ced855d1514b84adabe8590acd474487710ca259@167.235.79.123:26656,669d3f450f45906296e3c17c3f4fc52f4e07f8c3@49.12.72.145:26656,f5707786778283258b37b5154a520897ab4b75b5@116.203.187.234:26656\"| ; \
s|^(addr_book_strict[[:space:]]+=[[:space:]]+).*$|\1false|" ~/.supernova/config/config.toml

# Update config.toml for RocksDB settings
echo "Configuring RocksDB in config.toml..."
sed -i.bak -E "s|^(db_backend[[:space:]]+=[[:space:]]+).*$|\1\"rocksdb\"| ; \
s|^(db_dir[[:space:]]+=[[:space:]]+).*$|\1\"data/db\"|" ~/.supernova/config/config.toml

# Additional app.toml configurations
echo "Updating app.toml configurations..."
sed -i.bak -E "s|^(pruning[[:space:]]+=[[:space:]]+).*$|\1\"default\"| ; \
s|^(minimum-gas-prices[[:space:]]+=[[:space:]]+).*$|\1\"0stake\"| ; \
s|^(app-db-backend[[:space:]]+=[[:space:]]+).*$|\1\"rocksdb\"|" ~/.supernova/config/app.toml
sed -i.bak -E "s|^\[json-rpc\].*$|\[json-rpc\]\n# Enable defines if the gRPC server should be enabled.\nenable = false\n# Address defines the EVM RPC HTTP server address to bind to.\naddress = \"0.0.0.0:8545\"\n# Address defines the EVM WebSocket server address to bind to.\nws-address = \"0.0.0.0:8546\"|" ~/.supernova/config/app.toml

# Step 7: Create systemd service file
echo "Creating systemd service file..."
cat <<EOF | sudo tee /etc/systemd/system/supernova.service
[Unit]
Description=Supernova Node Service
After=network.target

[Service]
LimitNOFILE=32768
User=root
Group=root
Type=simple
ExecStart=/usr/local/bin/supernovad start
ExecStop=/bin/kill -s SIGTERM \$MAINPID
Restart=on-failure
TimeoutStopSec=120s
TimeoutStartSec=30s

[Install]
WantedBy=multi-user.target
EOF

# Step 8: Start the service
echo "Starting Supernova node service..."
sudo systemctl daemon-reload
sudo systemctl enable supernova.service
sudo systemctl start supernova.service

# Step 9: Confirm node setup
echo "Checking node status..."
supernovad status 2>&1 | jq '.SyncInfo'

echo "Supernova node setup and state sync completed successfully!"
