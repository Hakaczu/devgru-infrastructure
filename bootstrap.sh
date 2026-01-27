#!/bin/bash
# Bootstrap Hydra-0 (Alpine Linux)

set -e

echo "Starting Hydra-0 bootstrap..."

echo "Updating packages..."
apk update && apk upgrade

echo "Installing dependencies..."
apk add --no-cache python3 py3-pip ansible git

if [ ! -f configuration/inventory/production.ini ]; then
    echo "Creating Ansible inventory file for Hydra-0..."
    mkdir -p configuration/inventory
    cat > configuration/inventory/production.ini <<'EOF'
[control_nodes]
hydra-0 ansible_connection=local
EOF
    echo "Inventory file created at configuration/inventory/production.ini"
else
    echo "Ansible inventory file already exists at configuration/inventory/production.ini"
fi


