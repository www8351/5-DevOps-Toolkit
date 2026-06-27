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
  -i IMAGE     image preset or custom image (default: nginx)
               presets: nginx | apache | jenkins | <custom-image>
  -p HOSTPORT  host port to publish (default: 8080)
  -n NAME      container name (default: derived from image)
  -v HOSTDIR   host directory to bind-mount at the image docroot
  -h, --help   show this help and exit

Environment:
  DRY_RUN=1    print the docker command instead of running it
  ASSUME_YES=1 skip the confirmation prompt
EOF
}

main() {
  local image="nginx"
  local hostport="8080"
  local name=""
  local hostdir=""

  # Long-help shim: getopts does not handle --help on its own.
  if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local opt
  while getopts ":i:p:n:v:h" opt; do
    case "$opt" in
      i) image="$OPTARG" ;;
      p) hostport="$OPTARG" ;;
      n) name="$OPTARG" ;;
      v) hostdir="$OPTARG" ;;
      h) usage; exit 0 ;;
      :) die "option -$OPTARG requires an argument" ;;
      \?) die "unknown option: -$OPTARG (try --help)" ;;
    esac
  done
  shift $((OPTIND - 1))

  need_cmd docker

  [[ "$hostport" =~ ^[0-9]+$ ]] || die "host port must be numeric: $hostport"

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

  confirm "Launch container '$name' from '$real_image' ?" || { c_warn "aborted"; exit 0; }

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
