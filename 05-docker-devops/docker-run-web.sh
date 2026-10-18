#!/usr/bin/env bash
#
# docker-run-web.sh — launch a known web image with port/volume mapping and print its URL + IP
#   commands showcased: docker run -d -p -v --name, docker inspect
#
# Usage: ./docker-run-web.sh [options]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
docker-run-web.sh — launch a web container and print its URL + IP

Usage: $0 [options]

Options:
  -i, --image IMAGE     image preset or custom image (default: nginx)
                        presets: nginx | apache | jenkins | <custom-image>
  -p, --port HOSTPORT   host port to publish (default: 8080)
  --name NAME           container name (default: derived from image)
  -v, --volume HOSTDIR  host directory to bind-mount at the image docroot
  --dry-run             print the docker command instead of running it (DRY_RUN=1)
  --yes                 skip the confirmation prompt (ASSUME_YES=1)
  -h, --help            show this help and exit

Deprecated (still works, removed in 2.0.0): -n NAME (use --name).

Exit status: 0 on success, 1 on a failure or a declined prompt, 2 on a usage
error.
EOF
}

main() {
  local image="nginx"
  local hostport="8080"
  local name=""
  local hostdir=""

  help_requested "$@" && { usage; exit 0; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--image)  need_arg "$@"; image="$2"; shift 2 ;;
      -p|--port)   need_arg "$@"; hostport="$2"; shift 2 ;;
      --name)      need_arg "$@"; name="$2"; shift 2 ;;
      -n)          deprecated -n --name; need_arg "$@"; name="$2"; shift 2 ;;
      -v|--volume) need_arg "$@"; hostdir="$2"; shift 2 ;;
      --dry-run)   export DRY_RUN=1; shift ;;
      --yes)       export ASSUME_YES=1; shift ;;
      --) shift; [[ $# -eq 0 ]] || usage_error "unexpected argument: $1"; break ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done

  [[ "$hostport" =~ ^[1-9][0-9]{0,4}$ && "$hostport" -le 65535 ]] \
    || usage_error "--port must be a port number 1-65535 (got '$hostport')"

  need_cmd docker

  # Resolve preset -> real image, container port and docroot.
  local real_image cport docroot
  case "$image" in
    nginx)
      real_image="nginx"
      cport="80"
      docroot="/usr/share/nginx/html"
      ;;
    apache|httpd)
      real_image="httpd"
      cport="80"
      docroot="/usr/local/apache2/htdocs"
      ;;
    jenkins)
      real_image="jenkins/jenkins"
      cport="8080"
      docroot=""
      ;;
    *)
      # Custom image: no known docroot, default container port to 80.
      real_image="$image"
      cport="80"
      docroot=""
      ;;
  esac

  # Default name from the image's last path/tag component.
  if [[ -z "$name" ]]; then
    name="web-${real_image##*/}"
    name="${name%%:*}"
  fi

  # Assemble the docker run argument vector.
  local -a docker_args=(run -d --name "$name" -p "${hostport}:${cport}")

  if [[ -n "$hostdir" ]]; then
    [[ -d "$hostdir" ]] || die "host directory does not exist: $hostdir"
    if [[ -z "$docroot" ]]; then
      c_warn "no known docroot for image '$image'; skipping volume mount"
    else
      local abs_hostdir
      abs_hostdir="$(cd "$hostdir" && pwd)"
      docker_args+=(-v "${abs_hostdir}:${docroot}")
    fi
  fi

  docker_args+=("$real_image")

  banner "docker run: $name"
  c_info "image      : $real_image"
  c_info "port map   : ${hostport} -> ${cport}"
  [[ -n "$docroot" ]] && c_info "docroot    : $docroot"

  confirm_or_abort "Launch container '$name' from '$real_image'?"

  run docker "${docker_args[@]}"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_info "DRY_RUN set; skipping inspect"
    exit 0
  fi

  hr
  c_ok "container started"
  c_info "URL: http://localhost:${hostport}"

  local ip
  ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name" 2>/dev/null || true)"
  if [[ -n "$ip" ]]; then
    c_info "container IP: $ip"
  else
    c_warn "could not determine container IP"
  fi
}

main "$@"
