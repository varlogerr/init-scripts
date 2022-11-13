#!/usr/bin/env bash

THE_DIR="$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
TPL_DIR="${THE_DIR}/.init-scripts/vpn-server"

USER_ID="${SUDO_UID:-$(id -u)}"
USER_NAME="$(id -nu "${USER_ID}")"
USER_GROUP="$(id -ng "${USER_ID}")"
HOME_DIR="$(eval echo ~${USER_NAME})"
BIN_PATH="${HOME_DIR}/bin"

INITOS_PATH="${BIN_PATH}/initos.sh"

OVPN_DL_URL=https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh
OVPN_INSTALL_PATH="${BIN_PATH}/openvpn-install.sh"

WG_DL_URL=https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh
WG_INSTALL_PATH="${BIN_PATH}/wireguard-install.sh"

KEYRING_DIR=/etc/apt/keyrings

DOCKER_DIR="${HOME_DIR}/docker"
DOCKER_DDNS_DIR="${DOCKER_DIR}/ddns"

trap_help() {
  [[ "${1}" =~ ^(-\?|-h|--help)$ ]] || return 1

  echo "
    Configure VPN server. Must be run from root.

    After the script is done:
    * configure and run ${INITOS_PATH} script
    * configure .env file and run \`docker compose up -d\` in
      ${DOCKER_DDNS_DIR} directory
    * install openvpn or configure clients with
      ${OVPN_INSTALL_PATH} script
    * install wireguard or configure clients with
      ${WG_INSTALL_PATH} script
  " | sed -e '1d' -e '$d' | cut -c5-

  return 0
}

mkowndir() {
  (
    set -x
    mkdir -p "${1}" \
    && chown ${USER_NAME}:${USER_GROUP} "${1}"
  )
}

print_stderr() {
  echo "${@}" >&2
}

print_info() {
  print_stderr "[info] ${@}"
}

print_err() {
  print_stderr "[err] ${@}"
}

fail_noroot() {
  [[ "$(id -u)" -eq 0 ]] && return

  print_err "Root required"
  return 1
}

install_base_tools() {
  (
    set -x
    apt-get update \
    && apt-get install -y \
      curl \
      htop \
      tmux \
      vim
  )

  cp "${TPL_DIR}/tmux.conf" "${HOME_DIR}/.tmux.conf"

  (set -x; chown ${USER_NAME}:${USER_GROUP} "${HOME_DIR}/.tmux.conf")
}

install_docker() {
  local gpg_path="${KEYRING_DIR}/docker.gpg"

  (
    set -x

    # uninstall old versions
    apt-get remove -y docker docker-engine docker.io containerd runc

    # install prereqs
    apt-get update
    apt-get install -y \
      ca-certificates \
      curl \
      gnupg \
      lsb-release

    # setup repo
    [[ -f "${gpg_path}" ]] || {
      mkdir -p "$(dirname "${gpg_path}")"
      curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o "${gpg_path}"
    }
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=${gpg_path}] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    # install docker
    apt-get update \
    && apt-get install -y \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-compose-plugin
  )

  if [[ " $(id -nG "${USER_NAME}") " == *" docker "* ]]; then
    print_info "${USER_NAME} is already in docker group"
  else
    (
      set -x
      usermod -aG docker "${USER_NAME}"
    )
  fi
}

dl_initos() {
  [[ -f "${INITOS_PATH}" ]] && {
    print_info "${INITOS_PATH} is already installed, skipping"
    return
  }

  mkowndir "$(dirname "${INITOS_PATH}")"

  (
    set -x

    apt-get update
    apt-get install -y curl
    curl -L -o "${INITOS_PATH}" https://tinyurl.com/initos-sh \
    && chmod 0755 "${INITOS_PATH}" \
    && chown ${USER_NAME}:${USER_GROUP} "${INITOS_PATH}"
  )
}

dl_ovpn_install() {
  mkowndir "$(dirname "${OVPN_INSTALL_PATH}")"

  (
    set -x
    curl -L -o "${OVPN_INSTALL_PATH}" "${OVPN_DL_URL}" \
    && chmod +x "${OVPN_INSTALL_PATH}" \
    && chown ${USER_NAME}:${USER_GROUP} "${OVPN_INSTALL_PATH}"
  )
}

dl_wg_install() {
  mkowndir "$(dirname "${WG_INSTALL_PATH}")"

  (
    set -x
    curl -L -o "${WG_INSTALL_PATH}" "${WG_DL_URL}" \
    && chmod +x "${WG_INSTALL_PATH}" \
    && chown ${USER_NAME}:${USER_GROUP} "${WG_INSTALL_PATH}"
  )
}

ddns_create_conf() {
  local env_path="${DOCKER_DDNS_DIR}/.env"
  local yaml_path="${DOCKER_DDNS_DIR}/docker-compose.yaml"

  mkowndir "$(dirname "${env_path}")"

  [[ -f "${env_path}" ]] && {
    print_info "${env_path} is already installed, skipping"
  } || {
    cp "${TPL_DIR}/ddns.env" "${env_path}"
    chown ${USER_NAME}:${USER_GROUP} "${env_path}"
  }
  cp "${TPL_DIR}/ddns.docker-compose.yaml" "${yaml_path}"
  chown ${USER_NAME}:${USER_GROUP} "${yaml_path}"
}

trap_help "${@}" && exit

fail_noroot || exit $?

install_base_tools
install_docker

ddns_create_conf

dl_initos
dl_ovpn_install
dl_wg_install
