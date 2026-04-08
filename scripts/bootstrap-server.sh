#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Bootstrap a fresh Debian 13 host for the DB stack.
# Installs base packages, Docker Engine + Compose plugin, creates an SSH deploy
# key for GitHub, and clones the repository once the public key is authorized.
# ---------------------------------------------------------------------------

REPO_SSH_URL="${REPO_SSH_URL:-git@github.com:CurryBaxter/DB-Stack.git}"
TARGET_DIR="${TARGET_DIR:-$HOME/DB-Stack}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/db_stack_deploy_key}"

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

require_root_tools() {
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required on this host." >&2
    exit 1
  fi
}

install_base_packages() {
  log "Updating apt package index and upgrading installed packages"
  sudo apt update -y
  sudo apt upgrade -y

  log "Installing Git and prerequisite packages"
  sudo apt install -y git ca-certificates curl gnupg

  log "Git version"
  git --version
}

install_docker() {
  log "Installing Docker apt repository key"
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  log "Adding Docker apt repository"
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  log "Installing Docker Engine and Compose plugin"
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  log "Enabling Docker service"
  sudo systemctl enable --now docker

  log "Docker Compose version"
  docker compose version
}

ensure_ssh_key() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [[ -f "$SSH_KEY_PATH" ]]; then
    log "Reusing existing deploy key at $SSH_KEY_PATH"
  else
    log "Generating SSH deploy key at $SSH_KEY_PATH"
    ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "db-stack-deploy@$(hostname)"
  fi

  log "Public deploy key"
  cat "${SSH_KEY_PATH}.pub"

  cat <<EOF

Add the public key above as a read-only Deploy Key in the GitHub repository:
  CurryBaxter/DB-Stack

Then ensure SSH uses this key for github.com. Add this to ~/.ssh/config if needed:

Host github.com
  IdentityFile ${SSH_KEY_PATH}
  IdentitiesOnly yes

EOF
}

clone_repo() {
  if [[ -d "$TARGET_DIR/.git" ]]; then
    log "Repository already present at $TARGET_DIR"
    return
  fi

  log "Testing GitHub SSH access"
  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | tee /tmp/db-stack-github-ssh-test.log; then
    cat <<EOF

GitHub SSH access is not ready yet.
Make sure the deploy key has been added to CurryBaxter/DB-Stack and retry:
  REPO_SSH_URL='${REPO_SSH_URL}' TARGET_DIR='${TARGET_DIR}' $0

EOF
    return
  fi

  log "Cloning repository to $TARGET_DIR"
  git clone "$REPO_SSH_URL" "$TARGET_DIR"
}

main() {
  require_root_tools
  install_base_packages
  install_docker
  ensure_ssh_key
  clone_repo

  cat <<EOF

Bootstrap complete.

Next steps:
  1. cd ${TARGET_DIR}
  2. cp .env.example .env
  3. ./scripts/generate-secrets.sh
  4. Adjust .env and secret files for the target environment
  5. ./scripts/deploy.sh

EOF
}

main "$@"
