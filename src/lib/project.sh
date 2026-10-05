# ai-cli-terminal — project name resolver
#
#   projectName = basename(currentWorkingDirectory)
#
# No git, no manifests, no registry. If the directory is
# /home/user/projects/tft-training-log the project name is tft-training-log.
#
# shellcheck shell=bash

# act::project::name [dir] -> stdout
#
# * default input: $PWD
# * trailing slashes are removed, "/" stays "/"
# * a Windows path (backslashes, no forward slash) is split on "\" too, so
#   `D:\ghq\github.com\DwainYu\TFTAutoRecorder` -> `TFTAutoRecorder`
act::project::name() {
    local dir=${1-}

    if [ -z "$dir" ]; then
        dir=${PWD-}
    fi

    # Windows-style path handling (also useful under Git Bash / MSYS).
    case $dir in
        */*) ;;
        *\\*) dir=${dir//\\//} ;;
    esac

    # Strip trailing separators but keep the root as "/".
    while [ "$dir" != "/" ] && [ "${dir%/}" != "$dir" ]; do
        dir=${dir%/}
    done

    if [ -z "$dir" ]; then
        dir=/
    fi

    if [ "$dir" = "/" ]; then
        printf '/'
        return 0
    fi

    local base=${dir##*/}
    if [ -z "$base" ]; then
        base=$dir
    fi
    printf '%s' "$base"
}

# act::project::title <cli-name> [dir] -> stdout
# Convenience: the complete tab title for the current directory.
act::project::title() {
    local cli=${1-}
    local dir=${2-${PWD-}}
    # shellcheck source=src/lib/title.sh
    act::title::format "$(act::project::name "$dir")" "$cli"
}
