#!/usr/bin/env bash
set -euo pipefail

SSR_SERVICE_NAME="ssr"
SSR_BIN="/usr/local/bin/ssserver"
SSR_CMD="/usr/local/bin/ssr"
SSR_DIR="/etc/ssr"
SSR_CONFIG="$SSR_DIR/config.json"
SSR_ACL="$SSR_DIR/black_list.acl"
SSR_UNIT="/etc/systemd/system/${SSR_SERVICE_NAME}.service"
SSR_METHOD="2022-blake3-aes-128-gcm"
SCRIPT_RAW_URL="https://raw.githubusercontent.com/DarkJimiHole/easyssr/main/install.sh"
CN_LIST_URL="https://raw.githubusercontent.com/Hackl0us/GeoIP2-CN/release/CN-ip-cidr.txt"
COMMON_SERVICE_NAMES=("ss-rust" "shadowsocks-rust" "ssr" "ssserver")
COMMON_CONFIG_DIRS=("/etc/ssr" "/etc/ss-rust" "/etc/shadowsocks-rust")
COMMON_UNIT_DIRS=("/etc/systemd/system" "/lib/systemd/system" "/usr/lib/systemd/system")
SCRIPT_VERSION="v1.1"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="\033[0m"
  C_RED="\033[31m"
  C_GREEN="\033[32m"
  C_YELLOW="\033[33m"
  C_BLUE="\033[34m"
  C_CYAN="\033[36m"
  C_BOLD="\033[1m"
else
  C_RESET=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
  C_BOLD=""
fi

color() {
  local c="$1"
  shift
  printf "%b%s%b" "$c" "$*" "$C_RESET"
}

echo_err() {
  printf "%b%s%b\n" "$C_RED" "$*" "$C_RESET" >&2
}

echo_warn() {
  printf "%b%s%b\n" "$C_YELLOW" "$*" "$C_RESET"
}

echo_ok() {
  printf "%b%s%b\n" "$C_GREEN" "$*" "$C_RESET"
}

center_text() {
  local width="$1"
  local text="$2"
  local len left right

  len=${#text}
  left=$(( (width - len) / 2 ))
  right=$(( width - len - left ))

  if [ "$left" -lt 0 ]; then
    left=0
  fi
  if [ "$right" -lt 0 ]; then
    right=0
  fi

  printf "%*s%s%*s" "$left" "" "$text" "$right" ""
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo_err "Please run as root (sudo)."
    exit 1
  fi
}

self_install() {
  local self target tmp_file
  target="$SSR_CMD"
  self=$(readlink -f "$0" 2>/dev/null || echo "$0")

  if [ "$self" = "$target" ]; then
    return 0
  fi

  if [ -f "$self" ] && [ -r "$self" ]; then
    install -m 0755 "$self" "$target"
    return 0
  fi

  # When executed via `bash <(curl ...)`, $0 usually points to a transient
  # file descriptor path that cannot be copied reliably. In that case, fetch
  # the published script again and install it as the shortcut target.
  if ! ensure_fetch_cmd >/dev/null 2>&1; then
    echo_warn "Unable to install shortcut automatically from stdin execution."
    return 0
  fi

  tmp_file=$(mktemp)
  if download_file "$SCRIPT_RAW_URL" "$tmp_file"; then
    install -m 0755 "$tmp_file" "$target"
    rm -f "$tmp_file"
    return 0
  fi

  rm -f "$tmp_file"
  echo_warn "Failed to install shortcut automatically. You can rerun the script from a local file."
}

detect_pkg_mgr() {
  if have_cmd apt-get; then
    echo "apt"
  elif have_cmd dnf; then
    echo "dnf"
  elif have_cmd yum; then
    echo "yum"
  elif have_cmd apk; then
    echo "apk"
  elif have_cmd pacman; then
    echo "pacman"
  else
    echo ""
  fi
}

install_pkg() {
  local mgr="$1"
  shift

  case "$mgr" in
    apt)
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y "$@"
      ;;
    dnf)
      dnf install -y "$@"
      ;;
    yum)
      yum install -y "$@"
      ;;
    apk)
      apk add --no-cache "$@"
      ;;
    pacman)
      pacman -Sy --noconfirm "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_cmd_pkgmap() {
  local cmd="$1"
  local apt_pkg="$2"
  local dnf_pkg="$3"
  local yum_pkg="$4"
  local apk_pkg="$5"
  local pacman_pkg="$6"

  if have_cmd "$cmd"; then
    return 0
  fi

  local mgr pkg
  mgr=$(detect_pkg_mgr)
  if [ -z "$mgr" ]; then
    echo_err "Missing command: $cmd"
    return 1
  fi

  case "$mgr" in
    apt) pkg="$apt_pkg" ;;
    dnf) pkg="$dnf_pkg" ;;
    yum) pkg="$yum_pkg" ;;
    apk) pkg="$apk_pkg" ;;
    pacman) pkg="$pacman_pkg" ;;
    *) pkg="" ;;
  esac

  if [ -z "$pkg" ]; then
    echo_err "Missing command: $cmd"
    return 1
  fi

  echo "Installing missing command: $cmd"
  install_pkg "$mgr" "$pkg"
  have_cmd "$cmd"
}

ensure_fetch_cmd() {
  if have_cmd curl || have_cmd wget; then
    return 0
  fi

  if ensure_cmd_pkgmap curl curl curl curl curl curl; then
    return 0
  fi

  ensure_cmd_pkgmap wget wget wget wget wget wget
}

fetch_url_stdout() {
  local url="$1"

  if have_cmd curl; then
    curl -fsSL "$url"
    return 0
  fi

  if have_cmd wget; then
    wget -qO- "$url"
    return 0
  fi

  echo_err "Missing command: curl or wget"
  return 1
}

download_file() {
  local url="$1"
  local output="$2"

  if have_cmd curl; then
    curl -fL --progress-bar -o "$output" "$url"
    return 0
  fi

  if have_cmd wget; then
    wget --progress=bar:force -O "$output" "$url"
    return 0
  fi

  echo_err "Missing command: curl or wget"
  return 1
}

ensure_json_tool() {
  if have_cmd python3 || have_cmd jq; then
    return 0
  fi

  if ensure_cmd_pkgmap python3 python3 python3 python3 python3 python; then
    return 0
  fi

  ensure_cmd_pkgmap jq jq jq jq jq jq
}

ensure_port_check_tool() {
  if have_cmd ss || have_cmd lsof; then
    return 0
  fi

  ensure_cmd_pkgmap lsof lsof lsof lsof lsof lsof
}

ensure_install_tools() {
  ensure_cmd_pkgmap tar tar tar tar tar tar || return 1
  ensure_cmd_pkgmap openssl openssl openssl openssl openssl openssl || return 1
  ensure_cmd_pkgmap xz xz-utils xz xz xz xz || return 1
  ensure_fetch_cmd || return 1
  ensure_port_check_tool || return 1
}

get_local_ip() {
  local ip=""

  if have_cmd ip; then
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}') || ip=""
  fi

  if [ -z "$ip" ] && have_cmd hostname; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}') || ip=""
  fi

  if [ -z "$ip" ]; then
    ip="127.0.0.1"
  fi

  echo "$ip"
}

get_user_count() {
  if [ ! -f "$SSR_CONFIG" ]; then
    echo "0"
    return 0
  fi

  ensure_json_tool >/dev/null 2>&1 || {
    echo "0"
    return 0
  }

  if have_cmd python3; then
    python3 - "$SSR_CONFIG" <<'PY'
import json, sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

servers = data.get("servers")
if isinstance(servers, list):
    print(len(servers))
else:
    print(1)
PY
    return 0
  fi

  jq -r 'if (.servers | type?) == "array" then (.servers | length) else 1 end' "$SSR_CONFIG"
}

acl_enabled() {
  [ -f "$SSR_UNIT" ] && grep -q -- "--acl" "$SSR_UNIT"
}

status_line() {
  local state acl_state

  if [ ! -x "$SSR_BIN" ] && [ ! -f "$SSR_UNIT" ] && [ ! -f "$SSR_CONFIG" ]; then
    state=$(color "$C_RED" "not installed")
  elif have_cmd systemctl && systemctl is-active --quiet "$SSR_SERVICE_NAME"; then
    state=$(color "$C_GREEN" "running")
  else
    state=$(color "$C_YELLOW" "installed but not running")
  fi

  if acl_enabled; then
    acl_state=$(color "$C_GREEN" "CN block on")
  else
    acl_state=$(color "$C_YELLOW" "CN block off")
  fi

  echo "$(color "$C_BOLD" "Status:") $state"
  if [ -f "$SSR_CONFIG" ] || [ -f "$SSR_UNIT" ]; then
    echo "$(color "$C_BOLD" "ACL:") $acl_state"
  fi
}

detect_existing_install() {
  local found=1
  local name unit_dir unit_path config_dir

  if [ -x "$SSR_BIN" ]; then
    echo_warn "Detected leftover binary: $SSR_BIN"
    found=0
  fi

  for config_dir in "${COMMON_CONFIG_DIRS[@]}"; do
    if [ -d "$config_dir" ]; then
      echo_warn "Detected leftover config directory: $config_dir"
      found=0
    fi
  done

  for name in "${COMMON_SERVICE_NAMES[@]}"; do
    for unit_dir in "${COMMON_UNIT_DIRS[@]}"; do
      unit_path="${unit_dir}/${name}.service"
      if [ -f "$unit_path" ]; then
        echo_warn "Detected leftover service unit: $unit_path"
        found=0
      fi
    done
  done

  return "$found"
}

is_port_valid() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

is_port_in_use() {
  local port="$1"

  if have_cmd ss; then
    ss -lntu 2>/dev/null | awk -v suffix=":$port" '$4 ~ (suffix "$") || $4 ~ ("\\]" suffix "$") {found = 1} END {exit found ? 0 : 1}'
    return $?
  fi

  if have_cmd lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && return 0
    lsof -nP -iUDP:"$port" >/dev/null 2>&1 && return 0
    return 1
  fi

  return 2
}

is_port_in_config() {
  local port="$1"

  if [ ! -f "$SSR_CONFIG" ]; then
    return 1
  fi

  ensure_json_tool >/dev/null 2>&1 || return 1

  if have_cmd python3; then
    python3 - "$SSR_CONFIG" "$port" <<'PY' >/dev/null 2>&1
import json, sys

path = sys.argv[1]
port = int(sys.argv[2])

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

servers = data.get("servers")
if isinstance(servers, list):
    sys.exit(0 if any(item.get("server_port") == port for item in servers if isinstance(item, dict)) else 1)

sys.exit(0 if data.get("server_port") == port else 1)
PY
    return $?
  fi

  jq -e --argjson port "$port" '
    if (.servers | type?) == "array" then
      any(.servers[]; .server_port == $port)
    else
      .server_port == $port
    end
  ' "$SSR_CONFIG" >/dev/null 2>&1
}

read_port() {
  local prompt="$1"
  local port
  local status

  while true; do
    read -r -p "$prompt" port

    if ! is_port_valid "$port"; then
      echo_err "Port must be 1-65535."
      continue
    fi

    if is_port_in_use "$port"; then
      status=0
    else
      status=$?
    fi
    if [ "$status" -eq 0 ]; then
      echo_err "Port $port is already in use."
      continue
    fi
    if [ "$status" -eq 2 ]; then
      echo_err "Unable to verify port usage. Please install ss or lsof."
      return 1
    fi

    printf "%s\n" "$port"
    return 0
  done
}

generate_password() {
  openssl rand -base64 16
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-no}"
  local answer

  while true; do
    read -r -p "$prompt" answer
    answer="${answer,,}"

    if [ -z "$answer" ]; then
      [ "$default" = "yes" ] && return 0
      return 1
    fi

    case "$answer" in
      y|yes)
        return 0
        ;;
      n|no)
        return 1
        ;;
      *)
        echo_err "Please enter y/yes or n/no."
        ;;
    esac
  done
}

is_base64() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9+/=]+$ ]] || return 1
  printf "%s" "$value" | openssl base64 -d -A >/dev/null 2>&1
}

base64_decoded_len() {
  local value="$1"
  printf "%s" "$value" | openssl base64 -d -A 2>/dev/null | wc -c | tr -d ' '
}

read_password() {
  local prompt="$1"
  local password decoded_len

  while true; do
    read -r -p "$prompt" password

    if [ -z "$password" ]; then
      generate_password
      return 0
    fi

    if ! is_base64 "$password"; then
      echo_err "Password must be valid base64."
      continue
    fi

    decoded_len=$(base64_decoded_len "$password")
    if [ "$decoded_len" -ne 16 ]; then
      echo_err "Password must decode to 16 bytes, for example: openssl rand -base64 16"
      continue
    fi

    printf "%s\n" "$password"
    return 0
  done
}

get_latest_tag() {
  local response tag

  if ! response=$(fetch_url_stdout "https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest"); then
    return 1
  fi
  if have_cmd jq; then
    if ! tag=$(printf "%s\n" "$response" | jq -r '.tag_name // empty'); then
      return 1
    fi
  else
    tag=$(printf "%s\n" "$response" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  fi

  [ -n "$tag" ] || return 1
  printf "%s\n" "$tag"
}

get_release_target() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo "x86_64-unknown-linux-gnu"
      ;;
    aarch64|arm64)
      echo "aarch64-unknown-linux-gnu"
      ;;
    armv7l|armv7)
      echo "armv7-unknown-linux-gnueabihf"
      ;;
    i686|i386)
      echo "i686-unknown-linux-gnu"
      ;;
    *)
      return 1
      ;;
  esac
}

write_config_single() {
  local port="$1"
  local password="$2"

  mkdir -p "$SSR_DIR"
  cat > "$SSR_CONFIG" <<EOF
{
  "server": "::",
  "server_port": $port,
  "password": "$password",
  "method": "$SSR_METHOD",
  "fast_open": true,
  "mode": "tcp_and_udp",
  "timeout": 300,
  "no_delay": true
}
EOF
}

write_service_unit() {
  local enable_acl="$1"
  local exec_start

  exec_start="$SSR_BIN -c $SSR_CONFIG"
  if [ "$enable_acl" = "yes" ]; then
    exec_start="$exec_start --acl $SSR_ACL"
  fi

  mkdir -p "$(dirname "$SSR_UNIT")"
  cat > "$SSR_UNIT" <<EOF
[Unit]
Description=Shadowsocks-Rust Server
After=network.target

[Service]
ExecStart=$exec_start
Restart=on-failure
User=root
LimitNOFILE=51200

[Install]
WantedBy=multi-user.target
EOF
}

build_acl_file() {
  local tmp_file
  tmp_file=$(mktemp)

  if ! {
    echo "[accept_all]"
    echo
    echo "[black_list]"
    fetch_url_stdout "$CN_LIST_URL" | sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d'
  } > "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi

  mkdir -p "$SSR_DIR"
  mv "$tmp_file" "$SSR_ACL"
}

restart_service() {
  if ! have_cmd systemctl; then
    echo_warn "systemctl not found; service was not restarted."
    return 0
  fi

  systemctl daemon-reload
  systemctl enable "$SSR_SERVICE_NAME" >/dev/null 2>&1 || true
  systemctl restart "$SSR_SERVICE_NAME"
}

show_config_table() {
  if [ ! -f "$SSR_CONFIG" ]; then
    echo_err "Config not found: $SSR_CONFIG"
    return 1
  fi

  ensure_json_tool || {
    echo_err "Need python3 or jq to view config."
    return 1
  }

  local local_ip
  local_ip=$(get_local_ip)

  printf "%-8s %-15s %-8s %-28s %-28s\n" "User" "IP" "Port" "Password" "Method"
  printf "%-8s %-15s %-8s %-28s %-28s\n" "----" "---------------" "--------" "----------------------------" "----------------------------"

  if have_cmd python3; then
    python3 - "$SSR_CONFIG" "$local_ip" <<'PY'
import json, sys

path = sys.argv[1]
local_ip = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

def normalize_ip(value):
    return local_ip if value in ("::", "0.0.0.0", "") else value

servers = data.get("servers")
if not isinstance(servers, list):
    servers = [data]

for index, server in enumerate(servers, 1):
    print(f"{index:<8} {normalize_ip(server.get('server', '')):<15} {str(server.get('server_port', '')):<8} {server.get('password', ''):<28} {server.get('method', ''):<28}")
PY
    return 0
  fi

  jq -r --arg local_ip "$local_ip" '
    def ipfix(value):
      if value == "::" or value == "0.0.0.0" or value == "" then $local_ip else value end;

    if (.servers | type?) == "array" then
      .servers | to_entries[] | [(.key + 1), ipfix(.value.server), .value.server_port, .value.password, .value.method] | @tsv
    else
      [1, ipfix(.server), .server_port, .password, .method] | @tsv
    end
  ' "$SSR_CONFIG" | awk -F '\t' '{printf "%-8s %-15s %-8s %-28s %-28s\n", $1, $2, $3, $4, $5}'
}

get_user_fields() {
  local idx="$1"
  local local_ip
  local_ip=$(get_local_ip)

  if [ ! -f "$SSR_CONFIG" ]; then
    return 1
  fi

  ensure_json_tool >/dev/null 2>&1 || return 1

  if have_cmd python3; then
    python3 - "$SSR_CONFIG" "$idx" "$local_ip" <<'PY'
import json, sys

path = sys.argv[1]
idx = int(sys.argv[2])
local_ip = sys.argv[3]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

servers = data.get("servers")
if not isinstance(servers, list):
    servers = [data]

server = servers[idx - 1]
ip = server.get("server", "")
if ip in ("::", "0.0.0.0", ""):
    ip = local_ip

print(ip)
print(server.get("server_port", ""))
print(server.get("password", ""))
print(server.get("method", ""))
PY
    return 0
  fi

  jq -r --argjson idx "$idx" --arg local_ip "$local_ip" '
    def ipfix(value):
      if value == "::" or value == "0.0.0.0" or value == "" then $local_ip else value end;

    if (.servers | type?) == "array" then
      .servers[$idx - 1]
    else
      .
    end
    | ipfix(.server), .server_port, .password, .method
  ' "$SSR_CONFIG"
}

install_ssr() {
  if detect_existing_install; then
    echo_warn "Existing ss-rust related files were detected. Please uninstall first to avoid overwriting."
    return 1
  fi

  ensure_install_tools || return 1

  local tag target archive url tmp_dir tmp_archive port password

  tag=$(get_latest_tag) || {
    echo_err "Failed to get the latest release tag."
    return 1
  }

  target=$(get_release_target) || {
    echo_err "Unsupported architecture: $(uname -m)"
    return 1
  }

  archive="shadowsocks-${tag}.${target}.tar.xz"
  url="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${tag}/${archive}"
  tmp_dir=$(mktemp -d)
  tmp_archive="${tmp_dir}/${archive}"

  echo "Downloading $archive"
  if ! download_file "$url" "$tmp_archive"; then
    rm -rf "$tmp_dir"
    echo_err "Failed to download release archive."
    return 1
  fi

  if [ ! -s "$tmp_archive" ]; then
    echo_err "Download failed or empty file: $tmp_archive"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! tar -xf "$tmp_archive" -C "$tmp_dir"; then
    rm -rf "$tmp_dir"
    echo_err "Failed to extract release archive."
    return 1
  fi
  if [ ! -f "${tmp_dir}/ssserver" ]; then
    echo_err "ssserver was not found in the release archive."
    rm -rf "$tmp_dir"
    return 1
  fi

  port=$(read_port "Enter server port: ") || {
    rm -rf "$tmp_dir"
    return 1
  }
  password=$(read_password "Enter password (base64, empty to generate): ")

  install -m 0755 "${tmp_dir}/ssserver" "$SSR_BIN"
  write_config_single "$port" "$password"

  if prompt_yes_no "Enable block CN (y/N)? " "no"; then
    build_acl_file
    write_service_unit "yes"
  else
    rm -f "$SSR_ACL"
    write_service_unit "no"
  fi

  rm -rf "$tmp_dir"
  restart_service

  echo_ok "Installed successfully."
  echo ""
  show_config_table || true
}

uninstall_ssr() {
  local name unit_dir config_dir

  if have_cmd systemctl; then
    for name in "${COMMON_SERVICE_NAMES[@]}"; do
      systemctl stop "$name" >/dev/null 2>&1 || true
      systemctl disable "$name" >/dev/null 2>&1 || true
      systemctl reset-failed "$name" >/dev/null 2>&1 || true
    done
  fi

  for name in "${COMMON_SERVICE_NAMES[@]}"; do
    for unit_dir in "${COMMON_UNIT_DIRS[@]}"; do
      rm -f "${unit_dir}/${name}.service"
    done
  done

  rm -f "$SSR_BIN"
  for config_dir in "${COMMON_CONFIG_DIRS[@]}"; do
    rm -rf "$config_dir"
  done

  if have_cmd systemctl; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  echo_ok "ss-rust and related files were removed."
}

add_user() {
  if [ ! -f "$SSR_CONFIG" ]; then
    echo_err "Config not found: $SSR_CONFIG"
    return 1
  fi

  ensure_cmd_pkgmap openssl openssl openssl openssl openssl openssl || return 1
  ensure_json_tool || {
    echo_err "Need python3 or jq to update config."
    return 1
  }
  ensure_port_check_tool || return 1

  local port password tmp_file

  while true; do
    port=$(read_port "Enter new user port: ") || return 1
    if is_port_in_config "$port"; then
      echo_err "Port $port already exists in the config."
      continue
    fi
    break
  done

  password=$(read_password "Enter new password (base64, empty to generate): ")
  tmp_file=$(mktemp)

  if have_cmd python3; then
    python3 - "$SSR_CONFIG" "$port" "$password" "$SSR_METHOD" > "$tmp_file" <<'PY'
import json, sys

path = sys.argv[1]
port = int(sys.argv[2])
password = sys.argv[3]
method = sys.argv[4]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

new_server = {
    "server": "::",
    "server_port": port,
    "password": password,
    "method": method,
    "fast_open": True,
    "mode": "tcp_and_udp",
    "timeout": 300,
    "no_delay": True,
}

servers = data.get("servers")
if isinstance(servers, list):
    servers.append(new_server)
    output = data
else:
    output = {"servers": [data, new_server]}

json.dump(output, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
  else
    jq --argjson port "$port" --arg password "$password" --arg method "$SSR_METHOD" '
      if (.servers | type?) == "array" then
        .servers += [{
          server: "::",
          server_port: $port,
          password: $password,
          method: $method,
          fast_open: true,
          mode: "tcp_and_udp",
          timeout: 300,
          no_delay: true
        }]
      else
        {
          servers: [
            .,
            {
              server: "::",
              server_port: $port,
              password: $password,
              method: $method,
              fast_open: true,
              mode: "tcp_and_udp",
              timeout: 300,
              no_delay: true
            }
          ]
        }
      end
    ' "$SSR_CONFIG" > "$tmp_file"
  fi

  mv "$tmp_file" "$SSR_CONFIG"
  restart_service

  echo_ok "User added."
  show_config_table || true
}

delete_user() {
  if [ ! -f "$SSR_CONFIG" ]; then
    echo_err "Config not found: $SSR_CONFIG"
    return 1
  fi

  ensure_json_tool || {
    echo_err "Need python3 or jq to update config."
    return 1
  }

  local count idx tmp_file

  count=$(get_user_count)
  if [ "$count" -le 1 ]; then
    echo_err "Cannot delete the only user."
    return 1
  fi

  echo ""
  echo "Current users:"
  show_config_table || true
  read -r -p "Enter user index to delete (1..$count): " idx

  if [[ ! "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "$count" ]; then
    echo_err "Invalid user index."
    return 1
  fi

  tmp_file=$(mktemp)
  if have_cmd python3; then
    python3 - "$SSR_CONFIG" "$idx" > "$tmp_file" <<'PY'
import json, sys

path = sys.argv[1]
idx = int(sys.argv[2]) - 1

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

servers = data.get("servers")
if not isinstance(servers, list):
    raise SystemExit(1)

servers.pop(idx)
output = servers[0] if len(servers) == 1 else data

json.dump(output, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
  else
    jq --argjson idx "$idx" '
      .servers |= (to_entries | map(select(.key != ($idx - 1))) | map(.value))
      | if (.servers | length) == 1 then .servers[0] else . end
    ' "$SSR_CONFIG" > "$tmp_file"
  fi

  mv "$tmp_file" "$SSR_CONFIG"
  restart_service

  echo_ok "User deleted."
  show_config_table || true
}

view_config() {
  if [ ! -f "$SSR_CONFIG" ]; then
    echo_err "Config not found: $SSR_CONFIG"
    return 1
  fi

  local count idx ip port password method encoded_credentials node_name ss_link

  ensure_cmd_pkgmap openssl openssl openssl openssl openssl openssl || return 1

  echo ""
  show_config_table || return 1
  count=$(get_user_count)
  read -r -p "Enter user index to generate share link (Enter to return): " idx

  if [ -z "${idx:-}" ]; then
    return 0
  fi

  if [[ ! "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "$count" ]; then
    echo_err "Invalid user index."
    return 1
  fi

  mapfile -t user_fields < <(get_user_fields "$idx")
  ip="${user_fields[0]:-}"
  port="${user_fields[1]:-}"
  password="${user_fields[2]:-}"
  method="${user_fields[3]:-}"

  if [ -z "$ip" ] || [ -z "$port" ] || [ -z "$password" ] || [ -z "$method" ]; then
    echo_err "Failed to read user configuration."
    return 1
  fi

  encoded_credentials=$(printf "%s" "${method}:${password}" | openssl base64 -A)
  node_name="User-${idx}-ss2022"
  ss_link="ss://${encoded_credentials}@${ip}:${port}#${node_name}"

  echo ""
  echo "$(color "$C_GREEN" "Share link:") ${ss_link}"
  read -r -p "Press Enter to return to menu..." _
}

uninstall_script() {
  local self

  if detect_existing_install; then
    echo_warn "ss-rust is still installed. Please uninstall ss-rust first."
    return 1
  fi

  self=$(readlink -f "$0" 2>/dev/null || echo "$0")
  if [ -f "$SSR_CMD" ]; then
    rm -f "$SSR_CMD"
    echo_ok "Shortcut script removed: $SSR_CMD"
  elif [ "$self" = "$SSR_CMD" ]; then
    rm -f "$SSR_CMD"
    echo_ok "Shortcut script removed: $SSR_CMD"
  else
    echo_warn "Shortcut script not found: $SSR_CMD"
  fi
}

toggle_acl() {
  if [ ! -f "$SSR_CONFIG" ]; then
    echo_err "Config not found: $SSR_CONFIG"
    return 1
  fi

  ensure_fetch_cmd || return 1

  if prompt_yes_no "Enable block CN (y/N)? " "no"; then
    build_acl_file
    write_service_unit "yes"
  else
    rm -f "$SSR_ACL"
    write_service_unit "no"
  fi

  restart_service
  echo_ok "ACL updated."
}

print_menu() {
  echo ""
  echo "$(color "$C_CYAN" "1.") Install ss-rust"
  echo "$(color "$C_CYAN" "2.") Uninstall ss-rust"
  echo "$(color "$C_CYAN" "3.") Add user"
  echo "$(color "$C_CYAN" "4.") View ss-rust config"
  echo "$(color "$C_CYAN" "5.") Enable/Disable CN block"
  echo "$(color "$C_CYAN" "6.") Delete user"
  echo "$(color "$C_CYAN" "7.") Uninstall this script"
  echo "$(color "$C_CYAN" "0.") Exit"
}

print_header() {
  local width=50
  local divider left_text right_label right_value padding
  divider=$(printf '%*s' "$width" '' | tr ' ' '-')
  left_text="shadowsocks-rust script ${SCRIPT_VERSION}"
  right_label="Shortcut: "
  right_value="ssr"
  padding=$(( width - ${#left_text} - ${#right_label} - ${#right_value} ))
  if [ "$padding" -lt 1 ]; then
    padding=1
  fi
  echo ""
  echo "$(color "$C_CYAN" "  ______                _____ _____  _____")"
  echo "$(color "$C_CYAN" " |  ____|              / ____/ ____|/ ____|")"
  echo "$(color "$C_CYAN" " | |__   __ _ ___ _   _| (___| (___ | |__) |")"
  echo "$(color "$C_CYAN" " |  __| / _\` / __| | | |\\___ \\\\___ \\|  _  /")"
  echo "$(color "$C_CYAN" " | |___| (_| \\__ \\ |_| |____) |___) || | \\ \\")"
  echo "$(color "$C_CYAN" " |______\\__,_|___/\\__, |_____/_____/ |_|  \\_\\")"
  echo "$(color "$C_CYAN" "                   __/ |")"
  echo "$(color "$C_CYAN" "                  |___/")"
  echo ""
  echo "$(color "$C_BLUE" "$divider")"
  printf "%b%s%b%*s%b%s%b%b%s%b\n" \
    "$C_BLUE" "$left_text" "$C_RESET" \
    "$padding" "" \
    "$C_BLUE" "$right_label" "$C_RESET" \
    "$C_RED" "$right_value" "$C_RESET"
  echo "$(color "$C_BLUE" "$divider")"
}

run_menu_action() {
  if "$@"; then
    return 0
  fi

  echo ""
  read -r -p "Press Enter to return to menu..." _
  return 0
}

main() {
  require_root
  self_install

  while true; do
    print_header
    status_line
    echo ""
    printf "[%s]\n" "$(color "$C_GREEN" "MENU")"
    print_menu
    read -r -p "Select: " choice

    case "$choice" in
      1) run_menu_action install_ssr ;;
      2) run_menu_action uninstall_ssr ;;
      3) run_menu_action add_user ;;
      4) run_menu_action view_config ;;
      5) run_menu_action toggle_acl ;;
      6) run_menu_action delete_user ;;
      7)
        if uninstall_script; then
          exit 0
        fi
        echo ""
        read -r -p "Press Enter to return to menu..." _
        ;;
      0) exit 0 ;;
      *) echo "Invalid choice" ;;
    esac
  done
}

main
