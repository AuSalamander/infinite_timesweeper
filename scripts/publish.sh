#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --beta|--release" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
case "$1" in
  --beta) channel=beta ;;
  --release) channel=release ;;
  *) usage ;;
esac

for command in gh git; do
  if ! command -v "$command" > /dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit and push all changes before publishing." >&2
  exit 1
fi

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "Publishing from a detached HEAD is not supported." >&2
  exit 1
fi

if ! upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2> /dev/null)"; then
  echo "The current branch has no upstream. Push it before publishing." >&2
  exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "$upstream")" ]]; then
  echo "The current branch is not synchronized with $upstream. Push or pull first." >&2
  exit 1
fi

gh auth status
default_branch="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name')"
if [[ "$branch" != "$default_branch" ]]; then
  echo "Publishing is only supported from the default branch: $default_branch" >&2
  exit 1
fi

gh workflow run android-release.yml --ref "$branch" --field "channel=$channel"

echo "Started the $channel build on $branch."
echo "Builds: $(gh browse --no-browser 2> /dev/null)/actions/workflows/android-release.yml"
echo "Releases: $(gh browse --no-browser 2> /dev/null)/releases"
