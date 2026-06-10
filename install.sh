#!/usr/bin/env bash
#
# install.sh — Manage symlinks for skills and selected config/scripts.
#
# Usage:
#   ./install.sh           # create/update symlinks
#   ./install.sh --remove  # remove symlinks (warn on non-links)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="${HOME}/.copilot/skills"

mkdir -p "$SKILLS_DIR"

remove=false
[[ "${1:-}" == "--remove" ]] && remove=true

ensure_link() {
    local source="$1"
    local target="$2"
    local label="$3"

    mkdir -p "$(dirname "$target")"

    if $remove; then
        if [[ -L "$target" ]]; then
            echo "removing $target"
            rm "$target"
        elif [[ -e "$target" ]]; then
            echo "WARN:    $target exists and is not a symlink (not removing)"
        fi
        return
    fi

    if [[ -L "$target" ]]; then
        local current
        current="$(readlink "$target")"

        if [[ "$current" == "$source" ]]; then
            echo "exists:  $label -> $current"
        else
            rm "$target"
            ln -s "$source" "$target"
            echo "relinked: $label -> $source"
        fi
    elif [[ -e "$target" ]]; then
        echo "WARN:    $target exists and is not a symlink"
    else
        ln -s "$source" "$target"
        echo "linked:  $label -> $source"
    fi
}

for skill_dir in "$SCRIPT_DIR"/*/; do
    skill_name="$(basename "$skill_dir")"

    # Skip non-skill directories
    [[ -f "$skill_dir/SKILL.md" ]] || continue

    target="$SKILLS_DIR/$skill_name"

    ensure_link "$skill_dir" "$target" "$skill_name"
done

ensure_link "$SCRIPT_DIR/bc-wsl-diff" "${HOME}/bin/bc-wsl-diff" "bc-wsl-diff"
ensure_link "$SCRIPT_DIR/bc-wsl-edit" "${HOME}/bin/bc-wsl-edit" "bc-wsl-edit"
ensure_link "$SCRIPT_DIR/bc-wsl-merge" "${HOME}/bin/bc-wsl-merge" "bc-wsl-merge"
ensure_link "$SCRIPT_DIR/find-cargo.py" "${HOME}/bin/find-cargo" "find-cargo"
ensure_link "$SCRIPT_DIR/.jjconfig.toml" "${HOME}/.jjconfig.toml" ".jjconfig.toml"
ensure_link "$SCRIPT_DIR/.bash_aliases" "${HOME}/.bash_aliases" ".bash_aliases"
