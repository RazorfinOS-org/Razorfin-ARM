#!/usr/bin/env bash

# Shared helpers for Razorfin's Valve-style ARM64 Proton reference path.

RAZORFIN_STEAM_ARM_ENV="/usr/lib/razorfin/steam-arm/manifests/steam-arm64.conf"
if [[ -f "${RAZORFIN_STEAM_ARM_ENV}" ]]; then
    # shellcheck disable=SC1091
    source "${RAZORFIN_STEAM_ARM_ENV}"
fi

: "${RAZORFIN_STEAM_ARM_BASE:=/usr/lib/razorfin/steam-arm}"
: "${RAZORFIN_STEAMRT4_ARM64_NAME:=SteamLinuxRuntime_4-arm64}"
: "${RAZORFIN_STEAMRT4_ARM64_APPID:=4185400}"
: "${RAZORFIN_STEAMRT4_ARM64_BASE_URL:=https://repo.steampowered.com/steamrt4/images/latest-container-runtime-public-beta}"
: "${RAZORFIN_PROTON_ARM64_APPID:=4628740}"
: "${RAZORFIN_PROTON_ARM64_DISPLAY_NAME:=Proton 11.0 (ARM64)}"
: "${RAZORFIN_PROTON_ARM64_SYSTEM_DIR:=/usr/lib/razorfin/steam-arm/compatibilitytools.d/Proton-11.0-arm64}"

razorfin_steam_home() {
    printf '%s\n' "${RAZORFIN_STEAM_HOME:-${HOME}/.local/share/Steam}"
}

razorfin_runtime_dir() {
    printf '%s\n' "${RAZORFIN_STEAM_ARM_BASE}/runtime/${RAZORFIN_STEAMRT4_ARM64_NAME}"
}

razorfin_runtime_entry() {
    local runtime_dir

    runtime_dir="$(razorfin_runtime_dir)"
    for candidate in \
        "${runtime_dir}/_v2-entry-point" \
        "${runtime_dir}/run" \
        "${runtime_dir}/pressure-vessel/bin/steam-runtime-launch-client"; do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

razorfin_default_compatdata() {
    local appid="${1:?appid required}"

    printf '%s\n' "$(razorfin_steam_home)/steamapps/compatdata/${appid}"
}

razorfin_resolve_proton_dir() {
    local candidate
    local steam_home
    local -a search_roots

    steam_home="$(razorfin_steam_home)"
    search_roots=()

    if [[ -n "${RAZORFIN_PROTON_ARM64_PATH:-}" ]]; then
        search_roots+=("${RAZORFIN_PROTON_ARM64_PATH}")
    fi
    if [[ -n "${PROTONPATH:-}" ]]; then
        search_roots+=("${PROTONPATH}")
    fi

    search_roots+=(
        "${RAZORFIN_PROTON_ARM64_SYSTEM_DIR}"
        "${steam_home}/steamapps/common/${RAZORFIN_PROTON_ARM64_DISPLAY_NAME}"
        "${HOME}/.steam/root/steamapps/common/${RAZORFIN_PROTON_ARM64_DISPLAY_NAME}"
        "${HOME}/.steam/debian-installation/steamapps/common/${RAZORFIN_PROTON_ARM64_DISPLAY_NAME}"
    )

    for candidate in "${search_roots[@]}"; do
        if [[ -x "${candidate}/proton" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    for candidate in \
        "${RAZORFIN_STEAM_ARM_BASE}/compatibilitytools.d" \
        "${steam_home}/compatibilitytools.d" \
        "${HOME}/.steam/root/compatibilitytools.d" \
        "${HOME}/.steam/debian-installation/compatibilitytools.d"; do
        if [[ ! -d "${candidate}" ]]; then
            continue
        fi

        while IFS= read -r manifest; do
            local dir

            dir="$(dirname "${manifest}")"
            if [[ -x "${dir}/proton" ]]; then
                printf '%s\n' "${dir}"
                return 0
            fi
        done < <(find "${candidate}" -maxdepth 2 -name 'toolmanifest_arm64.vdf' -type f 2>/dev/null | sort)
    done

    return 1
}

razorfin_resolve_native_steam() {
    local steam_bin

    if ! steam_bin="$(command -v steam 2>/dev/null)"; then
        return 1
    fi

    printf '%s\n' "${steam_bin}"
}

razorfin_print_arm64_status() {
    local runtime_dir
    local runtime_version_file
    local runtime_version
    local proton_dir
    local runtime_entry

    runtime_dir="$(razorfin_runtime_dir)"
    runtime_version_file="${RAZORFIN_STEAM_ARM_BASE}/manifests/steamrt4-arm64.version"
    runtime_version="unknown"
    if [[ -f "${runtime_version_file}" ]]; then
        runtime_version="$(tr -d '\n' < "${runtime_version_file}")"
    fi

    echo "Razorfin ARM64 Proton reference stack"
    echo "  Base dir: ${RAZORFIN_STEAM_ARM_BASE}"
    echo "  Steam home: $(razorfin_steam_home)"
    echo "  Runtime dir: ${runtime_dir}"
    echo "  Runtime version: ${runtime_version}"

    if runtime_entry="$(razorfin_runtime_entry 2>/dev/null)"; then
        echo "  Runtime entry: ${runtime_entry}"
    else
        echo "  Runtime entry: missing"
    fi

    if proton_dir="$(razorfin_resolve_proton_dir 2>/dev/null)"; then
        echo "  Proton tool: ${proton_dir}"
    else
        echo "  Proton tool: missing"
        echo "  Install hint: queue Steam app ${RAZORFIN_PROTON_ARM64_APPID} (${RAZORFIN_PROTON_ARM64_DISPLAY_NAME})"
        echo "  Or place a Proton ARM64 build at ${RAZORFIN_PROTON_ARM64_SYSTEM_DIR}"
    fi

    echo "  Runtime appid: ${RAZORFIN_STEAMRT4_ARM64_APPID}"
    echo "  Proton appid: ${RAZORFIN_PROTON_ARM64_APPID}"
}
