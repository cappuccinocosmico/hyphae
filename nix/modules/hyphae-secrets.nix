# hyphae-secrets.nix — decrypt /etc/hyphae/secrets.yaml to /run/secrets/ on boot.
# Age key (/etc/hyphae/age.key) and secrets.yaml are written by the Ansible
# hyphae-secrets role; this service decrypts them before consul and nomad start.
{ pkgs, ... }:
let
  hyphae-secrets-decrypt = pkgs.writeShellApplication {
    name = "hyphae-secrets-decrypt";
    runtimeInputs = with pkgs; [ sops jq ];
    # writeShellApplication adds set -euo pipefail automatically.
    text = ''
      SECRETS_SRC=/etc/hyphae/secrets.yaml
      SECRETS_DIR=/run/secrets

      export SOPS_AGE_KEY_FILE=/etc/hyphae/age.key

      install -d -m 700 -o root -g root "$SECRETS_DIR"

      sops --decrypt --output-type json "$SECRETS_SRC" \
        | jq -r 'to_entries[] | select(.value | type == "string") | "\(.key)\t\(.value)"' \
        | while IFS=$'\t' read -r key value; do
            printf '%s' "$value" > "$SECRETS_DIR/$key"
            chmod 600 "$SECRETS_DIR/$key"
          done

      echo "hyphae-secrets: decrypted secrets to $SECRETS_DIR/"
    '';
  };
in
{
  systemd.services.hyphae-secrets = {
    description = "Decrypt hyphae secrets to /run/secrets";
    before = [ "nomad.service" "consul.service" ];
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${hyphae-secrets-decrypt}/bin/hyphae-secrets-decrypt";
    };
  };
}
