{ lib, pkgs, ... }:

{
  # Standard S3FS mount options for all Hyphae buckets
  defaultHyphaeMountOptions = [
    "passwd_file=/etc/hyphae/secrets/s3-credentials"
    "url=http://localhost:3900"  # Garage S3 API endpoint
    "use_path_request_style"     # Required for Garage compatibility
    "allow_other"                # Allow other users to access
    "uid=0"                      # Mount as root
    "gid=0"                      # Mount as root group
    "umask=022"                  # Readable by all, writable by owner
    "nonempty"                   # Allow mounting on non-empty directory
    "_netdev"                    # Wait for network
    "sigv2"                      # Use signature version 2 for Garage compatibility
    "no_check_certificate"       # Skip SSL certificate validation for local connections
    "enable_noobj_cache"         # Performance optimization
    "nofail"                     # Don't fail boot if mount fails
  ];
}