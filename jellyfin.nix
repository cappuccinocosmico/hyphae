{ config, lib, pkgs, ... }:

let
  hyphaeLib = import ./lib.nix { inherit lib pkgs; };
in
{
  # Enable Jellyfin media server
  services.jellyfin = {
    enable = true;
    user = "jellyfin";
    group = "jellyfin";
    dataDir = "/var/lib/jellyfin";
    configDir = "/var/lib/jellyfin/config";
    cacheDir = "/var/lib/jellyfin/cache";
    logDir = "/var/log/jellyfin";
    openFirewall = true;  # Opens port 8096
  };

  # Create necessary directories for Jellyfin and media storage
  systemd.tmpfiles.rules = [
    "d /var/lib/jellyfin 0755 jellyfin jellyfin -"
    "d /var/lib/jellyfin/config 0755 jellyfin jellyfin -"
    "d /var/lib/jellyfin/cache 0755 jellyfin jellyfin -"
    "d /var/log/jellyfin 0755 jellyfin jellyfin -"
    "d /etc/hyphae/mounts/hyphae-shows 0755 root root -"
    "d /etc/hyphae/mounts/hyphae-movies 0755 root root -"
    "d /etc/hyphae/mounts/hyphae-music 0755 root root -"
    "d /var/lib/jellyfin/media 0755 jellyfin jellyfin -"
    "d /var/lib/jellyfin/media/shows 0755 jellyfin jellyfin -"
    "d /var/lib/jellyfin/media/movies 0755 jellyfin jellyfin -"
    "d /var/lib/jellyfin/media/music 0755 jellyfin jellyfin -"
  ];

  # Mount hyphae-shows S3 bucket for TV shows
  fileSystems."/etc/hyphae/mounts/hyphae-shows" = {
    device = "garage:hyphae-shows";
    fsType = "rclone";
    options = hyphaeLib.defaultHyphaeRcloneMountOptions;
    depends = [ "garage.service" ];
  };

  # Mount hyphae-movies S3 bucket for movies
  fileSystems."/etc/hyphae/mounts/hyphae-movies" = {
    device = "garage:hyphae-movies";
    fsType = "rclone";
    options = hyphaeLib.defaultHyphaeRcloneMountOptions;
    depends = [ "garage.service" ];
  };

  # Mount hyphae-music S3 bucket for music
  fileSystems."/etc/hyphae/mounts/hyphae-music" = {
    device = "garage:hyphae-music";
    fsType = "rclone";
    options = hyphaeLib.defaultHyphaeRcloneMountOptions;
    depends = [ "garage.service" ];
  };

  # Configure Jellyfin service dependencies and media access
  systemd.services.jellyfin = {
    after = [
      "garage.service"
      "etc-hyphae-mounts-hyphae\\x2dshows.mount"
      "etc-hyphae-mounts-hyphae\\x2dmovies.mount"
      "etc-hyphae-mounts-hyphae\\x2dmusic.mount"
    ];
    wants = [
      "garage.service"
      "etc-hyphae-mounts-hyphae\\x2dshows.mount"
      "etc-hyphae-mounts-hyphae\\x2dmovies.mount"
      "etc-hyphae-mounts-hyphae\\x2dmusic.mount"
    ];

    # Bind mount the S3 buckets to Jellyfin-accessible paths
    serviceConfig = {
      BindPaths = [
        "/etc/hyphae/mounts/hyphae-shows:/var/lib/jellyfin/media/shows"
        "/etc/hyphae/mounts/hyphae-movies:/var/lib/jellyfin/media/movies"
        "/etc/hyphae/mounts/hyphae-music:/var/lib/jellyfin/media/music"
      ];
    };
  };

}