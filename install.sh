#!/bin/bash

# Ultra Minimal sing-box Installer
# 1. Prompt for JSON config URL
# 2. Download and install sing-box
# 3. Download configuration
# 4. Start service
# Nothing else - no SSL, no domain handling, no questions

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===============================${NC}"
echo -e "${BLUE}  Ultra Minimal sing-box Setup ${NC}"
echo -e "${BLUE}===============================${NC}"
echo ""

# Step 1: Prompt for JSON config URL
read -p "Enter the URL for JSON configuration: " config_url

echo ""
echo -e "${YELLOW}Starting ultra-minimal installation...${NC}"
echo ""

# Create required directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p /root/sing-box

# Install jq if not present (needed for version detection)
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Installing jq...${NC}"
    if [ -n "$(command -v apt)" ]; then
        apt update > /dev/null 2>&1 && apt install -y jq > /dev/null 2>&1
    elif [ -n "$(command -v yum)" ]; then
        yum install -y epel-release > /dev/null 2>&1 && yum install -y jq > /dev/null 2>&1
    elif [ -n "$(command -v dnf)" ]; then
        dnf install -y jq > /dev/null 2>&1
    else
        echo -e "${RED}Cannot install jq automatically. Please install manually.${NC}"
        exit 1
    fi
fi

# Download the latest stable release
echo -e "${YELLOW}Downloading latest stable sing-box...${NC}"
latest_version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | jq -r '[.[] | select(.prerelease==false)][0].tag_name')

# Determine architecture
arch=$(uname -m)
case $arch in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    armv7l) arch="armv7" ;;
    *) echo -e "${RED}Unsupported architecture: $arch${NC}"; exit 1 ;;
esac

# Download and extract
package_name="sing-box-${latest_version#v}-linux-${arch}"
url="https://github.com/SagerNet/sing-box/releases/download/${latest_version}/${package_name}.tar.gz"

echo -e "${YELLOW}Downloading sing-box...${NC}"
curl -sLo "/root/${package_name}.tar.gz" "$url"
tar -xzf "/root/${package_name}.tar.gz" -C /root
mv "/root/${package_name}/sing-box" /root/sing-box/sing-box

# Cleanup
rm -r "/root/${package_name}.tar.gz" "/root/${package_name}"

# Make executable
chmod +x /root/sing-box/sing-box

# Download config
echo -e "${YELLOW}Downloading configuration from $config_url...${NC}"
curl -s -o /root/sing-box/config.json "$config_url"

# Create service file
echo -e "${YELLOW}Creating systemd service...${NC}"
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root/sing-box
ExecStart=/root/sing-box/sing-box run -c /root/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# Start service
echo -e "${YELLOW}Starting sing-box service...${NC}"
systemctl daemon-reload
systemctl enable sing-box > /dev/null 2>&1
systemctl start sing-box

# Wait a moment for the service to start
sleep 3

# Final check and summary
if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}===============================${NC}"
    echo -e "${GREEN}  Installation completed!      ${NC}"
    echo -e "${GREEN}===============================${NC}"
    echo ""
    echo -e "${BLUE}Service:${NC} Active"
    echo -e "${BLUE}Config:${NC} $config_url"
    echo ""
else
    echo -e "${RED}===============================${NC}"
    echo -e "${RED}  Installation failed!         ${NC}"
    echo -e "${RED}===============================${NC}"
    echo ""
    echo "Service status:"
    systemctl status sing-box --no-pager
    exit 1
fi
