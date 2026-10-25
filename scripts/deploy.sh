#!/usr/bin/env bash
set -euo pipefail

remote="devops"
remote_dir="/var/www/devops-site"
site_url="https://devops.local"
ca_cert="${HOME}/devops.crt"

if [[ "$#" -gt 1 ]]; then
    echo "usage: scripts/deploy.sh [--dry-run]" >&2
    exit 2
fi

dry_run=0
if [[ "$#" -eq 1 ]]; then
    if [[ "$1" == "--dry-run" ]]; then
        dry_run=1
    else
        echo "usage: scripts/deploy.sh [--dry-run]" >&2
        exit 2
    fi
fi

if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo "error: run this script inside a git repository" >&2
    exit 1
fi

local_dir="${repo_root}/site/"

if [[ ! -f "${local_dir}index.html" ]]; then
    echo "error: site/index.html is missing" >&2
    exit 1
fi

if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]]; then
    echo "error: commit all repository changes before deployment" >&2
    exit 1
fi

rsync_args=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")

if [[ "$dry_run" -eq 1 ]]; then
    rsync "${rsync_args[@]}" --dry-run "$local_dir" "${remote}:${remote_dir}/"
    exit 0
fi

rsync "${rsync_args[@]}" "$local_dir" "${remote}:${remote_dir}/"

if ! curl --fail --silent --show-error --cacert "$ca_cert" --output /dev/null "$site_url"; then
    echo "error: HTTPS health check failed" >&2
    exit 1
fi

printf 'deployed commit %s\n' "$(git -C "$repo_root" rev-parse --short HEAD)"
