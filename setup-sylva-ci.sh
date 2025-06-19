#!/usr/bin/env bash

((!DETACHED)) && DETACHED=1 exec setsid --fork "$SHELL" "$0" "$@"

set -eu -o pipefail

: "${ISO_PATH:=/dev/sr0}"

source <(isoinfo -i "$ISO_PATH" -R -x /context.sh)

: "${HYDRA_HOST:=http://$ETH0_IP:3000}"
: "${HYDRA_USER:=oneadmin}"
: "${HYDRA_PASSWORD:=opennebula}"
: "${HYDRA_PROJECT_ID:=sylva-ci}"
: "${HYDRA_FLAKE_URL:=https://github.com/sk4zuzu/sylva-ci.git}"

install -o 0 -g 0 -m u=rw,go=r /dev/fd/0 /etc/nixos/configuration.nix.d/01-hydra.nix <<NIX
{ config, pkgs, lib, ... }: {
  nix.settings = {
    experimental-features = "nix-command flakes";
    sandbox = false;
  };
  nix.buildMachines = [{
    hostName = "localhost";
    protocol = null;
    system = "x86_64-linux";
    supportedFeatures = ["kvm" "nixos-test" "big-parallel" "benchmark"];
    maxJobs = 1;
  }];
  environment.systemPackages = with pkgs; [
    libargon2
  ];
  services.hydra = {
    enable = true;
    hydraURL = "$HYDRA_HOST";
    notificationSender = "hydra@localhost";
    buildMachinesFiles = [];
    useSubstitutes = true;
  };
  networking.hostName = "$SET_HOSTNAME";
}
NIX

install -o 0 -g 0 -m u=rw,go=r /dev/fd/0 /etc/nixos/configuration.nix.d/02-docker.nix <<NIX
{ config, pkgs, lib, ... }: {
  services.dockerRegistry = {
    enable = true;
    enableDelete = true;
    enableGarbageCollect = true;
    garbageCollectDates = "weekly";
    listenAddress = "0.0.0.0";
    port = 5000;
    storagePath = "/var/lib/docker-registry/";
    extraConfig = {
      proxy.remoteurl = "https://registry-1.docker.io";
    };
  };
  systemd.services.docker-registry = {
    environment = { OTEL_TRACES_EXPORTER = "none"; };
    overrideStrategy = "asDropinIfExists";
  };
}
NIX

nixos-rebuild switch

SALT="$(LC_ALL=C tr -dc '[:alnum:]' < /dev/urandom | head -c 16)" || true
HASH="$(tr -d \\n <<< "$HYDRA_PASSWORD" | argon2 "$SALT" -id -t 3 -k 262144 -p 1 -l 16 -e)"

RETRY=60
while ! sudo -u hydra hydra-create-user "$HYDRA_USER" --password-hash "$HASH" --role admin; do
    ((--RETRY))
    sleep 5
done

RETRY=60
while ! curl -fsSL -H 'Accept: application/json' "$HYDRA_HOST/"; do
    ((--RETRY))
    sleep 5
done

read -r -d "#\n" LOGIN_JSON <<JSON
{
  "username": "$HYDRA_USER",
  "password": "$HYDRA_PASSWORD"
}#
JSON

read -r -d "#\n" PROJECT_JSON <<JSON
{
  "displayname": "$HYDRA_PROJECT_ID",
  "enabled": true,
  "hidden": false,
  "declarative": {
    "type": "git",
    "file": "spec.json",
    "value": "$HYDRA_FLAKE_URL"
  }
}#
JSON

curl --fail-early --show-error \
--silent \
-X POST --referer "$HYDRA_HOST" "$HYDRA_HOST/login" \
--cookie-jar ~/hydra-session \
--json "$LOGIN_JSON" \
-: \
--silent \
-X PUT --referer "$HYDRA_HOST/login" "$HYDRA_HOST/project/$HYDRA_PROJECT_ID" \
--cookie ~/hydra-session \
--json "$PROJECT_JSON"

rm -f ~/hydra-session

sync
