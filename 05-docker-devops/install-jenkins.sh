#!/usr/bin/env bash
#
# install-jenkins.sh — install Jenkins on Debian/Ubuntu (JDK, repo, service, firewall)
#   commands showcased: apt-get, curl, systemctl, ufw
#
# Usage: sudo ./install-jenkins.sh [--dry-run] [--yes]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

readonly JENKINS_KEY_URL="https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key"
readonly JENKINS_KEYRING="/usr/share/keyrings/jenkins-keyring.asc"
readonly JENKINS_LIST="/etc/apt/sources.list.d/jenkins.list"
readonly JENKINS_SECRET="/var/lib/jenkins/secrets/initialAdminPassword"

usage() {
  cat <<EOF
install-jenkins.sh — install Jenkins on Debian/Ubuntu

Usage: sudo $0 [options]

Installs the JDK, adds the official Jenkins apt repository, installs and
enables the Jenkins service, and opens port 8080 in ufw if present.

Options:
  --dry-run      print every command instead of running it (DRY_RUN=1)
  --yes          skip the confirmation prompt (ASSUME_YES=1)
  -h, --help     show this help and exit

Exit status: 0 on success, 1 on a failure or a declined prompt, 2 on a usage
error.
EOF
}

# Best-effort detection of the server's primary IPv4 address.
detect_ip() {
  local ip=""
  if command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  if [[ -z "$ip" ]] && command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for (i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')"
  fi
  printf '%s\n' "${ip:-SERVER_IP}"
}

main() {
  help_requested "$@" && { usage; exit 0; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) export DRY_RUN=1; shift ;;
      --yes)     export ASSUME_YES=1; shift ;;
      --) shift; [[ $# -eq 0 ]] || usage_error "unexpected argument: $1"; break ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done

  require_root
  command -v apt-get >/dev/null 2>&1 || die "this installer supports Debian/Ubuntu (apt-get) only"
  need_cmd curl

  banner "Jenkins installer (Debian/Ubuntu)"
  confirm_or_abort "Install Jenkins and its dependencies now?"

  c_info "refreshing package index"
  run apt-get update

  c_info "installing prerequisites (fontconfig, default-jdk)"
  run apt-get install -y fontconfig default-jdk

  c_info "adding the Jenkins signing key"
  run curl -fsSL "$JENKINS_KEY_URL" -o "$JENKINS_KEYRING"

  c_info "writing the Jenkins apt repository"
  local repo_line="deb [signed-by=${JENKINS_KEYRING}] https://pkg.jenkins.io/debian-stable binary/"
  # Through `run` like every other side effect, so DRY_RUN=1 only prints it.
  run sh -c 'printf "%s\n" "$1" > "$2"' _ "$repo_line" "$JENKINS_LIST"
  [[ "${DRY_RUN:-0}" == "1" ]] || c_ok "wrote $JENKINS_LIST"

  c_info "refreshing package index with the Jenkins repo"
  run apt-get update

  c_info "installing Jenkins"
  run apt-get install -y jenkins

  c_info "enabling and starting the Jenkins service"
  run systemctl enable --now jenkins

  if command -v ufw >/dev/null 2>&1; then
    c_info "opening port 8080 in ufw"
    run ufw allow 8080
  else
    c_warn "ufw not found; skipping firewall rule (open port 8080 manually if needed)"
  fi

  local ip
  ip="$(detect_ip)"

  hr
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_info "dry run finished: nothing was changed"
  else
    c_ok "Jenkins installation finished"
  fi
  c_info "Open the web UI at: http://${ip}:8080"
  c_info "Initial admin password lives at: $JENKINS_SECRET"
  c_info "Reveal it with: sudo cat $JENKINS_SECRET"
}

main "$@"
