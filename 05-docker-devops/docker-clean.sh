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
  -a, --all          also remove created/dead containers (not just exited)
  --images-only      only prune dangling images
  --containers-only  only prune stopped containers
  --dry-run          print the removal commands instead of running them (DRY_RUN=1)
  --yes              skip the confirmation prompt (ASSUME_YES=1)
  -h, --help         show this help and exit

Deprecated (still works, removed in 2.0.0): -f (use -a/--all).

Exit status: 0 on success, 1 on a failure or a declined prompt, 2 on a usage
error.
EOF
}

main() {
  local include_dead=0
  local do_containers=1
  local do_images=1

  help_requested "$@" && { usage; exit 0; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--all)          include_dead=1 ;;
      -f)                deprecated -f -a/--all; include_dead=1 ;;
      --images-only)     do_containers=0 ;;
      --containers-only) do_images=0 ;;
      --dry-run)         export DRY_RUN=1 ;;
      --yes)             export ASSUME_YES=1 ;;
      --)                shift; [[ $# -eq 0 ]] || usage_error "unexpected argument: $1"; break ;;
      -*)                usage_error "unknown option: $1" ;;
      *)                 usage_error "unexpected argument: $1" ;;
    esac
    shift
  done

  [[ "$do_containers" -eq 1 || "$do_images" -eq 1 ]] \
    || usage_error "--images-only and --containers-only are mutually exclusive"

  need_cmd docker
  # Without this check every query below fails quietly (|| true) and a stopped
  # daemon is reported as "already tidy".
  docker info >/dev/null 2>&1 \
    || die "cannot reach the Docker daemon (is it running, and may this user use it?)"

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

  # The plan lists the same states that will be removed (-f adds created/dead).
  local -a state_filters=(--filter status=exited)
  if [[ "$include_dead" -eq 1 ]]; then
    state_filters+=(--filter status=created --filter status=dead)
  fi

  banner "docker cleanup plan"
  if [[ -n "$container_ids" ]]; then
    c_info "stopped containers to remove:"
    docker ps -a "${state_filters[@]}" --format '  {{.ID}}  {{.Image}}  {{.Names}}' 2>/dev/null || true
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
  confirm_or_abort "Proceed with removal?"

  if [[ -n "$container_ids" ]]; then
    # shellcheck disable=SC2086
    run docker rm $container_ids
    [[ "${DRY_RUN:-0}" == "1" ]] || c_ok "removed stopped containers"
  fi

  if [[ -n "$image_ids" ]]; then
    # shellcheck disable=SC2086
    run docker rmi $image_ids
    [[ "${DRY_RUN:-0}" == "1" ]] || c_ok "removed dangling images"
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_info "dry run finished: nothing was changed"
  else
    c_ok "cleanup complete"
  fi
}

main "$@"
