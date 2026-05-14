#!/bin/bash
#
#   UNMM Logging Module
#   - Version: 1.0.0
#   - Description: Módulo de logging para UNMM.
#
#   Sob licença MIT
#

if [[ -n "${UNMM_LIB_LOGGING_LOADED:-}" ]]; then
    return 0
fi
UNMM_LIB_LOGGING_LOADED=true

_logging_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_logging_lib_dir}/common.sh"
# shellcheck source=lib/config/lib.logging
with_config lib.logging
unset _logging_lib_dir

# _colorize_marker (stdin)
# Coloriza a saída de log com base no marcador de nível detectado.
_colorize_marker() {
    while IFS= read -r line; do
        if ! can_colorize; then
            # Apenas imprime sem colorização se não for possível colorizar ou desabilitado
            echo "$line"
            continue
        fi

        local label rest

        label=$(echo "$line" | cut -d' ' -f3 | sed "s/\[\|\]//g")
        rest=$(echo "$line" | cut -d' ' -f4-)

        if [[ "$label" == "INFO" ]]; then
            local back="0"
            local fore="92"
        elif [[ "$label" == "ERROR" ]]; then
            local back="0"
            local fore="91"
        elif [[ "$label" == "WARNING" ]]; then
            local back="0"
            local fore="93"
        elif [[ "$label" == "VERBOSE" ]]; then
            local back="0"
            local fore="94"
        else
            local back="0"
            local fore="90"
        fi

        printf "[\e[%s;%sm%s\e[0m] %s\n" "$back" "$fore" "$label" "$rest"
    done
}

# log_message <tipo> <mensagem>
#  Função genérica de logging. Printa uma mensagem formatada com timestamp, tipo e conteúdo
# e envia para um fluxo de arquivo seguido para o console (stderr) com colorização de marcadores, se habilitada.
#
# Argumentos:
#   tipo - Tipo da mensagem (INFO, ERROR, WARNING, VERBOSE)
#   mensagem - Mensagem a ser logada
log_message() {
    local type="$1"
    local message="$2"
    
    local log_file_path
    log_file_path=$(log_file)
    if [[ $? -ne 0 ]]; then
        echo "--> Erro ao acessar o arquivo de log: $log_file_path" >&2
        exit 1
    fi
    printf "(%s) [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$type" "$message" | tee -a "$log_file_path" | _colorize_marker >&2
}

# log_info <mensagem>
# Loga uma mensagem de informação.
#
# Argumentos:
#   mensagem - Mensagem a ser logada
log_info() {
    if [[ $# -eq 0 ]]; then
        local message=""
    else
        local message="$1"
    fi
    
    log_message "INFO" "$message"
}

# log_error <mensagem>
# Loga uma mensagem de erro.
#
# Argumentos:
#   mensagem - Mensagem a ser logada
log_error() {
    local message="$1"
    log_message "ERROR" "$message"
}

# log_warning <mensagem>
# Loga uma mensagem de aviso.
#
# Argumentos:
#   mensagem - Mensagem a ser logada
log_warning() {
    local message="$1"
    log_message "WARNING" "$message"
}

# log_verbose <mensagem>
# Loga uma mensagem detalhada se o modo verbose estiver habilitado.
#
# Argumentos:
#   mensagem - Mensagem a ser logada
log_verbose() {
    local message="$1"
    if verbose; then
        log_message "VERBOSE" "$message"
    fi
}

# _stdout_capture (stdin) <contexto>
# Captura a saída padrão de um comando e loga como informação.
_stdout_capture() {
    while IFS= read -r line; do
        log_info "[$1] $line"
    done
}

# _stderr_capture (stdin) <contexto>
# Captura a saída de erro de um comando e loga como erro.
_stderr_capture() {
    while IFS= read -r line; do
        log_error "[$1] $line"
    done
}

_log_driver() {
    local curdir root
    curdir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    root="$(dirname "$curdir")"
    local driver="$root/assets/logdrv.py"

    if [[ ! -f "$driver" ]]; then
        log_error "Driver de logging não encontrado: $driver"
        exit 1
    fi

    echo "$driver"
}

# exec_logged <contexto> <comando...>
# Executa um comando capturando e logando sua saída padrão e de erro.
#
# Argumentos:
#   contexto - Contexto do comando (para log)
#   comando... - Comando a ser executado
#
# Retorna:
#   Código de saída do comando executado
exec_logged() {
    local context="$1"
    shift

    log_verbose "Executando comando: $*"
    "$@" \
        1> >( _stdout_capture "$context" ) \
        2> >( _stderr_capture "$context" )

    local exit_code=$?
    log_verbose "Comando '$*' finalizado com código de saída: $exit_code"

    return $exit_code
}

# exec_logged2 <contexto> <comando...>
# Atua semelhante a exec_logged, mas utiliza um driver Python para execução.
#
# Argumentos:
#   contexto - Contexto do comando (para log)
#   comando... - Comando a ser executado
#
# Retorna:
#   Código de saída do comando executado, ou sai com erro se o comando ou driver falhar.
#
# Notas:
#   Essa função foi implementada devido a um problema quando se usa exec_logged em qemu-nbd.
#   Mesmo que o qemu-nbd retorne um código de saída e permita o fluxo continuar, o process substitution (>(...))
#   usado para capturar stdout e stderr acaba bloqueando subshells pois o qemu-nbd não é fechado e os FDs
#   permanecem abertos e não emitem EOF, causando bloqueio.
#
#   Usando o driver Python, mesmo que o qemu-nbd use o stdout, stdin e stderr do processo do driver, 
#   não se ocorre bloqueio pois são os FDs do Python que é usado, atuando como intermediário.
exec_logged2() {
    local context="$1"
    shift

    log_verbose "Executando comando: $*"
    python3 "$(_log_driver)" "$@" \
        1> >( _stdout_capture "$context" ) \
        2> >( _stderr_capture "$context" )

    local exit_code=$?
    if [[ $exit_code -eq 255 ]]; then
        log_error "O driver falhou em executar o comando '$*'."
        exit 1
    fi

    log_verbose "Comando '$*' finalizado com código de saída: $exit_code"

    return $exit_code
}