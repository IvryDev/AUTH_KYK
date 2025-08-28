#!/usr/bin/env bash
set -euo pipefail
REALM_NAME=${1:-master}
DIR=/opt/keycloak/data/export

mkdir -p "$DIR"
/opt/keycloak/bin/kc.sh export \
  --realm="$REALM_NAME" \
  --dir="$DIR" \
  --users same_file

echo "Export du realm '$REALM_NAME' terminé dans $DIR"