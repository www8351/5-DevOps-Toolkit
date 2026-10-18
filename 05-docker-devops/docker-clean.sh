#!/usr/bin/env bash
#
# docker-clean.sh — prune stopped containers and dangling images
#   commands showcased: docker ps -a, docker rm, docker images, docker rmi
#
# Usage: ./docker-clean.sh [options]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
docker-clean.sh — prune stopped containers and dangling images

Usage: $0 [options]

Options:
  -f                 also remove created/dead containers (not just exited)
      --images-only      only prune dangling images
      --containers-only  only prune stopped containers
  -h, --help         show this help and exit

Environment:
  DRY_RUN=1          print the removal commands instead of running them
  ASSUME_YES=1       skip the confirmation prompt
EOF
}

main() {
  local include_dead=0
  local do_containers=1
  local do_images=1

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)         usage; exit 0 ;;
      -f)                include_dead=1 ;;
      --images-only)     do_containers=0 ;;
      --containers-only) do_images=0 ;;
      -*)                die "unknown option: $1 (try --help)" ;;
      *)                 die "unexpected argument: $1 (try --help)" ;;
    esac
    shift
  done

  [[ "$do_containers" -eq 1 || "$do_images" -eq 1 ]] \
    || die "--images-only and --containers-only are mutually exclusive"

  need_cmd docker

  local container_ids="" image_ids=""

  # Gather stopped container IDs.
  if [[ "$do_containers" -eq 1 ]]; then
    container_ids="$(docker ps -aq -f status=exited 2>/dev/null || true)"
    if [[ "$include_dead" -eq 1 ]]; then
      local extra
      extra="$(docker ps -aq -f status=created -f status=dead 2>/dev/null || true)"
      container_ids="$(printf '%s\n%s\n' "$container_ids" "$extra" | sort -u | sed '/^$/d')"
    fi
  fi

  # Gather dangling image IDs.
  if [[ "$do_images" -eq 1 ]]; then
    image_ids="$(docker images -f dangling=true -q 2>/dev/null || true)"
  fi

  banner "docker cleanup plan"
  if [[ -n "$container_ids" ]]; then
    c_info "stopped containers to remove:"
    docker ps -a --filter status=exited --format '  {{.ID}}  {{.Image}}  {{.Names}}' 2>/dev/null || true
  else
    c_info "no stopped containers to remove"
  fi
  if [[ -n "$image_ids" ]]; then
    c_info "dangling images to remove:"
    docker images -f dangling=true --format '  {{.ID}}  {{.Repository}}:{{.Tag}}' 2>/dev/null || true
  else
    c_info "no dangling images to remove"
  fi

  if [[ -z "$container_ids" && -z "$image_ids" ]]; then
    c_ok "nothing to clean — system already tidy"
    exit 0
  fi

  hr
  confirm "Proceed with removal ?" || { c_warn "aborted"; exit 0; }

  if [[ -n "$container_ids" ]]; then
    # shellcheck disable=SC2086
    run docker rm $container_ids
    c_ok "removed stopped containers"
  fi

  if [[ -n "$image_ids" ]]; then
    # shellcheck disable=SC2086
    run docker rmi $image_ids
    c_ok "removed dangling images"
  fi

  c_ok "cleanup complete"
}

main "$@"
