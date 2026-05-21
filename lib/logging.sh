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
# Processa linhas de log do stdin, colorindo marcadores de nível ([INFO], [ERROR], [WARNING], [VERBOSE])
# com cores ANSI conforme o tipo. Se colorização estiver desabilitada, imprime sem cores.
#
# Retorna:
#   - echo: Linhas do stdin com códigos ANSI de cores aplicados ou sem cores
#
# Variáveis:
#   - Verifica função can_colorize() para determinar se deve colorizar
#
# STDIN/STDOUT:
#   - stdin: Linhas de log formatadas com marcadores entre colchetes
#   - stdout: Linhas com códigos ANSI (ou sem cores se desabilitado)
#
# Notas:
#   Cores: INFO=verde (92), ERROR=vermelho (91), WARNING=amarelo (93), VERBOSE=azul (94), outros=cinza (90)
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
# Função genérica de logging que imprime mensagem formatada com timestamp, tipo e conteúdo.
# A mensagem é escrita em arquivo de log e no stderr (com colorização se habilitada).
#
# Argumentos:
#   tipo - Tipo da mensagem (INFO, ERROR, WARNING, VERBOSE ou outro)
#   mensagem - Conteúdo da mensagem a ser logada
#
# Retorna:
#   - return: 0 se log foi escrito com sucesso
#   - echo: Linha formatada "(TIMESTAMP) [TIPO] mensagem"
#   - exit: 1 se log_file falha
#
# Erros:
#   - Sai com exit 1 se não conseguir acessar arquivo de log (via log_file)
#
# Variáveis:
#   - UNMM_LIB_LOGGING_LOG_FILE ou equivalente (acessada via log_file)
#
# Dependências:
#   - log_file() para obter caminho do arquivo de log
#   - _colorize_marker() para colorizar saída
#   - date, tee, printf
#
# Efeitos colaterais:
#   - Escreve em arquivo de log
#   - Imprime no stderr
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
# Loga uma mensagem de informação (tipo INFO) com timestamp.
#
# Argumentos:
#   mensagem - Texto a ser logado (pode ser vazio)
#
# Retorna:
#   - return: 0 sempre (delega a log_message)
log_info() {
    if [[ $# -eq 0 ]]; then
        local message=""
    else
        local message="$1"
    fi
    
    log_message "INFO" "$message"
}

# log_error <mensagem>
# Loga uma mensagem de erro (tipo ERROR) com timestamp, indicando condição de erro.
#
# Argumentos:
#   mensagem - Texto do erro a ser logado
#
# Retorna:
#   - return: 0 sempre (a função em si não causa saída; quem chama log_error decide o exit)
log_error() {
    local message="$1"
    log_message "ERROR" "$message"
}

# log_warning <mensagem>
# Loga uma mensagem de aviso (tipo WARNING) com timestamp, indicando situação de atenção.
#
# Argumentos:
#   mensagem - Texto do aviso a ser logado
#
# Retorna:
#   - return: 0 sempre
log_warning() {
    local message="$1"
    log_message "WARNING" "$message"
}

# log_verbose <mensagem>
# Loga uma mensagem detalhada (tipo VERBOSE) apenas se modo verbose estiver habilitado.
#
# Argumentos:
#   mensagem - Texto a ser logado
#
# Retorna:
#   - return: 0 se verbose desabilitado (sem log)
#   - return: 0 se verbose habilitado e log foi escrito
#
# Variáveis:
#   - Verificada via verbose() para determinar se deve logar
log_verbose() {
    local message="$1"
    if verbose; then
        log_message "VERBOSE" "$message"
    fi
}

# _stdout_capture (stdin) <contexto>
# Processa linhas do stdout de um comando, logando cada linha com contexto como INFO.
# Usada para capturar saída de comandos em process substitution.
#
# Argumentos:
#   contexto - String descritiva (ex: "apt-get") adicionada a cada log como [contexto]
#
# Retorna:
#   - return: 0 sempre
#
# STDIN/STDOUT:
#   - stdin: Linhas de stdout do comando capturado
#   - stdout: Nenhum (saída é enviada para log via log_info)
#
# Efeitos colaterais:
#   - Escreve em arquivo de log via log_info
_stdout_capture() {
    while IFS= read -r line; do
        log_info "[$1] $line"
    done
}

# _stderr_capture (stdin) <contexto>
# Processa linhas do stderr de um comando, logando cada linha com contexto como ERROR.
# Usada para capturar erros de comandos em process substitution.
#
# Argumentos:
#   contexto - String descritiva (ex: "apt-get") adicionada a cada log como [contexto]
#
# Retorna:
#   - return: 0 sempre
#
# STDIN/STDOUT:
#   - stdin: Linhas de stderr do comando capturado
#   - stdout: Nenhum (saída é enviada para log via log_error)
#
# Efeitos colaterais:
#   - Escreve em arquivo de log via log_error
_stderr_capture() {
    while IFS= read -r line; do
        log_error "[$1] $line"
    done
}


# _log_driver
# Retorna o caminho para o script Python logdrv.py que atua como intermediário para execução logada.
# Essencial para exec_logged2, que usa o driver para contornar problemas de bloqueio em process substitution.
#
# Argumentos:
#   Nenhum
#
# Retorna:
#   - echo: Caminho absoluto para assets/logdrv.py
#   - exit: 1 se arquivo não encontrado
#
# Erros:
#   - Sai com exit 1 e log_error se logdrv.py não existir (msg: "Driver de logging não encontrado")
#
# Dependências:
#   - realpath (para encontrar caminho do script)
#   - Arquivo assets/logdrv.py deve existir
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
# Executa um comando capturando stdout e stderr, logando cada linha com contexto.
# Usa process substitution para redirecionar saídas para as funções de captura.
#
# Argumentos:
#   contexto - Identificador para log (ex: "apt-get", "mount")
#   comando... - Comando completo a ser executado com seus argumentos
#
# Retorna:
#   - return: Código de saída do comando
#
# Dependências:
#   - _stdout_capture, _stderr_capture
#   - log_verbose
#
# Efeitos colaterais:
#   - Executa comando externo com todos os seus efeitos (instala pacotes, monta, etc)
#   - Escreve em arquivo de log
#
# Notas:
#   Process substitution (>(...)) pode bloquear em certos comandos (ex: qemu-nbd).
#   Para contornar, use exec_logged2.
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
# Executa um comando via driver Python, capturando stdout/stderr com logging.
# Alternativa a exec_logged para evitar bloqueios em process substitution.
#
# Argumentos:
#   contexto - Identificador para log (ex: "qemu-nbd", "mount")
#   comando... - Comando completo a ser executado com seus argumentos
#
# Retorna:
#   - return: Código de saída do comando (ou 0 se sucesso)
#   - exit: 1 se driver Python falha (exit code 255)
#
# Erros:
#   - Sai com exit 1 e log_error se driver retorna 255 (msg: "O driver falhou em executar...")
#
# Variáveis:
#   - _log_driver() é chamado para obter caminho do driver Python
#
# Dependências:
#   - python3
#   - assets/logdrv.py (intermediário para execução)
#   - _stdout_capture, _stderr_capture
#
# Efeitos colaterais:
#   - Executa comando externo via driver Python
#   - Escreve em arquivo de log
#
# Notas:
#   Implementada para contornar problema onde process substitution bloqueia indefinidamente
#   com comandos que não fecham seus file descriptors (ex: qemu-nbd).
#   O driver Python atua como intermediário, permitindo que o processo bash finalize.
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