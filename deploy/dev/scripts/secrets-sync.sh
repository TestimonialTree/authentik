#!/usr/bin/env bash
set -euo pipefail

# Sync consolidated JSON secret authentik-dev/app-config from existing per-field secrets

REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=${AWS_ACCOUNT_ID:-}
NEW_SECRET_NAME=${NEW_SECRET_NAME:-authentik-dev/app-config}

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need aws
need jq

get_val(){
  local id=$1
  local keyhint=$2
  if ! out=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$id" 2>/dev/null); then
    echo ""; return 0
  fi
  val=$(printf '%s' "$out" | jq -r '.SecretString')
  if [[ "$val" =~ ^\{ ]]; then
    echo "$val" | jq -r --arg k "$keyhint" '.[$k] // .key // .password // .host // .username // .database // empty'
  else
    printf '%s' "$val"
  fi
}

AK_KEY=$(get_val authentik-dev/secret-key AUTHENTIK_SECRET_KEY)
DB_HOST=$(get_val authentik-dev/rds-host AUTHENTIK_POSTGRESQL__HOST)
DB_USER=$(get_val authentik-dev/rds-user AUTHENTIK_POSTGRESQL__USER)
DB_PASS=$(get_val authentik-dev/rds-password AUTHENTIK_POSTGRESQL__PASSWORD)
DB_NAME=$(get_val authentik-dev/rds-database AUTHENTIK_POSTGRESQL__NAME)

missing=()
[[ -z "$AK_KEY" ]] && missing+=(AUTHENTIK_SECRET_KEY)
[[ -z "$DB_HOST" ]] && missing+=(AUTHENTIK_POSTGRESQL__HOST)
[[ -z "$DB_USER" ]] && missing+=(AUTHENTIK_POSTGRESQL__USER)
[[ -z "$DB_PASS" ]] && missing+=(AUTHENTIK_POSTGRESQL__PASSWORD)
[[ -z "$DB_NAME" ]] && missing+=(AUTHENTIK_POSTGRESQL__NAME)

if (( ${#missing[@]} > 0 )); then
  echo "Missing values for: ${missing[*]}" >&2
  echo "Set them manually or ensure old secrets exist, then re-run." >&2
  exit 1
fi

payload=$(jq -n --arg sk "$AK_KEY" \
              --arg host "$DB_HOST" \
              --arg user "$DB_USER" \
              --arg pass "$DB_PASS" \
              --arg db "$DB_NAME" '{
  AUTHENTIK_SECRET_KEY: $sk,
  AUTHENTIK_POSTGRESQL__HOST: $host,
  AUTHENTIK_POSTGRESQL__USER: $user,
  AUTHENTIK_POSTGRESQL__PASSWORD: $pass,
  AUTHENTIK_POSTGRESQL__NAME: $db
}')

if aws secretsmanager describe-secret --region "$REGION" --secret-id "$NEW_SECRET_NAME" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value --region "$REGION" --secret-id "$NEW_SECRET_NAME" --secret-string "$payload" >/dev/null
  echo "Updated secret $NEW_SECRET_NAME"
else
  aws secretsmanager create-secret --region "$REGION" --name "$NEW_SECRET_NAME" --description "Authentik app config (JSON)" --secret-string "$payload" >/dev/null
  echo "Created secret $NEW_SECRET_NAME"
fi

for s in secret-key rds-host rds-user rds-password rds-database; do
  if aws secretsmanager describe-secret --region "$REGION" --secret-id "authentik-dev/$s" >/dev/null 2>&1; then
    aws secretsmanager tag-resource --region "$REGION" --secret-id "authentik-dev/$s" --tags Key=status,Value=deprecated >/dev/null || true
  fi
done

echo "Done. Update applied to $NEW_SECRET_NAME. Old secrets tagged 'deprecated'."

