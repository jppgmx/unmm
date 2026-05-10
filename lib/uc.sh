#!/usr/bin/bash
#
#   UNMM Unit Calculator (unicalc.py) Wrapper
#   - Version: 1.0.0
#   - Description: Wrapper Bash para a calculadora de unidades (unicalc.py).
#
#   Sob licença MIT
#

if [[ -n "${UNMM_LIB_UC_LOADED:-}" ]]; then
    return 0
fi
UNMM_LIB_UC_LOADED=true

# _uc_repo_root
# Retorna o caminho raiz do repositório UNMM, assumindo que este script está
# localizado em lib/ dentro do repositório.
_uc_repo_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(dirname "$script_dir")"
}

# _uc_unicalc_path
# Retorna o caminho para o script unicalc.py, verificando a variável de ambiente
# UC_UNICALC_PATH ou assumindo o caminho padrão dentro do repositório.
_uc_unicalc_path() {
    if [[ -n "${UC_UNICALC_PATH:-}" ]]; then
        echo "$UC_UNICALC_PATH"
        return 0
    fi

    echo "$(_uc_repo_root)/assets/unicalc.py"
}

# _uc_exec <command> [args...]
# Executa o comando unicalc.py com os argumentos fornecidos.
#
# Argumentos:
#   command - O comando a ser executado (convert, add, subtract, multiply, divide, compare).
#   args... - Argumentos adicionais para o comando.
#
# Retorna:
#   A saída do comando unicalc.py ou um erro se o script não for encontrado ou se a execução falhar.
#   Quando executado sem erros, a saída pode ser uma string se convert/add/subtract/multiply/divide 
#   for usado, ou um código de status (0 para verdadeiro, 1 para falso) se compare for usado.

_uc_exec() {
    local unicalc_path
    unicalc_path="$(_uc_unicalc_path)"
    if [[ ! -f "$unicalc_path" ]]; then
        echo "unicalc.py não encontrado em: $unicalc_path" >&2
        return 1
    fi

    python3 "$unicalc_path" "$@"
}

# uc_convert <value> <target_unit> [variant]
# Converte um valor para a unidade alvo, opcionalmente especificando uma variante.
#
# Argumentos:
#   value - O valor a ser convertido (ex: "1 GB", "1024 MB").
#   target_unit - A unidade para a qual o valor deve ser convertido (ex: "MB", "GiB").
#   variant - (Opcional) A variante da unidade (ex: 0 para MB, 1 para M).
#
# Retorna:
#   A string resultante da conversão, ou um erro se a conversão falhar.
uc_convert() {
    _uc_exec convert "$@"
}

# uc_add <unit1> <unit2> [target_unit] [variant]
# Soma duas unidades, opcionalmente convertendo o resultado para uma unidade alvo e variante.
#
# Argumentos:
#   unit1 - A primeira unidade (ex: "1 GB").
#   unit2 - A segunda unidade (ex: "512 MB").
#   target_unit - (Opcional) A unidade para a qual o resultado deve ser convertido (ex: "MB", "GiB").
#   variant - (Opcional) A variante da unidade (ex: 0 para MB, 1 para M).
#
# Retorna:
#   A string resultante da soma, ou um erro se a operação falhar.
uc_add() {
    _uc_exec add "$@"
}

# uc_sub <unit1> <unit2> [target_unit] [variant]
# Subtrai duas unidades, opcionalmente convertendo o resultado para uma unidade alvo e variante.
#
# Argumentos:
#   unit1 - A primeira unidade (ex: "1 GB").
#   unit2 - A segunda unidade (ex: "512 MB").
#   target_unit - (Opcional) A unidade para a qual o resultado deve ser convertido (ex: "MB", "GiB").
#   variant - (Opcional) A variante da unidade (ex: 0 para MB, 1 para M).
#
# Retorna:
#   A string resultante da subtração, ou um erro se a operação falhar.
uc_sub() {
    _uc_exec subtract "$@"
}

# uc_mul <unit> <factor> [target_unit] [variant]
# Multiplica uma unidade por um fator, opcionalmente convertendo o resultado para uma unidade alvo e variante.
#
# Argumentos:
#   unit - A unidade a ser multiplicada (ex: "1 GB").
#   factor - O fator pelo qual a unidade deve ser multiplicada (ex: 2).
#   target_unit - (Opcional) A unidade para a qual o resultado deve ser convertido (ex: "MB", "GiB").
#   variant - (Opcional) A variante da unidade (ex: 0 para MB, 1 para M).
#
# Retorna:
#   A string resultante da multiplicação, ou um erro se a operação falhar.
uc_mul() {
    _uc_exec multiply "$@"
}

# uc_div <unit> <divisor> [target_unit] [variant]
# Divide uma unidade por um divisor, opcionalmente convertendo o resultado para uma unidade alvo e variante.
#
# Argumentos:
#   unit - A unidade a ser dividida (ex: "1 GB").
#   divisor - O divisor pelo qual a unidade deve ser dividida (ex: 2).
#   target_unit - (Opcional) A unidade para a qual o resultado deve ser convertido (ex: "MB", "GiB").
#   variant - (Opcional) A variante da unidade (ex: 0 para MB, 1 para M).
#
# Retorna:
#   A string resultante da divisão, ou um erro se a operação falhar
uc_div() {
    _uc_exec divide "$@"
}

# uc_compare <unit1> <unit2> <comparison>
# Compara duas unidades usando um operador de comparação (eq, ne, lt, le, gt, ge).
#
# Argumentos:
#   unit1 - A primeira unidade (ex: "1 GB").
#   unit2 - A segunda unidade (ex: "1024 MB").
#   comparison - O operador de comparação (eq, ne, lt, le, gt, ge).
#
# Retorna:
#   0 (verdadeiro) ou 1 (falso) dependendo do resultado da comparação, ou um erro se a operação falhar.
uc_compare() {
    _uc_exec compare "$@"
}
