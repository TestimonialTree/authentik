#!/usr/bin/env bash
# Smoke-test the Dockerfile.custom token.py overlay against a real authentik stack.
#
#   overlay-test/run.sh                                   # production base (2024.8.3)
#   overlay-test/run.sh ghcr.io/goauthentik/server:2025.10.0
#
# Builds Dockerfile.custom on the given base, starts Postgres + Redis + server,
# seeds an OAuth2 provider, and checks the token endpoint's success and failure
# paths. Exits non-zero on any failure. Needs Docker. Uses port 19000.
# Background: TTV2-2478 (prod token endpoint returned 405 for every error and
# never matched a redirect URI because token.py did not fit the 2024.8.3 base).
set -euo pipefail

BASE="${1:-ghcr.io/goauthentik/server:2024.8.3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="ak-overlay-test"
NET="$NAME-net"
PORT=19000
U="http://localhost:$PORT/application/o/token/"
R="https://api.rechat.com/testimonialtree/auth/done"
IMAGE="$NAME:local"

cleanup() { docker rm -f "$NAME-server" "$NAME-pg" "$NAME-redis" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "Base: $BASE"
docker build --platform linux/amd64 -q -f "$ROOT/Dockerfile.custom" --build-arg "AUTHENTIK_BASE=$BASE" -t "$IMAGE" "$ROOT" >/dev/null
docker network create "$NET" >/dev/null
docker run -d --name "$NAME-pg" --network "$NET" -e POSTGRES_PASSWORD=pw -e POSTGRES_USER=authentik -e POSTGRES_DB=authentik postgres:16-alpine >/dev/null
docker run -d --name "$NAME-redis" --network "$NET" redis:7-alpine >/dev/null
docker run -d --name "$NAME-server" --network "$NET" -p "$PORT:9000" --platform linux/amd64 \
  -e AUTHENTIK_SECRET_KEY=overlay-test-secret-key-0123456789abcdef \
  -e AUTHENTIK_POSTGRESQL__HOST="$NAME-pg" -e AUTHENTIK_POSTGRESQL__USER=authentik \
  -e AUTHENTIK_POSTGRESQL__NAME=authentik -e AUTHENTIK_POSTGRESQL__PASSWORD=pw \
  -e AUTHENTIK_REDIS__HOST="$NAME-redis" -e AUTHENTIK_ERROR_REPORTING__ENABLED=false \
  -e AUTHENTIK_DISABLE_UPDATE_CHECK=true "$IMAGE" server >/dev/null

printf "Waiting for server (migrations take a few minutes)"
for _ in $(seq 180); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/-/health/ready/")" = 200 ] && break
  docker ps -q -f "name=$NAME-server" | grep -q . || { echo; docker logs "$NAME-server" | tail -20; exit 1; }
  printf "."; sleep 5
done; echo

docker cp "$ROOT/overlay-test/seed.py" "$NAME-server:/tmp/seed.py"
docker exec "$NAME-server" ak shell -c "exec(open('/tmp/seed.py').read())" 2>&1 | grep -q seeded

fail=0
check() { # name expected_status actual_status [extra condition result]
  if [ "$2" = "$3" ] && [ "${4:-ok}" = ok ]; then echo "PASS  $1 ($3)"; else echo "FAIL  $1 (expected $2, got $3 ${4:-})"; fail=1; fi
}
post() { curl -s -o /tmp/overlay-body -w '%{http_code}' -X POST "$@" "$U"; }
has() { grep -q "\"$1\"" /tmp/overlay-body && echo ok || echo "missing $1"; }

check "bare POST, no client -> invalid_client"  400 "$(post -d grant_type=authorization_code)" "$(has invalid_client)"
check "code exchange, exact redirect URI"       200 "$(post -u overlay-test:s3cret -d grant_type=authorization_code -d code=code-plain --data-urlencode redirect_uri=$R)" "$(has access_token)"
check "code reuse -> invalid_grant"             400 "$(post -u overlay-test:s3cret -d grant_type=authorization_code -d code=code-plain --data-urlencode redirect_uri=$R)" "$(has invalid_grant)"
check "wrong redirect URI -> invalid_client"    400 "$(post -u overlay-test:s3cret -d grant_type=authorization_code -d code=code-wrong-redirect --data-urlencode redirect_uri=https://evil.example/cb)" "$(has invalid_client)"
check "wrong client secret -> invalid_client"   400 "$(post -u overlay-test:nope -d grant_type=authorization_code -d code=code-wrong-secret --data-urlencode redirect_uri=$R)" "$(has invalid_client)"
check "bogus refresh token -> invalid_grant"    400 "$(post -u overlay-test:s3cret -d grant_type=refresh_token -d refresh_token=bogus)" "$(has invalid_grant)"
check "code with offline_access"                200 "$(post -u overlay-test:s3cret -d grant_type=authorization_code -d code=code-offline --data-urlencode redirect_uri=$R)" "$(has refresh_token)"
RT=$(python3 -c "import json;print(json.load(open('/tmp/overlay-body')).get('refresh_token',''))" 2>/dev/null || true)
check "refresh grant"                           200 "$(post -u overlay-test:s3cret -d grant_type=refresh_token -d "refresh_token=$RT")" "$(has access_token)"
cors=$(curl -s -D - -o /dev/null -H "Origin: https://api.rechat.com" -X POST -u overlay-test:s3cret -d grant_type=authorization_code -d code=code-cors --data-urlencode redirect_uri=$R "$U" | tr -d '\r' | grep -i '^access-control-allow-origin: https://api.rechat.com$' >/dev/null && echo ok || echo "no CORS header")
check "CORS allow-origin on success"            ok ok "$cors"
check "password grant, good password"           200 "$(post -d grant_type=password -d client_id=overlay-test -d client_secret=s3cret -d username=overlay-agent -d 'password=AgentPw!2478')"
check "password grant, bad password"            400 "$(post -d grant_type=password -d client_id=overlay-test -d client_secret=s3cret -d username=overlay-agent -d password=wrong)"
tb=$(docker logs "$NAME-server" 2>&1 | grep -c Traceback || true)
check "no server tracebacks"                    0 "$tb"

[ $fail = 0 ] && echo "ALL PASSED on $BASE" || { echo "FAILURES on $BASE"; exit 1; }
