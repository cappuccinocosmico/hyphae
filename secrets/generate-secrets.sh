#!/usr/bin/env bash
set -euo pipefail

# Script to generate secrets for Hyphae using the same methods as before
# These will be encrypted with sops-nix

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

cd "$SCRIPT_DIR"

log_info "Generating secrets for Hyphae (to be encrypted with sops)..."

# Create secrets YAML file with all secrets
cat > secrets.yaml << EOF
# Garage secrets
garage-rpc-secret: "$(openssl rand -hex 32)"
garage-admin-token: "$(openssl rand -base64 32)"
garage-metrics-token: "$(openssl rand -base64 32)"

# Kavita JWT token
kavita-token-key: "$(openssl rand -base64 64)"

# S3 credentials (placeholders to be updated after cluster initialization)
s3-access-key-id: "hyphae-access-key"
s3-secret-key: "hyphae-secret-key"
EOF

log_success "Generated secrets.yaml with placeholder values"
log_info "Now encrypting with sops..."

# Encrypt the file with sops
sops --encrypt --in-place secrets.yaml

log_success "Secrets encrypted successfully!"
log_info "File: secrets.yaml"

echo
log_info "Next steps:"
log_info "1. Commit secrets.yaml to the repo (it is encrypted)"
log_info "2. Run 'ansible-playbook bootstrap.yml' to deploy hyphae-secrets to each node"
log_info "3. After Garage is running, update s3-access-key-id and s3-secret-key with real values"