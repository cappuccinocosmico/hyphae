{ lib, pkgs, ... }:

{
  # Standard S3FS mount options for all Hyphae buckets (legacy)
  defaultHyphaeMountOptions = [
    "passwd_file=/etc/hyphae/secrets/s3-credentials"
    "url=http://localhost:3900"  # Garage S3 API endpoint
    "endpoint=hyphae"            # Specify the correct region/endpoint
    "use_path_request_style"     # Required for Garage compatibility
    "allow_other"                # Allow other users to access
    "uid=0"                      # Mount as root
    "gid=0"                      # Mount as root group
    "umask=000"                  # Read/write by all, no execute permissions
    "nonempty"                   # Allow mounting on non-empty directory
    "_netdev"                    # Wait for network
    "sigv4"                      # Use signature version 4 instead of v2
    "no_check_certificate"       # Skip SSL certificate validation for local connections
    "enable_noobj_cache"         # Performance optimization
    "nofail"                     # Don't fail boot if mount fails
  ];

  # Rclone mount options for all Hyphae buckets (optimized for writes)
  defaultHyphaeRcloneMountOptions = [
    "nodev"
    "nofail"
    "allow_other"
    "args2env"
    "config=/etc/hyphae/secrets/rclone.conf"
    "vfs-cache-mode=full"        # Full caching for better write performance
    "vfs-cache-max-size=1G"      # Limit cache size to 1GB
    "vfs-cache-max-age=1h"       # Keep cache for 1 hour
    "vfs-write-back=5s"          # Write back to storage after 5 seconds
    "buffer-size=16M"            # Larger buffer for file operations
    "_netdev"                    # Wait for network
  ];

  # Generate mount options that use sops secrets directly
  hyphaeMountOptionsWithSopsSecrets = config: [
    "passwd_file=${config.environment.etc."hyphae/secrets/s3-credentials".source}"
    "url=http://localhost:3900"
    "use_path_request_style"
    "allow_other"
    "uid=0"
    "gid=0"
    "umask=022"
    "nonempty"
    "_netdev"
    "sigv2"
    "no_check_certificate"
    "enable_noobj_cache"
    "nofail"
  ];
}
