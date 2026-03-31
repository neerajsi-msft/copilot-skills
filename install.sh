#!/usr/bin/env bash
#
# install.sh — Symlink all skills from this repo into ~/.copilot/skills/
#
# Usage:
#   ./install.sh           # install all skills
#   ./install.sh --remove  # remove symlinks
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="${HOME}/.copilot/skills"

mkdir -p "$SKILLS_DIR"

remove=false
[[ "${1:-}" == "--remove" ]] && remove=true

for skill_dir in "$SCRIPT_DIR"/*/; do
    skill_name="$(basename "$skill_dir")"

    # Skip non-skill directories
    [[ -f "$skill_dir/SKILL.md" ]] || continue

    target="$SKILLS_DIR/$skill_name"

    if $remove; then
        if [[ -L "$target" ]]; then
            echo "removing $target"
            rm "$target"
        fi
    else
        if [[ -L "$target" ]]; then
            echo "exists:  $skill_name -> $(readlink "$target")"
        elif [[ -e "$target" ]]; then
            echo "SKIP:    $skill_name (not a symlink — manual install?)"
        else
            ln -s "$skill_dir" "$target"
            echo "linked:  $skill_name -> $skill_dir"
        fi
    fi
done
