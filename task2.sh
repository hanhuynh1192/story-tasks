#!/bin/bash

# Define colors for enhanced logging
COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_BOLD="\033[1m"
COLOR_RESET="\033[0m"

# Logging functions for improved output
log_info() {
  echo -e "${COLOR_CYAN}[INFO] $1${COLOR_RESET}"
}

log_success() {
  echo -e "${COLOR_GREEN}[SUCCESS] $1${COLOR_RESET}"
}

log_warning() {
  echo -e "${COLOR_YELLOW}[WARNING] $1${COLOR_RESET}"
}

log_error() {
  echo -e "${COLOR_RED}[ERROR] $1${COLOR_RESET}"
}

log_separator() {
  echo -e "${COLOR_BOLD}----------------------------------------${COLOR_RESET}"
}

# Step 1: Update and install necessary packages
log_info "Step 1: Installing required dependencies..." && sleep 1
sudo apt-get update -y
sudo apt-get install -y curl git wget htop tmux jq make lz4 unzip bc

# Define constants and variables
network_type="testnet"
project_name="story"
server_root_url="server-3.itrocket.net"
story_dir_path="$HOME/.story/story"
geth_dir_path="$HOME/.story/geth/iliad/geth"
FILE_SERVER_LIST=(
  "https://server-3.itrocket.net/testnet/story/.current_state.json"
  "https://server-1.itrocket.net/testnet/story/.current_state.json"
  "https://server-5.itrocket.net/testnet/story/.current_state.json"
)
RPC_ENDPOINT="https://story-testnet-rpc.itrocket.net"
MAX_RETRIES=3
TEST_FILE_SIZE_BYTES=50000000  # Size of test file for download speed checks

# Function to retrieve snapshot data from server
fetch_snapshot_data() {
  local snapshot_url=$1
  local attempt=0
  local response_data=""

  while (( attempt < MAX_RETRIES )); do
    response_data=$(curl -s --max-time 5 "$snapshot_url")
    if [[ -n "$response_data" ]]; then
      break
    else
      ((attempt++))
      sleep 1
    fi
  done

  echo "$response_data"
}

# Function to display available snapshots for user
show_snapshots() {
  local snapshot_list=("$@")
  log_success "Available snapshots:"
  log_separator
  for i in "${!snapshot_list[@]}"; do
    IFS='|' read -r server_number snapshot_name snapshot_height blocks_behind snapshot_age total_size_gb snapshot_size geth_size estimated_time server_url snapshot_filename geth_filename <<< "${snapshot_list[$i]}"
    echo "[$i] Server $server_number: $snapshot_name | Height: $snapshot_height | Age: $snapshot_age | Size: $total_size_gb GB | Est. Time: $estimated_time"
  done
}

# Function to install selected snapshot
install_snapshot() {
  local selected_snapshot=$1
  local selected_geth=$2
  local snapshot_server_url=$3

  log_info "Installing snapshot from $snapshot_server_url:"
  log_separator
  log_info "Stopping Story and Geth services..." && sleep 1
  sudo systemctl stop story story-geth

  log_info "Backing up priv_validator_state.json..." && sleep 1
  cp "$story_dir_path/data/priv_validator_state.json" "$story_dir_path/priv_validator_state.json.backup"

  log_info "Clearing old data and extracting Story snapshot..." && sleep 1
  rm -rf "$story_dir_path/data"
  curl "$snapshot_server_url/${network_type}/${project_name}/$selected_snapshot" | lz4 -dc - | tar -xf - -C "$story_dir_path"

  log_info "Restoring priv_validator_state.json..." && sleep 1
  mv "$story_dir_path/priv_validator_state.json.backup" "$story_dir_path/data/priv_validator_state.json"

  log_info "Clearing old Geth data and extracting Geth snapshot..." && sleep 1
  rm -rf "$geth_dir_path/chaindata"
  curl "$snapshot_server_url/${network_type}/${project_name}/$selected_geth" | lz4 -dc - | tar -xf - -C "$geth_dir_path"

  log_info "Restarting Story and Geth services..." && sleep 1
  sudo systemctl restart story story-geth

  log_success "Snapshot installation completed successfully."
}

# Fetch snapshot data from available servers
SNAPSHOT_OPTIONS=()
for file_server in "${FILE_SERVER_LIST[@]}"; do
  snapshot_data=$(fetch_snapshot_data "$file_server")
  if [[ -n "$snapshot_data" ]]; then
    server_base_url=$(echo "$file_server" | sed "s|/${network_type}/${project_name}/.current_state.json||")
    server_number=$(echo "$server_base_url" | grep -oP 'server-\K[0-9]+')
    snapshot_name=$(echo "$snapshot_data" | jq -r '.snapshot_name')
    geth_snapshot_name=$(echo "$snapshot_data" | jq -r '.snapshot_geth_name')
    snapshot_height=$(echo "$snapshot_data" | jq -r '.snapshot_height')
    snapshot_size=$(echo "$snapshot_data" | jq -r '.snapshot_size')
    geth_snapshot_size=$(echo "$snapshot_data" | jq -r '.geth_snapshot_size')
    total_size_gb=$(echo "$snapshot_size + $geth_snapshot_size" | bc)
    snapshot_age=$(echo "$snapshot_data" | jq -r '.snapshot_age')
    estimated_time="N/A"  # Placeholder for estimated time calculation
    SNAPSHOT_OPTIONS+=("$server_number|$snapshot_name|$snapshot_height|$snapshot_age|$total_size_gb|$snapshot_size|$geth_snapshot_size|$estimated_time|$server_base_url|$snapshot_name|$geth_snapshot_name")
  fi
done

# Display available snapshots to the user
show_snapshots "${SNAPSHOT_OPTIONS[@]}"

# Prompt the user to choose a snapshot for installation
read -p "Select the snapshot number you wish to install: " selected_option

# Validate user input and install the selected snapshot
if [[ "$selected_option" =~ ^[0-9]+$ ]] && [ "$selected_option" -ge 0 ] && [ "$selected_option" -lt "${#SNAPSHOT_OPTIONS[@]}" ]; then
  IFS='|' read -r server_number snapshot_filename snapshot_height snapshot_age total_size_gb snapshot_size geth_snapshot_size estimated_time server_base_url snapshot_filename geth_filename <<< "${SNAPSHOT_OPTIONS[$selected_option]}"
  install_snapshot "$snapshot_filename" "$geth_filename" "$server_base_url"
else
  log_error "Invalid selection. Exiting."
  exit 1
fi
