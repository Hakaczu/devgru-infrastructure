#!/bin/sh
# Bootstrap Hydra-0 (Alpine Linux)

TERRAFORM_VERSION="1.7.4"
TERRAGRUNT_VERSION="v0.55.1"

set -e

echo "🚀 Starting Hydra-0 bootstrap..."

echo "📦 Updating packages..."
apk update && apk upgrade

echo "🔧 Installing dependencies..."
apk add --no-cache \
    git \
    curl \
    openssh \
    python3 \
    py3-pip \
    ansible \
    bash \
    jq

if ! command -v terraform &> /dev/null; then
    echo "🏗 Installing Terraform v${TERRAFORM_VERSION}..."
    cd /tmp
    wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    mv terraform /usr/local/bin/
    rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip
    chmod +x /usr/local/bin/terraform
else
    echo "✅ Terraform is already installed."
fi

if ! command -v terragrunt &> /dev/null; then
    echo "🏗 Installing Terragrunt ${TERRAGRUNT_VERSION}..."
    wget https://github.com/gruntwork-io/terragrunt/releases/download/${TERRAGRUNT_VERSION}/terragrunt_linux_amd64
    mv terragrunt_linux_amd64 /usr/local/bin/terragrunt
    chmod +x /usr/local/bin/terragrunt
else
    echo "✅ Terragrunt is already installed."
fi

if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "🔑 Generating SSH key..."
    ssh-keygen -t ed25519 -C "hydra-0-control-node" -f ~/.ssh/id_ed25519 -N ""
    echo "⚠️  Important: Copy the public key below to GitHub (Deploy Key) and to hydra-1..3 servers:"
    cat ~/.ssh/id_ed25519.pub
else
    echo "✅ SSH key already exists."
fi

echo "🎉 Bootstrap finished!"

if [ ! -f configuration/inventory/production.ini ]; then
    echo "📝 Creating Ansible inventory file for Hydra-0..."
    mkdir -p configuration/inventory
    cat > configuration/inventory/production.ini <<'EOF'
[control_nodes]
hydra-0 ansible_connection=local
EOF
    echo "✅ Inventory file created at configuration/inventory/production.ini"
else
    echo "✅ Ansible inventory file already exists at configuration/inventory/production.ini"
fi


