#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="${INPUT_DEPLOY_DIRECTORY:-.}"

BASE_REF="${INPUT_BASE_REF}"
if [ -z "$BASE_REF" ]; then
  if [ -n "${GITHUB_BASE_REF:-}" ]; then
    BASE_REF="origin/$GITHUB_BASE_REF"
  elif [ -n "${GITHUB_EVENT_BEFORE:-}" ] && [ "$GITHUB_EVENT_BEFORE" != "0000000000000000000000000000000000000000" ]; then
    BASE_REF="$GITHUB_EVENT_BEFORE"
  fi
fi

if [ -z "$BASE_REF" ]; then
  echo "No base ref available (initial push?) — syncing all challenges"
  echo "should_sync=true" >> "$GITHUB_OUTPUT"
  echo "only_flags=" >> "$GITHUB_OUTPUT"
  echo "global_changed=true" >> "$GITHUB_OUTPUT"
  echo "challenges=" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Base ref: $BASE_REF"

CHANGED_FILES=$(git diff --name-only "$BASE_REF" HEAD -- "$DEPLOY_DIR")

if [ -z "$CHANGED_FILES" ]; then
  echo "No files changed under $DEPLOY_DIR"
  echo "should_sync=false" >> "$GITHUB_OUTPUT"
  echo "only_flags=" >> "$GITHUB_OUTPUT"
  echo "global_changed=false" >> "$GITHUB_OUTPUT"
  echo "challenges=" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Changed files:"
echo "$CHANGED_FILES"

GLOBAL_CHANGED=false
while IFS= read -r file; do
  rel="${file#"$DEPLOY_DIR"/}"
  [ "$DEPLOY_DIR" = "." ] && rel="$file"

  basename=$(basename "$rel")
  dir=$(dirname "$rel")

  if [ "$dir" = "." ] && [[ "$basename" =~ ^kona\.(toml|yaml|yml)$ ]]; then
    GLOBAL_CHANGED=true
    break
  fi
done <<< "$CHANGED_FILES"

if [ "$GLOBAL_CHANGED" = "true" ]; then
  echo "Global kona config changed — syncing all challenges"
  echo "should_sync=true" >> "$GITHUB_OUTPUT"
  echo "only_flags=" >> "$GITHUB_OUTPUT"
  echo "global_changed=true" >> "$GITHUB_OUTPUT"
  echo "challenges=" >> "$GITHUB_OUTPUT"
  exit 0
fi

declare -A CHALLENGE_DIRS
while IFS= read -r file; do
  dir=$(dirname "$file")

  while [ "$dir" != "." ] && [ "$dir" != "$DEPLOY_DIR" ]; do
    if [ -f "$dir/kona.toml" ] || [ -f "$dir/kona.yaml" ] || [ -f "$dir/kona.yml" ]; then
      CHALLENGE_DIRS["$dir"]=1
      break
    fi
    dir=$(dirname "$dir")
  done
done <<< "$CHANGED_FILES"

if [ ${#CHALLENGE_DIRS[@]} -eq 0 ]; then
  echo "No challenge directories affected"
  echo "should_sync=false" >> "$GITHUB_OUTPUT"
  echo "only_flags=" >> "$GITHUB_OUTPUT"
  echo "global_changed=false" >> "$GITHUB_OUTPUT"
  echo "challenges=" >> "$GITHUB_OUTPUT"
  exit 0
fi

ONLY_FLAGS=""
CHALLENGES_LIST=""
for dir in "${!CHALLENGE_DIRS[@]}"; do
  ONLY_FLAGS="$ONLY_FLAGS --only $dir"
  CHALLENGES_LIST="$CHALLENGES_LIST $dir"
done
ONLY_FLAGS="${ONLY_FLAGS# }"
CHALLENGES_LIST="${CHALLENGES_LIST# }"

echo "Challenges to sync: $CHALLENGES_LIST"

echo "should_sync=true" >> "$GITHUB_OUTPUT"
echo "only_flags=$ONLY_FLAGS" >> "$GITHUB_OUTPUT"
echo "global_changed=false" >> "$GITHUB_OUTPUT"
echo "challenges=$CHALLENGES_LIST" >> "$GITHUB_OUTPUT"
