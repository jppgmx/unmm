#!/usr/bin/bash
#
# UNMM Common Module
#  - Version: 1.0.0
#  - Description: Módulo comum para UNMM.
#
# Sob licença MIT
#

# Comando geral para instalação de pacotes via APT para CLI
export APT_GET_COMMAND="apt-get install -y --no-install-recommends -o Dpkg::Use-Pty=0"

# Source - https://stackoverflow.com/a
# Posted by Nicholas Sushkin, modified by community. See post 'Timeline' for change history
# Retrieved 2026-01-02, License - CC BY-SA 4.0

function join_by { local IFS="$1"; shift; echo "$*"; }

# m_to_bytes <size_in_mb>
# Converte megabytes para bytes.
#
# Argumentos:
#   size_in_mb - Tamanho em megabytes (ex: 512M)
#
# Retorna:
#   Tamanho em bytes.
m_to_bytes() {
    local size_in_mb="${1%M}"
    local size_in_bytes=$((size_in_mb * 1024 * 1024))
    echo "${size_in_bytes}"
}

# gb_to_bytes <size_in_gb>
# Converte gigabytes para bytes.
#
# Argumentos:
#   size_in_gb - Tamanho em gigabytes (ex: 2G)
#
# Retorna:
#   Tamanho em bytes.
gb_to_bytes() {
    local size_in_gb="${1%G}"
    local size_in_bytes=$((size_in_gb * 1024 * 1024 * 1024))
    echo "${size_in_bytes}"
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

    if [[ $size1 == *M ]]; then
        size1_bytes=$(m_to_bytes "$size1")
    elif [[ $size1 == *G ]]; then
        size1_bytes=$(gb_to_bytes "$size1")
    else
        echo "Formato de tamanho inválido: $size1" >&2
        return 2
    fi

    if [[ $size2 == *M ]]; then
        size2_bytes=$(m_to_bytes "$size2")
    elif [[ $size2 == *G ]]; then
        size2_bytes=$(gb_to_bytes "$size2")
    else
        echo "Formato de tamanho inválido: $size2" >&2
        return 2
    fi

    if (( size1_bytes < size2_bytes )); then
        return 0
    else
        return 1
    fi
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