#!/usr/bin/env bash
set -euo pipefail

# Script to generate and encrypt secrets for Hyphae using agenix
# This replaces the manual secret generation in the NixOS modules

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="$SCRIPT_DIR/secrets"

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

# Change to secrets directory
cd "$SECRETS_DIR"

log_info "Generating and encrypting secrets for Hyphae..."

# Generate Garage RPC secret (32 bytes hex)
log_info "Creating garage-rpc-secret.age..."
openssl rand -hex 32 | agenix -e garage-rpc-secret.age

# Generate Garage admin token (32 bytes base64)
log_info "Creating garage-admin-token.age..."
openssl rand -base64 32 | agenix -e garage-admin-token.age

# Generate Garage metrics token (32 bytes base64)
log_info "Creating garage-metrics-token.age..."
openssl rand -base64 32 | agenix -e garage-metrics-token.age

# Generate Kavita JWT token (64 bytes base64)
log_info "Creating kavita-token.age..."
openssl rand -base64 64 | agenix -e kavita-token.age

# For S3 credentials, we'll create placeholder values
# These will be updated after running the garage initialization script
log_info "Creating s3-access-key-id.age (placeholder)..."
echo "hyphae-access-key" | agenix -e s3-access-key-id.age

log_info "Creating s3-secret-key.age (placeholder)..."
echo "hyphae-secret-key" | agenix -e s3-secret-key.age

log_success "All secrets generated and encrypted!"
log_info "Secret files created:"
ls -la *.age

echo
log_info "Next steps:"
log_info "1. Update your NixOS configuration to use agenix secrets"
log_info "2. Run 'sudo nixos-rebuild switch' to apply the changes"
log_info "3. Run the garage initialization script to create real S3 credentials"
log_info "4. Update the S3 secret files with real credentials if needed"