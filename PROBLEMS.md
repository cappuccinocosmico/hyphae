So I have some potential problems with the current way things are architected.

1. This is very dependant on the nixos architecture, which makes it very hard to package for a generic linux server. Not only does it need to be running nixos it needs to have a configuration defined with flakes and import this as a flake dependancy.

2. There is also a bit of a weird permissions problem, currently this needs to be run as root in order to do the file system mounts for s3. But the s3 server doesnt run as root, and the jellyfin/kavita interfaces dont run as root either, so it seems somewhat weird that the application fundamentally needs root permissions.

3. The fact that the only way to test this is to update the configuration of a running machine makes it hard and a bit slow to develop.
