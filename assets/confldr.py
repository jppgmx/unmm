"""
    confldr.py
    ================

    Carrega e transforma arquivos do formato INI em variáveis de ambiente.
"""

import argparse as ap
import configparser as cp
import os
import re
import shlex
import sys

UNMM_ENV_PREFIX = "UNMM_"

# Às vezes, pode ser necessário mapear chaves normalizadas para nomes alternativos.
# Por exemplo, se houver uma chave como "EnableCDRom", será normalizada para
# "ENABLE_CD_ROM", mas talvez queiramos que a variável de ambiente seja "ENABLE_CDROM"
# sem o underscore extra.
ALTERNATIVE_KEY_NAME_TABLE = {
    "ENABLE_CD_ROM": "ENABLE_CDROM",
}

def err(*args, **kwargs):
    """
    Imprime mensagens de erro no stderr.
    """
    print(*args, **kwargs, file=sys.stderr)


SECTION_REGEX = r"^[A-Z][A-Za-z0-9]*(\.[A-Z0-9][A-Za-z0-9]*)*$"
def normalize_section_name(section):
    """
    Normaliza o nome da seção para o formato de variável de ambiente.
    Seção.Subseção -> SEÇÃO_SUBSEÇÃO
    """
    if not re.match(SECTION_REGEX, section):
        raise ValueError(f"Nome de seção '{section}' é inválido. " +
                         "Deve começar com letra maiúscula e conter apenas letras, " +
                         "números e pontos.")
    return section.replace(".", "_").upper()

KEY_REGEX = r"^[A-Za-z][A-Za-z0-9]*$"
PASCAL_CASE_REGEX = r"[A-Z][a-z]+|[A-Z]+(?=[A-Z][a-z])|[A-Z]+|\d+"
def normalize_key_name(key):
    """
    Normaliza o nome da chave para o formato de variável de ambiente.
    Chave -> CHAVE
    """
    if not re.match(KEY_REGEX, key):
        raise ValueError(f"Nome de chave '{key}' é inválido. " +
                         "Deve começar com uma letra e conter apenas letras e números.")

    matches = re.findall(PASCAL_CASE_REGEX, key)
    if not matches:
        raise ValueError(f"Nome de chave '{key}' não contém partes reconhecíveis em PascalCase.")

    normalized = "_".join(matches).upper()
    if normalized in ALTERNATIVE_KEY_NAME_TABLE:
        return ALTERNATIVE_KEY_NAME_TABLE[normalized]
    return normalized

def normalize_option(full_key):
    """
    Normaliza a chave completa (seção + chave) para o formato de variável de ambiente.
    Seção.Subseção.Chave -> SEÇÃO_SUBSEÇÃO_CHAVE
    """
    parts = full_key.split(".")
    if len(parts) < 2:
        raise ValueError(f"Chave completa '{full_key}' deve conter " +
                         "pelo menos uma seção e uma chave.")

    section_parts = parts[:-1]
    key_part = parts[-1]

    normalized_section = normalize_section_name(".".join(section_parts))
    normalized_key = normalize_key_name(key_part)

    return f"{normalized_section}_{normalized_key}"

def normalize_value(value):
    """
        Normaliza o valor, interpretando como uma lista se houver espaços,
        mas permitindo espaços escapados com barra invertida, ou como uma string simples.
    """
    l = []
    v = ''

    if value == '_':
        return []

    value = value.strip()
    nex = prev = ''
    quoted = False

    for i, c in enumerate(value):
        prev = value[i - 1] if i > 0 else ''
        nex = value[i + 1] if i + 1 < len(value) else ''
        if c == '"':
            # v += c
            if not quoted:
                if prev and prev != ' ':
                    raise ValueError(
                        f"Valor '{value}' contém aspas duplas não precedidas por espaço."
                        )
                quoted = True

            if not nex or nex == ' ':
                quoted = False
        elif c == ' ':
            if quoted:
                v += c
            else:
                if v:
                    l.append(v)
                    v = ''
        else:
            v += c

    if quoted:
        raise ValueError(f"Valor '{value}' contém aspas duplas não fechadas.")

    if v:
        l.append(v)

    if len(l) > 1:
        return l

    return v if len(l) == 0 else l[0]

def get_root():
    """
        Obtém a raiz do projeto, assumindo que este script está localizado 
        em "assets/confldr.py" dentro do repositório.
    """

    this_file = os.path.abspath(__file__)
    parent_dir = os.path.dirname(this_file)
    root_dir = os.path.dirname(parent_dir)

    unmm_sh = os.path.join(root_dir, "unmm.sh")
    if not os.path.isfile(unmm_sh):
        raise FileNotFoundError(f"Arquivo 'unmm.sh' não encontrado no diretório raiz '{root_dir}'.")
    return root_dir

def make_env_string(key, val, prefix=UNMM_ENV_PREFIX):
    """
    Gera a string de exportação para a variável de ambiente.
     - Se val for uma lista, gera uma declaração de array.
     - Se val for uma string, gera um comando de exportação simples.
    """

    # Expande variáveis como $scriptdir dentro dos valores
    def expand_vars(val):
        if '$scriptdir' in val:
            scriptdir = get_root()
            val = val.replace('$scriptdir', scriptdir)
        return val

    cmd = "export {}{}={}"

    if isinstance(val, list):
        val = " ".join(shlex.quote(expand_vars(str(v))) for v in val)
        cmd = "declare -a {}{}=({})"
    else:
        val = shlex.quote(expand_vars(str(val)))

    return cmd.format(prefix, key, val)

def load_ini_sources(filenames, config):
    """
    Carrega múltiplas fontes INI: "-" = stdin, else = arquivo.
    Retorna lista de fontes efetivamente carregadas.
    Lança ValueError se houver erro de parse.
    """
    loaded = []
    stdin_buffer = None

    for fname in filenames:
        if fname == "-":
            # Lê stdin uma única vez e reutiliza para múltiplos "-"
            if stdin_buffer is None:
                stdin_buffer = sys.stdin.read()
            try:
                config.read_string(stdin_buffer, source="<stdin>")
                loaded.append("<stdin>")
            except cp.Error as e:
                raise ValueError(f"Erro ao parsear stdin: {e}") from e
        else:
            # Arquivo normal
            try:
                read_files = config.read(fname)
                if read_files:
                    loaded.extend(read_files)
                else:
                    raise FileNotFoundError(f"Arquivo '{fname}' não encontrado.")
            except cp.Error as e:
                raise ValueError(f"Erro ao ler '{fname}': {e}") from e

    return loaded

def validate_sources(filenames):
    """
    Valida que todas as fontes existem (arquivos reais; "-" é sempre válido).
    """
    for fname in filenames:
        if fname != "-" and not os.path.isfile(fname):
            err(f"Arquivo de configuração '{fname}' não encontrado.")
            return False
    return True

def build_parser():
    """
        Cria o parser de argumentos para o script, definindo as opções e descrições.
    """
    parser = ap.ArgumentParser(
        description="Carrega e transforma arquivos INI em variáveis de ambiente."
        )
    parser.add_argument("config_file",
                        help="Caminho para um ou mais arquivos no formato INI a ser carregado. " \
                        "Use '-' para ler stdin.",
                        nargs="+"
                        )
    parser.add_argument("--prefix",
                        default=UNMM_ENV_PREFIX,
                        help="Prefixo para as variáveis de ambiente (padrão: UNMM_)."
                        )
    parser.add_argument("--ignore-read-errors",
                        action="store_true",
                        help="Ignora erros de leitura de arquivos INI e " \
                        "continua processando os próximos."
                        )
    parser.add_argument("-s", "--set",
                        help="Sobrescreve variáveis de ambiente específico."
                        "Pode ser usado múltiplas vezes para definir várias variáveis."
                        "Formato: CHAVE=VALOR para string ou CHAVE+=VALOR para " \
                        "criar/adicionar a uma lista.",
                        metavar="var",
                        action="append"
                        )
    return parser

def main(args):
    """
    Lê os arquivos de configuração INI, normaliza as chaves e as exporta como variáveis de ambiente.
    Suporta '-' como placeholder para stdin.
    """
    # Validar fontes (arquivos reais; '-' é sempre válido)
    if not validate_sources(args.config_file):
        return 1

    config = cp.ConfigParser()
    config.optionxform = str  # Preserva o case das chaves
    env = {}
    try:
        loaded_sources = load_ini_sources(args.config_file, config)
        if not loaded_sources:
            err("Nenhum arquivo de configuração foi carregado. Verifique os caminhos fornecidos.")
            return 1
    except ValueError as e:
        err(f"Erro ao carregar configuração: {e}")
        if not args.ignore_read_errors:
            return 1
        err("Ignorando erro e continuando.")

    for section in config.sections():
        for key, value in config.items(section):
            full_key = f"{section}.{key}"
            try:
                env_key = normalize_option(full_key)
                env[env_key] = normalize_value(value)
            except ValueError as e:
                err(f"Erro ao normalizar chave '{full_key}': {e}")
                if not args.ignore_read_errors:
                    return 1
                err("Ignorando erro e continuando com as próximas chaves.")

    if args.set and len(args.set) > 0:
        for var in args.set:
            try:
                if '+=' in var:
                    key, value = var.split('+=', 1)
                    norm_key = normalize_option(key)
                    append_value = normalize_value(value)
                    if norm_key in env:
                        if not isinstance(env[norm_key], list):
                            raise ValueError(f"Variável '{norm_key}' existe, mas não é uma lista.")
                        if isinstance(append_value, list):
                            env[norm_key].extend(append_value)
                        else:
                            env[norm_key].append(append_value)
                    else:
                        env[norm_key] = append_value \
                            if isinstance(append_value, list) \
                            else [append_value]
                elif '=' in var:
                    key, value = var.split('=', 1)
                    env[normalize_option(key)] = normalize_value(value)
                else:
                    err(f"Variável de ambiente '{var}' deve estar"
                         "no formato CHAVE=VALOR ou CHAVE+=VALOR (se lista).")
                    return 1
            except ValueError as e:
                err(f"Erro ao processar variável '{var}': {e}")
                return 1

    for key, value in env.items():
        print(make_env_string(key, value, prefix=args.prefix))

    return 0

if __name__ == "__main__":
    sys.exit(main(build_parser().parse_args()))
