#!/bin/bash
#
#   UNMM Logging Module
#   - Version: 1.0.0
#   - Description: Módulo de logging para UNMM.
#
#   Sob licença MIT
#

LOGFILE="/var/log/unmm.log"
ENABLE_VERBOSE=false

# colorize_marker (stdin)
# Coloriza a saída de log com base no marcador de nível detectado.
colorize_marker() {
    while IFS= read -r line; do
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
# Função genérica de logging.
#
# Argumentos:
#   tipo - Tipo da mensagem (INFO, ERROR, WARNING, VERBOSE)
#   mensagem - Mensagem a ser logada
log_message() {
    local type="$1"
    local message="$2"
    
    printf "(%s) [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$type" "$message" | tee -a "$LOGFILE" | colorize_marker >&2
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
    if [[ "$ENABLE_VERBOSE" == true ]]; then
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