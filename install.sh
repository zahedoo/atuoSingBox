#!/bin/bash

# Automated sing-box Installer
# Follows the exact workflow:
# 1. Prompt for JSON config URL
# 2. Check if SSL certificate generation is requested by the user
# 3. If requested, prompt for domain name and automatically generate certificates, otherwise skip SSL setup
# 4. Automatically handle all remaining setup tasks
# 5. Start the service and complete

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}    sing-box Auto Installer     ${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Step 1: Prompt for JSON config URL
read -p "Enter the URL for JSON configuration: " config_url

# Step 2: Check if SSL certificate generation is requested by the user
echo ""
read -p "Do you want to generate SSL certificates? (y/N): " need_ssl
need_ssl=${need_ssl:-N}

# Step 3: If requested, prompt for domain name and automatically generate certificates, otherwise skip SSL setup
if [[ "$need_ssl" =~ ^[Yy]$ ]]; then
    read -p "Enter your domain name: " domain_name
fi

echo ""
echo -e "${YELLOW}Starting installation...${NC}"
echo ""

# Step 4: Automatically handle all remaining setup tasks
# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check if jq is installed
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

# Check if openssl is needed and installed
if [[ "$need_ssl" =~ ^[Yy]$ ]]; then
    if ! command -v openssl &> /dev/null; then
        echo -e "${YELLOW}Installing openssl...${NC}"
        if [ -n "$(command -v apt)" ]; then
            apt install -y openssl > /dev/null 2>&1
        elif [ -n "$(command -v yum)" ]; then
            yum install -y openssl > /dev/null 2>&1
        elif [ -n "$(command -v dnf)" ]; then
            dnf install -y openssl > /dev/null 2>&1
        else
            echo -e "${RED}Cannot install openssl automatically. Please install manually.${NC}"
            exit 1
        fi
    fi
fi

# Create required directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p /root/sing-box
if [[ "$need_ssl" =~ ^[Yy]$ ]]; then
    mkdir -p /root/sing-box/certs
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

# Generate SSL certificates if needed
if [[ "$need_ssl" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Generating SSL certificates for $domain_name...${NC}"
    
    # Generate certificate for the domain
    openssl req -x509 -newkey rsa:4096 -keyout /root/sing-box/certs/${domain_name}.key \
        -out /root/sing-box/certs/${domain_name}.crt -days 365 -nodes \
        -subj "/C=US/ST=California/L=Los Angeles/O=Sing-box Certificate/CN=${domain_name}"
    
    echo -e "${GREEN}SSL certificates generated for $domain_name${NC}"
fi

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

# Step 5: Start the service and complete
echo -e "${YELLOW}Starting sing-box service...${NC}"
systemctl daemon-reload
systemctl enable sing-box > /dev/null 2>&1
systemctl start sing-box

# Wait a moment for the service to start
sleep 3

# Final check and summary
if systemctl is-active --quiet sing-box; then
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}  Installation completed!       ${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo -e "${BLUE}Service:${NC} Active"
    echo -e "${BLUE}Config:${NC} $config_url"
    if [[ "$need_ssl" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Domain:${NC} $domain_name"
        echo -e "${BLUE}SSL Certs:${NC} /root/sing-box/certs/${domain_name}.*"
    fi
    echo ""
else
    echo -e "${RED}================================${NC}"
    echo -e "${RED}  Installation failed!          ${NC}"
    echo -e "${RED}================================${NC}"
    echo ""
    echo "Service status:"
    systemctl status sing-box --no-pager
    exit 1
fi
