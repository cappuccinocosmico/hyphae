{ lib, pkgs, ... }:

{
  # Standard S3FS mount options for all Hyphae buckets
  defaultHyphaeMountOptions = [
    "passwd_file=/etc/hyphae/secrets/s3-credentials"
    "url=http://localhost:3900"  # Garage S3 API endpoint
    "endpoint=hyphae"            # Specify the correct region/endpoint
    "use_path_request_style"     # Required for Garage compatibility
    "allow_other"                # Allow other users to access
    "uid=0"                      # Mount as root
    "gid=0"                      # Mount as root group
    "umask=022"                  # Readable by all, writable by owner
    "nonempty"                   # Allow mounting on non-empty directory
    "_netdev"                    # Wait for network
    "sigv4"                      # Use signature version 4 instead of v2
    "no_check_certificate"       # Skip SSL certificate validation for local connections
    "enable_noobj_cache"         # Performance optimization
    "nofail"                     # Don't fail boot if mount fails
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