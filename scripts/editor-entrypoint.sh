#!/bin/sh
set -eu

workspace=/home/coder/project
repository=https://github.com/kursap1906-lang/Aplikacja-Git.git

if [ ! -d "$workspace/.git" ]; then
  if [ -n "$(find "$workspace" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
    echo "Workspace is not empty and is not a Git checkout; refusing to overwrite it." >&2
    exit 1
  fi

  git clone --depth 1 --branch main "$repository" "$workspace"
  git -C "$workspace" switch -c phone-editor
fi

exec code-server \
  --auth none \
  --bind-addr 0.0.0.0:8080 \
  --base-path /editor \
  --base-path-relative \
  "$workspace"
