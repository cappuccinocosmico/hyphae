# disk-config.nix — disko partition layout for vps1 (IONOS VPS).
#
# Hybrid GPT layout: 1 MiB BIOS-boot partition so GRUB works on both legacy
# BIOS and UEFI firmware.  The actual disk device is overridden at deploy time
# via nixos-anywhere --disk-encryption-keys / --extra-files, or by setting
# disko.devices.disk.main.device in a host-specific override.
#
# Check the actual device name on the VPS with `lsblk` before deploying.
# IONOS VPS typically use /dev/sda or /dev/vda.
{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda"; # override if VPS uses /dev/vda
        content = {
          type = "gpt";
          partitions = {
            # 1 MiB unformatted BIOS-boot partition (EF02) so GRUB can embed
            # its second-stage loader on legacy-BIOS firmware.
            bios-boot = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            # 512 MiB EFI System Partition for UEFI firmware.
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            # Root: rest of disk, ext4.
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
