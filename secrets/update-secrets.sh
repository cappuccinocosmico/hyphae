#!/usr/bin/env bash
set -euo pipefail

# Script to update encrypted secrets for Hyphae using sops
# This allows you to regenerate secrets or update S3 credentials

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/secrets.yaml"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

usage() {
    echo "Usage: $0 [regenerate|update-s3]"
    echo "  regenerate  - Regenerate all secrets (garage tokens, kavita token)"
    echo "  update-s3   - Update S3 credentials with new values"
    echo "  edit        - Edit secrets file directly with sops"
    exit 1
}

case "${1:-}" in
    "regenerate")
        log_info "Regenerating all secrets..."
        log_warning "This will replace ALL secrets with new values!"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Create new secrets file with regenerated values
            cat > /tmp/new-secrets.yaml << EOF
# Garage secrets
garage-rpc-secret: "$(openssl rand -hex 32)"
garage-admin-token: "$(openssl rand -base64 32)"
garage-metrics-token: "$(openssl rand -base64 32)"

# Kavita JWT token
kavita-token: "$(openssl rand -base64 64)"

# S3 credentials (keep existing or use placeholders)
s3-access-key-id: "hyphae-access-key"
s3-secret-key: "hyphae-secret-key"
EOF
            nix-shell -p sops --run "sops --encrypt /tmp/new-secrets.yaml > $SECRETS_FILE"
            rm /tmp/new-secrets.yaml
            log_success "All secrets regenerated and encrypted!"
        else
            log_info "Operation cancelled"
        fi
        ;;
    "update-s3")
        log_info "Updating S3 credentials..."
        echo "Enter the new S3 access key ID:"
        read -r access_key
        echo "Enter the new S3 secret key:"
        read -rs secret_key
        echo

        # Decrypt, update S3 credentials, and re-encrypt
        nix-shell -p sops yq --run "
            sops --decrypt $SECRETS_FILE |
            yq eval '.s3-access-key-id = \"$access_key\"' - |
            yq eval '.s3-secret-key = \"$secret_key\"' - |
            sops --encrypt /dev/stdin > $SECRETS_FILE.new &&
            mv $SECRETS_FILE.new $SECRETS_FILE
        "
        log_success "S3 credentials updated!"
        ;;
    "edit")
        log_info "Opening secrets file for editing with sops..."
        nix-shell -p sops --run "sops $SECRETS_FILE"
        ;;
    *)
        usage
        ;;
esac

echo
log_info "After updating secrets, run 'sudo nixos-rebuild switch' to apply changes"