#!/usr/bin/env bash
#
# install-jenkins.sh — install Jenkins on Debian/Ubuntu (JDK, repo, service, firewall)
#   commands showcased: apt-get, curl, systemctl, ufw
#
# Usage: sudo ./install-jenkins.sh
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
  -h, --help     show this help and exit

Environment:
  DRY_RUN=1      print every command instead of running it
  ASSUME_YES=1   skip the confirmation prompt
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
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -*)        die "unknown option: $1 (try --help)" ;;
      *)         die "unexpected argument: $1 (try --help)" ;;
    esac
  done

  require_root
  command -v apt-get >/dev/null 2>&1 || die "this installer supports Debian/Ubuntu (apt-get) only"
  need_cmd curl

  banner "Jenkins installer (Debian/Ubuntu)"
  confirm "Install Jenkins and its dependencies now ?" || { c_warn "aborted"; exit 0; }

  c_info "refreshing package index"
  run apt-get update

  c_info "installing prerequisites (fontconfig, default-jdk)"
  run apt-get install -y fontconfig default-jdk

  c_info "adding the Jenkins signing key"
  run curl -fsSL "$JENKINS_KEY_URL" -o "$JENKINS_KEYRING"

  c_info "writing the Jenkins apt repository"
  local repo_line="deb [signed-by=${JENKINS_KEYRING}] https://pkg.jenkins.io/debian-stable binary/"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_info "DRY_RUN: would write '$repo_line' to $JENKINS_LIST"
  else
    printf '%s\n' "$repo_line" > "$JENKINS_LIST"
    c_ok "wrote $JENKINS_LIST"
  fi

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
  c_ok "Jenkins installation finished"
  c_info "Open the web UI at: http://${ip}:8080"
  c_info "Initial admin password lives at: $JENKINS_SECRET"
  c_info "Reveal it with: sudo cat $JENKINS_SECRET"
}

main "$@"
