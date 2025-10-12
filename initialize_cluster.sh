#!/usr/bin/env bash
set -euo pipefail

# Hyphae Garage Cluster Initialization Script
# This script initializes a Garage cluster and creates the necessary buckets and keys

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARAGE_CMD="garage"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if garage command is available
check_garage_available() {
    if ! command -v garage &> /dev/null; then
        log_error "Garage CLI not found. Make sure Garage is installed and in PATH."
        exit 1
    fi
    log_success "Garage CLI found"
}

# Check garage status and ensure it's running
check_garage_status() {
    log_info "Checking Garage status..."
    if ! garage status &> /dev/null; then
        log_error "Garage service is not running or not accessible."
        log_info "Make sure garage.service is active: systemctl status garage"
        exit 1
    fi
    log_success "Garage service is running"
}

# Get the node ID from garage status
get_node_id() {
    local node_id
    node_id=$(garage status | grep "NO ROLE ASSIGNED" | awk '{print $1}' | head -1)
    if [[ -z "$node_id" ]]; then
        log_error "Could not find node ID or node already has a role assigned"
        garage status
        exit 1
    fi
    echo "$node_id"
}

# Create cluster layout
create_cluster_layout() {
    local node_id="$1"
    local zone="${2:-dc1}"
    local capacity="${3:-10G}"

    log_info "Creating cluster layout for node $node_id..."
    log_info "Zone: $zone, Capacity: $capacity"

    garage layout assign -z "$zone" -c "$capacity" "$node_id"
    log_success "Layout assigned"

    log_info "Applying layout version 1..."
    garage layout apply --version 1
    log_success "Layout applied"
}

# Create hyphae-data bucket
create_hyphae_bucket() {
    local bucket_name="hyphae-data"

    log_info "Creating bucket: $bucket_name"

    # Check if bucket already exists
    if garage bucket list | grep -q "$bucket_name"; then
        log_warning "Bucket $bucket_name already exists"
    else
        garage bucket create "$bucket_name"
        log_success "Bucket $bucket_name created"
    fi

    # Show bucket info
    log_info "Bucket information:"
    garage bucket info "$bucket_name"
}

# Create hyphae API key
create_hyphae_key() {
    local key_name="hyphae-access-key"

    log_info "Creating API key: $key_name"

    # Check if key already exists
    if garage key list | grep -q "$key_name"; then
        log_warning "Key $key_name already exists"
        log_info "Existing key information:"
        garage key info "$key_name"
    else
        log_info "Generating new API key..."
        garage key create "$key_name"
        log_success "Key $key_name created"

        log_warning "IMPORTANT: Save the Key ID and Secret key shown above!"
        log_warning "You will need these for the S3 credentials file."
    fi
}

# Allow key to access bucket
allow_key_bucket_access() {
    local bucket_name="hyphae-data"
    local key_name="hyphae-access-key"

    log_info "Granting permissions to key $key_name for bucket $bucket_name..."

    garage bucket allow \
        --read \
        --write \
        --owner \
        "$bucket_name" \
        --key "$key_name"

    log_success "Permissions granted"

    # Show final bucket info
    log_info "Final bucket information:"
    garage bucket info "$bucket_name"
}

# Update S3 credentials file
update_s3_credentials() {
    local creds_file="/etc/hyphae/secrets/s3-credentials"

    log_info "S3 credentials file location: $creds_file"

    if [[ -f "$creds_file" ]]; then
        log_warning "You need to manually update the S3 credentials file with the actual key information:"
        log_info "1. Get the Key ID and Secret from the key creation output above"
        log_info "2. Edit $creds_file (as root)"
        log_info "3. Replace 'hyphae-access-key:hyphae-secret-key' with 'KEY_ID:SECRET_KEY'"
        log_info "4. Restart any services that use the mount"
    else
        log_error "S3 credentials file not found at $creds_file"
        log_info "This should be created automatically by the NixOS module"
    fi
}

# Main execution
main() {
    log_info "Starting Hyphae Garage cluster initialization..."
    echo

    # Step 1: Check prerequisites
    check_garage_available
    check_garage_status
    echo

    # Step 2: Get node information
    log_info "Getting node information..."
    NODE_ID=$(get_node_id)
    log_success "Found node ID: $NODE_ID"
    echo

    # Step 3: Create cluster layout (if not already assigned)
    if garage status | grep -q "NO ROLE ASSIGNED"; then
        create_cluster_layout "$NODE_ID"
    else
        log_warning "Node already has a role assigned, skipping layout creation"
        garage status
    fi
    echo

    # Step 4: Create bucket
    create_hyphae_bucket
    echo

    # Step 5: Create API key
    create_hyphae_key
    echo

    # Step 6: Grant permissions
    allow_key_bucket_access
    echo

    # Step 7: Instructions for S3 credentials
    update_s3_credentials
    echo

    log_success "Hyphae cluster initialization completed!"
    log_info "Next steps:"
    log_info "1. Update the S3 credentials file as instructed above"
    log_info "2. Test the S3 mount: ls /etc/hyphae/mounts/hyphae-data"
    log_info "3. The bucket is ready for use!"
}

# Run main function
main "$@"