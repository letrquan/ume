#!/bin/sh
# mango-binds.sh <mango config.conf>
# Prints mango's config with every `source=` file put in its place (paths
# are relative to the file that sources them), for the shortcut cheat sheet
# (services/binds.js). A line "\001file <path>" marks where each file starts
# again, so a comment never runs on into the next file.
expand() {
    local file="$1" depth="$2" dir line f
    [ "$depth" -gt 5 ] && return
    [ -r "$file" ] || return
    dir=${file%/*}
    printf '\001file %s\n' "$file"
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in
            source*=*)
                f=${line#*=}
                f=${f#"${f%%[![:space:]]*}"}
                f=${f%"${f##*[![:space:]]}"}
                case $f in
                    /*) ;;
                    "~/"*) f=$HOME/${f#"~/"} ;;
                    *) f=$dir/$f ;;
                esac
                expand "$f" $((depth + 1))
                printf '\001file %s\n' "$file"
                ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < "$file"
}
expand "$1" 0
