#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY="${N2A_REPOSITORY:-Twddhcm/Notion2API}"
RELEASE="${N2A_RELEASE:-v1.0.8-neutral.2}"
INSTALL_DIR="${N2A_INSTALL_DIR:-/opt/notion2api}"
PORT="${N2A_PORT:-8787}"
TIMEZONE="${TZ:-Asia/Shanghai}"
CONTAINER_NAME="${N2A_CONTAINER_NAME:-notion2api}"

log() {
  printf '[Notion2API] %s\n' "$*"
}

fail() {
  printf '[Notion2API] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR:-}" && "$TEMP_DIR" == /tmp/notion2api-install.* ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}

trap cleanup EXIT

[[ "${EUID}" -eq 0 ]] || fail "Run this installer as root: curl ... | sudo bash"
[[ -r /etc/os-release ]] || fail "Cannot identify the operating system."

# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "debian" ]] || fail "This installer supports Debian only."
[[ "${VERSION_ID:-}" == "13"* ]] || fail "Debian 13 is required; found ${VERSION_ID:-unknown}."
[[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != "/" ]] || fail "N2A_INSTALL_DIR must be an absolute non-root path."
[[ "$PORT" =~ ^[0-9]+$ ]] || fail "N2A_PORT must be numeric."
(( PORT >= 1 && PORT <= 65535 )) || fail "N2A_PORT must be between 1 and 65535."
[[ "$CONTAINER_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fail "N2A_CONTAINER_NAME is invalid."
[[ ! -e "$INSTALL_DIR" ]] || fail "$INSTALL_DIR already exists; this installer will not overwrite it."

export DEBIAN_FRONTEND=noninteractive

log "Installing base packages..."
apt-get update
apt-get install -y ca-certificates curl jq

if ! docker compose version >/dev/null 2>&1; then
  if command -v docker >/dev/null 2>&1; then
    log "Docker exists but the Compose plugin is missing."
    apt-get install -y docker-compose-plugin || fail "Install a Docker Compose v2 plugin, then rerun this installer."
  else
    log "Installing Docker Engine from Docker's official Debian repository..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    printf '%s\n' \
      'Types: deb' \
      'URIs: https://download.docker.com/linux/debian' \
      "Suites: ${VERSION_CODENAME:-trixie}" \
      'Components: stable' \
      "Architectures: $(dpkg --print-architecture)" \
      'Signed-By: /etc/apt/keyrings/docker.asc' \
      > /etc/apt/sources.list.d/docker.sources

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
fi

systemctl enable --now docker
docker compose version >/dev/null 2>&1 || fail "Docker Compose is unavailable."

TEMP_DIR="$(mktemp -d /tmp/notion2api-install.XXXXXX)"
ARCHIVE="$TEMP_DIR/source.tar.gz"
SOURCE_DIR="$TEMP_DIR/source"
DOWNLOAD_URL="https://github.com/${REPOSITORY}/archive/refs/tags/${RELEASE}.tar.gz"

log "Downloading ${REPOSITORY} ${RELEASE}..."
curl -fL --retry 3 --connect-timeout 15 "$DOWNLOAD_URL" -o "$ARCHIVE"
mkdir -p "$SOURCE_DIR"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIR" --strip-components=1

[[ -f "$SOURCE_DIR/docker-compose.yml" ]] || fail "Release archive does not contain docker-compose.yml."
[[ -f "$SOURCE_DIR/config.docker.json" ]] || fail "Release archive does not contain config.docker.json."

install -d -m 0755 "$(dirname "$INSTALL_DIR")"
mv "$SOURCE_DIR" "$INSTALL_DIR"
install -d -m 0700 "$INSTALL_DIR/config"
install -d -m 0755 "$INSTALL_DIR/data"

if ! grep -qxF '/config/' "$INSTALL_DIR/.dockerignore"; then
  printf '\n/config/\n' >> "$INSTALL_DIR/.dockerignore"
fi

API_KEY="n2a_$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
ADMIN_PASSWORD="$(od -An -N18 -tx1 /dev/urandom | tr -d ' \n')"
CONFIG_TMP="$INSTALL_DIR/config/config.json.tmp"

jq \
  --arg api_key "$API_KEY" \
  --arg admin_password "$ADMIN_PASSWORD" \
  '.api_key = $api_key
   | .host = "0.0.0.0"
   | .port = 8787
   | .admin.enabled = true
   | .admin.password = $admin_password' \
  "$INSTALL_DIR/config.docker.json" > "$CONFIG_TMP"

mv "$CONFIG_TMP" "$INSTALL_DIR/config/config.json"
chmod 600 "$INSTALL_DIR/config/config.json"

printf 'N2A_PORT=%s\nN2A_CONTAINER_NAME=%s\nTZ=%s\n' \
  "$PORT" "$CONTAINER_NAME" "$TIMEZONE" > "$INSTALL_DIR/.env"
chmod 600 "$INSTALL_DIR/.env"

{
  printf 'Admin URL: http://SERVER_IP:%s/admin\n' "$PORT"
  printf 'API base URL: http://SERVER_IP:%s/v1\n' "$PORT"
  printf 'API key: %s\n' "$API_KEY"
  printf 'Admin password: %s\n' "$ADMIN_PASSWORD"
} > "$INSTALL_DIR/config/install-credentials.txt"
chmod 600 "$INSTALL_DIR/config/install-credentials.txt"

log "Building and starting the service..."
cd "$INSTALL_DIR"
docker compose up -d --build

HEALTHY=0
for _ in $(seq 1 90); do
  if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  sleep 2
done

if (( HEALTHY == 0 )); then
  docker compose logs --tail=100 notion2api || true
  fail "The service did not become healthy within 180 seconds."
fi

SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
SERVER_IP="${SERVER_IP:-SERVER_IP}"

printf '\nNotion2API installation completed.\n'
printf 'Admin URL:     http://%s:%s/admin\n' "$SERVER_IP" "$PORT"
printf 'API base URL:  http://%s:%s/v1\n' "$SERVER_IP" "$PORT"
printf 'API key:       %s\n' "$API_KEY"
printf 'Admin password: %s\n' "$ADMIN_PASSWORD"
printf 'Credentials:   %s/config/install-credentials.txt\n' "$INSTALL_DIR"
printf '\nOpen the admin page and import a Notion account before testing a model.\n'
