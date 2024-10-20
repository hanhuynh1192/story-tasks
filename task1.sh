#!/bin/bash
set -euo pipefail

# Color codes for output
color_success="\e[32m"
color_reset="\e[0m"

# Functions
installGo() {
    echo -e "${color_success}--> Starting Go installation...${color_reset}"
    wget https://go.dev/dl/go1.23.2.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz
    sudo rm -f go1.23.2.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile
    echo 'export GOPATH=$HOME/go' >> ~/.profile
    echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
    source ~/.profile
    echo -e "${color_success}Go successfully installed! Version: $(go version)${color_reset}"
}

installStory() {
    echo -e "${color_success}--> Starting Story installation...${color_reset}"
    wget -qO story.tar.gz $(curl -s https://api.github.com/repos/piplabs/story/releases/latest | grep 'body' | grep -Eo 'https?://[^ ]+story-linux-amd64[^ ]+' | sed 's/......$//')
    echo "Extracting Story package..."
    tar xf story.tar.gz
    sudo cp -f story*/story /bin
    rm -rf story*/ story.tar.gz
    echo -e "${color_success}Story installation complete!${color_reset}"
}

installGeth() {
    echo -e "${color_success}--> Starting Geth installation...${color_reset}"
    wget -qO story-geth.tar.gz $(curl -s https://api.github.com/repos/piplabs/story-geth/releases/latest | grep 'body' | grep -Eo 'https?://[^ ]+geth-linux-amd64[^ ]+' | sed 's/......$//')
    echo "Extracting Geth package..."
    tar xf story-geth.tar.gz
    sudo cp geth*/geth /bin
    rm -rf geth*/ story-geth.tar.gz
    echo -e "${color_success}Geth installation complete!${color_reset}"
}

installStoryConsensus() {
    echo -e "${color_success}--> Installing Story Consensus...${color_reset}"
    wget -qO story.tar.gz $(curl -s https://api.github.com/repos/piplabs/story/releases/latest | grep 'body' | grep -Eo 'https?://[^ ]+story-linux-amd64[^ ]+' | sed 's/......$//')
    echo "Extracting Story Consensus package..."
    tar xf story.tar.gz
    sudo cp -f story*/story /bin
    rm -rf story*/ story.tar.gz
    echo -e "${color_success}Story Consensus installation complete!${color_reset}"
}

autoUpdateStory() {
    echo -e "${color_success}--> Initiating automatic Story update...${color_reset}"
    installGo
    cd $HOME && \
    rm -rf story && \
    git clone https://github.com/piplabs/story && \
    cd $HOME/story && \
    latest_branch=$(git branch -r | grep -o 'origin/[^ ]*' | grep -v 'HEAD' | tail -n 1 | cut -d '/' -f 2) && \
    git checkout $latest_branch && \
    go build -o story ./client && \
    old_bin_path=$(which story) && \
    home_path=$HOME && \
    rpc_port=$(grep -m 1 -oP '^laddr = "\K[^"]+' "$HOME/.story/story/config/config.toml" | cut -d ':' -f 3) && \
    [[ -z "$rpc_port" ]] && rpc_port=$(grep -oP 'node = "tcp://[^:]+:\K\d+' "$HOME/.story/story/config/client.toml") ; \
    tmux new -s story-upgrade "sudo bash -c 'curl -s https://raw.githubusercontent.com/itrocket-team/testnet_guides/main/utils/autoupgrade/upgrade.sh | bash -s -- -u \"1325860\" -b story -n \"$HOME/story/story\" -o \"$old_bin_path\" -h \"$home_path\" -p \"undefined\" -r \"$rpc_port\"'"
    echo -e "${color_success}Story auto-update completed!${color_reset}"
}

latestVersions() {
    echo -e "${color_success}--> Fetching latest software versions...${color_reset}"
    latestStoryVersion=$(curl -s https://api.github.com/repos/piplabs/story/releases/latest | grep tag_name | cut -d\" -f4)
    latestGethVersion=$(curl -s https://api.github.com/repos/piplabs/story-geth/releases/latest | grep tag_name | cut -d\" -f4)
    echo -e "Current Story version: $latestStoryVersion"
    echo -e "Current Geth version: $latestGethVersion"
}

mainMenu() {
    echo -e "\033[36m""Main Menu""${color_reset}"
    echo "1 Install Story"
    echo "2 Install Geth"
    echo "3 Install Story Consensus"
    echo "4 Automatic Story Update"
    echo "5 Display Latest Story and Geth Versions"
    echo "q Quit"
}

# Main Loop
while true; do
    mainMenu
    read -ep "Select an option: " user_choice
    case "$user_choice" in
        "1") installStory ;;
        "2") installGeth ;;
        "3") installStoryConsensus ;;
        "4") autoUpdateStory ;;
        "5") latestVersions ;;
        "q") exit ;;
        *) echo -e "${color_success}Invalid choice. Please select a valid option.${color_reset}" ;;
    esac
done
