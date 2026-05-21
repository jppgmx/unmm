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

# join_by <delimiter> (stdin) <item1> [item2...]
# Une múltiplos itens em uma única string separados por um delimitador.
#
# Argumentos:
#   delimiter - Caractere ou string usada como separador entre itens
#   item1... - Um ou mais itens a serem unidos
#
# Retorna:
#   - echo: String com itens separados pelo delimitador
#
# Exemplos:
#   join_by "," foo bar baz -> foo,bar,baz
#   join_by ":" path1 path2 -> path1:path2
function join_by { local IFS="$1"; shift; echo "$*"; }

_common_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_common_config_lib_dir="${_common_lib_dir}/config"
# shellcheck source=lib/uc.sh
source "${_common_lib_dir}/uc.sh"

# with_config <modulo1> [modulo2...]
# Carrega módulos de configuração INI via source, resolvendo caminhos absolutos, relativos ou do lib/config/.
# Exporta variáveis de ambiente baseadas no arquivo INI carregado.
#
# Argumentos:
#   modulo1... - Nome do módulo (em lib/config/), caminho relativo ou caminho absoluto
#
# Retorna:
#   - return: 0 se todos os módulos foram carregados com sucesso
#   - return: 1 se algum arquivo de configuração não foi encontrado
#
# Erros:
#   - Sai com retorno 1 se módulo não encontrado (msg: "Módulo de configuração não encontrado")
#
# Variáveis:
#   - Exporta variáveis de ambiente conforme definido nos arquivos INI carregados
#
# Efeitos colaterais:
#   - Modifica o ambiente shell via source de arquivos
#   - Define e exporta variáveis de configuração
with_config() {
    local config_modules=("$@")

    for config_module in "${config_modules[@]}"; do
        local config_file
        if [[ "$config_module" == /* ]]; then
            # Absolute path
            config_file="$config_module"
        elif [[ "$config_module" == ../* ]] || [[ "$config_module" == ./* ]]; then
            # Relative path: resolve against caller's directory
            local caller_dir
            caller_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
            config_file="$(cd "$caller_dir" && cd "$(dirname "$config_module")" 2>/dev/null && pwd)/$(basename "$config_module")"
        else
            # Module in lib/config/
            config_file="${_common_config_lib_dir}/${config_module}"
        fi

        if [[ ! -f "$config_file" ]]; then
            echo "Módulo de configuração não encontrado: $config_module" >&2
            return 1
        fi

        # shellcheck source=/dev/null
        source "$config_file"
    done
}

with_config general

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
# Exibe a logo e informações de versão do projeto UNMM no stdout.
#
# Argumentos:
#   Nenhum
#
# Retorna:
#   - echo: Logo, copyright, licença e versão
#   - return: 0 sempre
#
# Variáveis:
#   - UNMM_VERSION: versão do projeto (padrão: 1.0.0)
logo() {
    echo "Ubuntu Noble Minimal Maker (UNMM)."
    echo "Copyright (c) 2025 jppgmx. All rights reserved."
    echo "License: MIT License."
    echo "Version: ${UNMM_VERSION}"
    echo
}

# load_config <arquivo_config[:arquivo_config2...]> [Secao.Chave=Valor...]
# Carrega configurações INI via confldr.py e as exporta como variáveis de ambiente.
# Pode processar múltiplos arquivos (separados por ':') e aplicar sobrescritas (formato: Secao.Chave=Valor).
#
# Argumentos:
#   arquivo_config - Caminho para arquivo(s) de configuração separados por dois-pontos
#   Secao.Chave=Valor - Sobrescritas de configuração (opcional)
#
# Retorna:
#   - return: 0 se configuração foi processada com sucesso
#   - return: 1 e exit se confldr.py falhou ou arquivos inválidos
#
# Erros:
#   - Sai com exit 1 e mensagem "**Falha ao tentar source configuração processada" se source falha
#   - Sai com exit 1 e mensagem "**Falha ao processar configuração com confldr.py" se confldr retorna erro
#
# Variáveis:
#   - Exporta UNMM_* e outras variáveis conforme arquivos INI
#   - __confldr_failed: flag interna para detectar falhas do confldr
#
# Dependências:
#   - python3
#   - assets/confldr.py (script python que processa INI)
#
# Efeitos colaterais:
#   - Modifica ambiente shell via source de saída do python
#   - Exporta múltiplas variáveis de configuração
#
# Exemplos:
#   load_config "unmm.conf" -> carrega unmm.conf
#   load_config "unmm.conf:override.conf" "General.Output=/custom" -> carrega múltiplos com override
load_config() {
    local config_files="$1"
    local set_list=("${@:2}")

    local this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local confldr_script
    confldr_script=$(to_absolute_path "${this_dir}/../assets/confldr.py")

    local confldr_files=()
    IFS=':' read -ra confldr_files <<< "$config_files"

    local confldr_sets=()
    for set in "${set_list[@]}"; do
        confldr_sets+=("-s" "$set")
    done

    local __confldr_failed=false
    source <( \
        python3 "$confldr_script" "${confldr_files[@]}" "${confldr_sets[@]}" \
            || echo "export __confldr_failed=true" \
    ) || {
        echo "**Falha ao tentar source configuração processada" >&2
        exit 1
    }

    if [[ "$__confldr_failed" == "true" ]]; then
        echo "**Falha ao processar configuração com confldr.py" >&2
        exit 1
    fi
}