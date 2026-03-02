# fuse.nix — write /etc/fuse.conf to allow FUSE mounts by non-root users.
# Kernel module loading (modprobe fuse, /etc/modules-load.d/fuse.conf) is
# kernel-level and stays in the Ansible common role.
{ ... }:
{
  environment.etc."fuse.conf" = {
    text = ''
      # /etc/fuse.conf — managed by system-manager (hyphae fuse module)
      # Required for geesefs host-level FUSE mounts.
      user_allow_other
    '';
    mode = "0644";
  };
}
