#!/bin/bash

# Define colors for improved logging
color_green="\e[32m"
color_pink="\e[35m"
color_cyan="\e[36m"
color_reset="\e[0m"

# Function to display section headers
log_section() {
    echo -e "${color_cyan}========== $1 ==========${color_reset}"
}

# Function to check the status of services
check_service_status() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        echo -e "${color_green}$service is running.${color_reset}"
    else
        echo -e "${color_pink}$service is not running.${color_reset}"
    fi
}

# Step 1: Update and upgrade the system
log_section "Update and Upgrade the System"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Step 2: Install necessary dependencies
log_section "Install Necessary Dependencies"
apt-get install -y curl tar wget original-awk gawk netcat jq

# Step 3: Ensure the script is run as root
log_section "Ensure Script is Run as Root"
if [ "$EUID" -ne 0 ]; then
    echo -e "${color_pink}Please run the script as root.${color_reset}"
    exit 1
fi

# Step 4: Receive the node's status
log_section "Receive Node Status"
rpc_port=$(awk '/\[rpc\]/ {f=1} f && /laddr/ {match($0, /127.0.0.1:([0-9]+)/, arr); print arr[1]; f=0}' $HOME/.story/story/config/config.toml)
node_status=$(curl -s http://localhost:$rpc_port/status)
validator_address=$(echo "$node_status" | jq -r '.result.validator_info.address')
network_id=$(echo "$node_status" | jq -r '.result.node_info.network')

source .bash_profile

# Step 5: Create necessary directories
log_section "Create Necessary Directories"
directories=("/var/lib/prometheus" "/etc/prometheus/rules" "/etc/prometheus/rules.d" "/etc/prometheus/files_sd")
for dir in "${directories[@]}"; do
    if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
        echo "$dir already exists and is not empty. Skipping..."
    else
        mkdir -p "$dir"
        echo "Created directory: $dir"
    fi
done

# Step 6: Download and extract Prometheus
log_section "Download and Extract Prometheus"
cd $HOME
rm -rf prometheus*
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
sleep 1
tar xvf prometheus-2.45.0.linux-amd64.tar.gz
rm prometheus-2.45.0.linux-amd64.tar.gz
cd prometheus*/

# Step 7: Move consoles and libraries if necessary
if [ ! -d "/etc/prometheus/consoles" ]; then
    mv consoles /etc/prometheus/
fi
if [ ! -d "/etc/prometheus/console_libraries" ]; then
    mv console_libraries /etc/prometheus/
fi

mv prometheus promtool /usr/local/bin/

# Step 8: Define Prometheus config
log_section "Define Prometheus Configuration"
cat <<EOF | sudo tee /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
alerting:
  alertmanagers:
    - static_configs:
        - targets: []
scrape_configs:
  - job_name: "prometheus"
    metrics_path: /metrics
    static_configs:
      - targets: ["localhost:9345"]
  - job_name: "story"
    scrape_interval: 5s
    metrics_path: /
    static_configs:
      - targets: ['localhost:26660']
EOF

# Step 9: Create Prometheus systemd service
log_section "Create Prometheus Service"
cat <<EOF | sudo tee /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=root
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9344
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Step 10: Reload systemd and start Prometheus
log_section "Reload Systemd and Start Prometheus"
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

# Step 11: Check Prometheus service status
check_service_status "prometheus"

# Step 12: Install Grafana
log_section "Install Grafana"
apt-get install -y apt-transport-https software-properties-common wget
wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
echo "deb https://packages.grafana.com/enterprise/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
apt-get update -y
apt-get install grafana-enterprise -y
systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server

# Step 13: Check Grafana service status
check_service_status "grafana-server"

# Step 14: Install and start Prometheus Node Exporter
log_section "Install and Start Prometheus Node Exporter"
apt install prometheus-node-exporter -y

# Step 15: Create Prometheus Node Exporter service
cat <<EOF | sudo tee /etc/systemd/system/prometheus-node-exporter.service
[Unit]
Description=prometheus-node-exporter
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=$USER
ExecStart=/usr/bin/prometheus-node-exporter --web.listen-address=0.0.0.0:9345
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

# Step 16: Update Grafana port
log_section "Update Grafana Port"
grafana_config="/etc/grafana/grafana.ini"
new_grafana_port="9346"
if [ ! -f "$grafana_config" ]; then
    echo -e "${color_pink}Grafana configuration file not found: $grafana_config${color_reset}"
    exit 1
fi
sed -i "s/^;http_port = .*/http_port = $new_grafana_port/" "$grafana_config"
systemctl restart grafana-server
check_service_status "grafana-server"

# Step 17: Enable Prometheus in story.toml
log_section "Enable Prometheus in story.toml"
story_config="$HOME/.story/story/config/config.toml"
sed -i "s/prometheus = false/prometheus = true/g" "$story_config"

# Step 18: Reload services
log_section "Reload Services"
systemctl restart prometheus-node-exporter
systemctl restart prometheus
systemctl restart grafana-server
systemctl restart story

# Step 19: Check final service statuses
sleep 3
check_service_status "prometheus-node-exporter"
check_service_status "prometheus"
check_service_status "grafana-server"
check_service_status "story"

# Step 20: Configure Grafana API for Prometheus and Dashboard
log_section "Configure Grafana API and Dashboard"
grafana_url="http://localhost:9346"
admin_user="admin"
admin_pass="admin"
prometheus_url="http://localhost:9344"
dashboard_url="https://raw.githubusercontent.com/encipher88/story-grafana/main/story.json"

# Step 21: Download and update dashboard with validator address
log_section "Download and Modify Dashboard"
curl -s "$dashboard_url" -o $HOME/story.json
sed -i "s/FCB1BF9FBACE6819137DFC999255175B7CA23C5D/$validator_address/g" $HOME/story.json

# Step 22: Add Prometheus data source to Grafana
log_section "Add Prometheus Data Source to Grafana"
curl -X POST "$grafana_url/api/datasources" \
    -H "Content-Type: application/json" \
    -u "$admin_user:$admin_pass" \
    -d '{
          "name": "Prometheus",
          "type": "prometheus",
          "access": "proxy",
          "url": "'"$prometheus_url"'",
          "basicAuth": false,
          "isDefault": true,
          "jsonData": {}
        }'

# Step 23: Import modified dashboard to Grafana
log_section "Import Modified Dashboard into Grafana"
curl -X POST "$grafana_url/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -u "$admin_user:$admin_pass" \
    -d '{
          "dashboard": '"$(cat "$HOME/story.json")"',
          "overwrite": true,
          "folderId": 0
        }'

# Final log messages and dashboard access details
echo -e "${color_green}**********************************${color_reset}"
echo -e "${color_green}Installation Complete! Dashboard successfully imported.${color_reset}"
echo -e "${color_green}Grafana accessible at: http://localhost:$new_grafana_port/d/UJyurCTWz/${color_reset}"
echo -e "${color_pink}Login credentials:${color_reset}"
echo -e "${color_pink}Username: admin | Password: admin${color_reset}"
echo -e "${color_pink}Validator Address: $validator_address | Network ID: $network_id${color_reset}"
echo -e "${color_green}**********************************${color_reset}"
