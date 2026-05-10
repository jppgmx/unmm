#!/usr/bin/bash
#
# UNMM Common Module
#  - Version: 1.0.0
#  - Description: Módulo comum para UNMM.
#
# Sob licença MIT
#

if [[ -n "${UNMM_LIB_COMMON_LOADED:-}" ]]; then
    return 0
fi
UNMM_LIB_COMMON_LOADED=true

# Comando geral para instalação de pacotes via APT para CLI
export APT_GET_COMMAND="apt-get install -y --no-install-recommends -o Dpkg::Use-Pty=0"
export UNMM_VERSION="1.0.0"

# Source - https://stackoverflow.com/a
# Posted by Nicholas Sushkin, modified by community. See post 'Timeline' for change history
# Retrieved 2026-01-02, License - CC BY-SA 4.0

function join_by { local IFS="$1"; shift; echo "$*"; }

_common_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/uc.sh
source "${_common_lib_dir}/uc.sh"
unset _common_lib_dir

no_logo() {
    local enabled="${UNMM_GENERAL_NO_LOGO:-false}"
    [[ "$enabled" == "true" || "$enabled" == "1" ]]
}

mountpoint() {
    local path="${UNMM_GENERAL_MOUNT_POINT:-/mnt/unmm}"
    echo "$path"
}

keep_on_errors() {
    local enabled="${UNMM_GENERAL_KEEP_ON_ERRORS:-false}"
    [[ "$enabled" == "true" || "$enabled" == "1" ]]
}

output_dir() {
    local dir="${UNMM_GENERAL_OUTPUT_DIR:-./output}"
    echo "$dir"
}

# size_less_than <size1> <size2>
# Compara dois tamanhos (em MB ou GB) e verifica se o primeiro é menor que o segundo.
#
# Argumentos:
#   size1 - Primeiro tamanho (ex: 512M, 2G)
#   size2 - Segundo tamanho (ex: 1G, 2048M)
#
# Retorna:
#   0 se size1 < size2, 1 caso contrário.
size_less_than() {
    local size1="$1"
    local size2="$2"

    if ! uc_convert "$size1" B >/dev/null 2>&1; then
        echo "Formato de tamanho inválido: $size1" >&2
        return 2
    fi

    if ! uc_convert "$size2" B >/dev/null 2>&1; then
        echo "Formato de tamanho inválido: $size2" >&2
        return 2
    fi

    if uc_compare "$size1" "$size2" lt >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# to_absolute_path <input_path>
# Converte um caminho relativo ou com til (~) para um caminho absoluto.
#
# Argumentos:
#   input_path - Caminho de entrada (relativo ou com ~)
#
# Retorna:
#   Caminho absoluto correspondente.
to_absolute_path() {
    local input_path="$1"

    if [[ "$input_path" == "~"* ]]; then
        input_path="${HOME}${input_path:1}"
    fi

    readlink --canonicalize "$(realpath -m "$input_path")"
}

# logo
# Mostra a logo do projeto
logo() {
    echo "Ubuntu Noble Minimal Maker (UNMM)."
    echo "Copyright (c) 2025 jppgmx. All rights reserved."
    echo "License: MIT License."
    echo "Version: ${UNMM_VERSION}"
    echo
}

boot_mode() {
    local mode="${UNMM_SYSTEM_BOOT_MODE:-bios}"
    
    if [[ $mode =~ ^(bios|uefi|hybrid)$ ]]; then
        log_error "Valor inválido para UNMM_SYSTEM_BOOT_MODE: $mode"
        log_error "Valores permitidos: bios, uefi, hybrid"
        exit 1
    fi
    
    echo "$mode"
}