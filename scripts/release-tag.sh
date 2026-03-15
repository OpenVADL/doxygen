#!/usr/bin/env bash

set -euo pipefail

REMOTE="origin"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/doxygen/doxygen.git}"
VERSION_FILE="VERSION"
DRY_RUN=0
AUTO_CONFIRM=0

usage() {
  cat <<'EOF'
Usage: scripts/release-tag.sh [options]

Creates and pushes the next OpenVADL release tag for the upstream version in VERSION.

Options:
  --dry-run               Print the resolved tag without creating or pushing it
  --yes                   Skip the confirmation prompt
  --remote <name>         Git remote to query and push to (default: origin)
  --upstream-repo <url>   Upstream Doxygen repo or remote URL
                          (default: https://github.com/doxygen/doxygen.git)
  --version-file <path>   Version file to read (default: VERSION)
  -h, --help              Show this help
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

resolve_remote_tag_commit() {
  local repo="$1"
  local tag="$2"
  local output
  local direct_hash=""
  local peeled_hash=""

  if ! output=$(git ls-remote --tags "$repo" "refs/tags/$tag" "refs/tags/$tag^{}"); then
    fail "failed to query tag '$tag' from '$repo'"
  fi

  if [[ -z "$output" ]]; then
    return 1
  fi

  while read -r hash ref; do
    if [[ "$ref" == "refs/tags/$tag^{}" ]]; then
      peeled_hash="$hash"
    elif [[ "$ref" == "refs/tags/$tag" ]]; then
      direct_hash="$hash"
    fi
  done <<< "$output"

  if [[ -n "$peeled_hash" ]]; then
    printf '%s\n' "$peeled_hash"
    return 0
  fi

  if [[ -n "$direct_hash" ]]; then
    printf '%s\n' "$direct_hash"
    return 0
  fi

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --yes)
      AUTO_CONFIRM=1
      shift
      ;;
    --remote)
      [[ $# -ge 2 ]] || fail "missing value for --remote"
      REMOTE="$2"
      shift 2
      ;;
    --upstream-repo)
      [[ $# -ge 2 ]] || fail "missing value for --upstream-repo"
      UPSTREAM_REPO="$2"
      shift 2
      ;;
    --version-file)
      [[ $# -ge 2 ]] || fail "missing value for --version-file"
      VERSION_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a git repository"
cd "$repo_root"

[[ -f "$VERSION_FILE" ]] || fail "version file not found: $VERSION_FILE"

upstream_version=$(tr -d '[:space:]' < "$VERSION_FILE")
[[ "$upstream_version" =~ ^[0-9]+(\.[0-9]+)+$ ]] || fail "invalid upstream version in $VERSION_FILE: '$upstream_version'"

expected_branch="Release_${upstream_version//./_}"
current_branch=$(git symbolic-ref -q HEAD || true)
current_branch="${current_branch#refs/heads/}"
current_branch="${current_branch#heads/}"
if [[ -n "$current_branch" && "$current_branch" != "$expected_branch" ]]; then
  fail "expected to run on branch '$expected_branch', got '$current_branch'"
fi

if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  fail "working tree has uncommitted changes"
fi

head_commit=$(git rev-parse HEAD)
upstream_release_tag="Release_${upstream_version//./_}"
upstream_commit=$(resolve_remote_tag_commit "$UPSTREAM_REPO" "$upstream_release_tag") \
  || fail "upstream tag '$upstream_release_tag' was not found in '$UPSTREAM_REPO'"

if [[ "$head_commit" == "$upstream_commit" ]]; then
  fail "HEAD is still the upstream release commit ($upstream_release_tag); add fork changes before tagging"
fi

if git cat-file -e "${upstream_commit}^{commit}" 2>/dev/null; then
  if ! git merge-base --is-ancestor "$upstream_commit" HEAD; then
    fail "HEAD does not descend from upstream release commit '$upstream_release_tag'"
  fi
fi

current_release_tags=$(git tag --points-at HEAD --list "${upstream_version}-openvadl*")
if [[ -n "$current_release_tags" ]]; then
  fail "HEAD already has release tag(s): $(printf '%s' "$current_release_tags" | tr '\n' ' ')"
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  fail "git remote '$REMOTE' does not exist"
fi

remote_branch_ref="refs/heads/${expected_branch}"
remote_branch_line=$(git ls-remote --heads "$REMOTE" "$remote_branch_ref") \
  || fail "failed to query branch '$expected_branch' from remote '$REMOTE'"

if [[ -z "$remote_branch_line" ]]; then
  fail "remote branch '$REMOTE/$expected_branch' does not exist"
fi

remote_branch_commit=${remote_branch_line%%[[:space:]]*}
if [[ "$remote_branch_commit" != "$head_commit" ]]; then
  fail "HEAD ($head_commit) does not match '$REMOTE/$expected_branch' ($remote_branch_commit)"
fi

published_tags=$(git ls-remote --tags --refs "$REMOTE" "refs/tags/${upstream_version}-openvadl*") \
  || fail "failed to query published release tags from remote '$REMOTE'"

previous_tag=""
max_release=0
tag_prefix="${upstream_version}-openvadl"

if [[ -n "$published_tags" ]]; then
  while read -r _ ref; do
    tag_name="${ref#refs/tags/}"
    if [[ "$tag_name" == "${tag_prefix}"* ]]; then
      suffix="${tag_name#${tag_prefix}}"
      if [[ "$suffix" =~ ^[0-9]+$ ]] && (( suffix > max_release )); then
        max_release=$suffix
        previous_tag="$tag_name"
      fi
    fi
  done <<< "$published_tags"
fi

next_release=$((max_release + 1))
next_tag="${tag_prefix}${next_release}"

if git rev-parse --verify --quiet "refs/tags/${next_tag}" >/dev/null; then
  fail "local tag '$next_tag' already exists"
fi

if [[ -n "$(git ls-remote --tags --refs "$REMOTE" "refs/tags/${next_tag}")" ]]; then
  fail "remote tag '$next_tag' already exists on '$REMOTE'"
fi

echo "Upstream version:     $upstream_version"
echo "Upstream release tag: $upstream_release_tag"
if [[ -n "$previous_tag" ]]; then
  echo "Previous release tag: $previous_tag"
else
  echo "Previous release tag: none"
fi
echo "Next release tag:     $next_tag"
echo "HEAD commit:          $head_commit"

if (( DRY_RUN )); then
  echo "Dry run only; no tag was created or pushed."
  exit 0
fi

if (( ! AUTO_CONFIRM )); then
  printf "Create and push tag '%s' to '%s'? [y/N] " "$next_tag" "$REMOTE"
  read -r confirmation
  if [[ ! "$confirmation" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Aborted; no tag was created or pushed."
    exit 1
  fi
fi

git tag -a "$next_tag" -m "Release $next_tag"
git push "$REMOTE" "refs/tags/$next_tag"

echo "Created and pushed tag '$next_tag' to '$REMOTE'."
