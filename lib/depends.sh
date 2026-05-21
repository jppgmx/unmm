#!/usr/bin/bash
#
# UNMM Dependencies Module
#  - Version: 1.0.0
#  - Description: Módulo de verificação de dependências para UNMM.
#
# Sob licença MIT
#

if [[ -n "${UNMM_LIB_DEPENDS_LOADED:-}" ]]; then
    return 0
fi
UNMM_LIB_DEPENDS_LOADED=true

_REQUIRED_DEPENDENCIES=(
    # --- Manipulação de Disco e Imagem ---
    "wipefs:util-linux"
    "parted:parted"
    "losetup:util-linux"
    "blkid:util-linux"       # Vital para o fstab UUID
    "mkfs.ext4:e2fsprogs"
    "mkfs.vfat:dosfstools"   # Vital para partição EFI (boot moderno)

    # --- Construção do Sistema ---
    "debootstrap:debootstrap"
    "chroot:coreutils"       # Opcional, mas aceitável manter

    # --- Utilitários e Empacotamento ---
    "wget:wget"
    "tar:tar"
    "awk:gawk"               # Vital para scripts de manipulação de texto
    "grep:grep"
    "sed:sed"                # Vital para substituir XML do OVF
    "sha256sum:coreutils"    # Vital para o Manifesto (.mf)
)

# Entre distros, há variações em quais pacotes fornecem quais comandos. 
# Esta seção mapeia os comandos para os pacotes corretos em cada distro.
_DEBIAN_SPECIFIC_DEPENDENCIES=(
    "qemu-img:qemu-utils"
)

_ARCH_SPECIFIC_DEPENDENCIES=(
    "qemu-img:qemu-img"
    "python3:python"
)

_PYTHON_VERSION_REQUIRED="3.11"

# check_os
# Detecta o tipo de distribuição Linux lendo /etc/os-release e retorna identificador: "deb" ou "arch".
#
# Argumentos:
#   Nenhum
#
# Retorna:
#   - echo: "deb" para distribuições Debian-based, "arch" para Arch-based
#   - return: 0 se distribuição detectada
#   - return: 1 se /etc/os-release não existe ou distribuição não suportada
#
# Erros:
#   - log_error se /etc/os-release não encontrado
#   - log_error se distribuição não é Debian ou Arch baseado
#
# Dependências:
#   - grep, cut, tr
#   - Arquivo /etc/os-release
check_os() {
    local id_like=""
    local id=""
    if [ -f /etc/os-release ]; then
        id_like=$(grep '^ID_LIKE=' /etc/os-release | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')
        id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')
    else
        log_error "Arquivo /etc/os-release não encontrado. Não é possível determinar a distribuição."
        return 1
    fi

    case "$id:$id_like" in
        *debian*)
            echo "deb"
            return 0
            ;;
        *arch*)
            echo "arch"
            return 0
            ;;
        *)
            log_error "Distribuição não suportada. Este script requer uma distribuição baseada em Debian ou Arch Linux."
            return 1
            ;;
    esac
}

# check_if_supports_debootstrap
# Verifica se o sistema suporta debootstrap, necessário para a construção do sistema.
function check_if_supports_debootstrap() {
    local os_type
    os_type=$(check_os) || return 1
    return 0
}

# check_python_version
# Verifica se Python 3 está instalado e se a versão é >= 3.11 (conforme _PYTHON_VERSION_REQUIRED).
#
# Argumentos:
#   Nenhum
#
# Retorna:
#   - return: 0 se Python 3 >= 3.11 está instalado
#   - return: 1 se Python 3 não encontrado ou versão < 3.11
#
# Erros:
#   - log_error se python3 não encontrado (msg: "Python 3 não encontrado. Por favor, instale Python 3.11 ou superior.")
#   - log_error se versão < 3.11 (msg: "Versão do Python é X.Y.Z. Por favor, instale Python 3.11 ou superior.")
#
# Variáveis:
#   - _PYTHON_VERSION_REQUIRED (padrão: "3.11")
#
# Dependências:
#   - python3
#   - command, awk, printf, sort
check_python_version() {
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 não encontrado. Por favor, instale Python 3.11 ou superior."
        return 1
    fi

    local version
    version=$(python3 --version 2>&1 | awk '{print $2}')
    if [[ "$(printf '%s\n' "$_PYTHON_VERSION_REQUIRED" "$version" | sort -V | head -n1)" != "$_PYTHON_VERSION_REQUIRED" ]]; then
        log_error "Versão do Python é $version. Por favor, instale Python 3.11 ou superior."
        return 1
    fi

    return 0
}

# check_dependencies
# Verifica se todas as dependências necessárias estão instaladas.
# Se o script está sendo executado em um shell interativo e há dependências ausentes,
# pergunta ao usuário se deseja instalá-las automaticamente.
function check_dependencies() {
    local missing_dependencies=()
    local deps=()
    local os_type
    os_type=$(check_os) || return 1

    log_verbose "Verificando dependências para a distribuição detectada: $os_type"
    if [[ "$os_type" == "deb" ]]; then
        log_verbose "Distribuição é Debian-based."
        deps=("${_REQUIRED_DEPENDENCIES[@]}" "${_DEBIAN_SPECIFIC_DEPENDENCIES[@]}")
    elif [[ "$os_type" == "arch" ]]; then
        log_verbose "Distribuição é Arch-based."
        deps=("${_REQUIRED_DEPENDENCIES[@]}" "${_ARCH_SPECIFIC_DEPENDENCIES[@]}")
    else
        log_error "Tipo de distribuição desconhecido. Não é possível determinar dependências específicas."
        return 1
    fi

    for dependency in "${deps[@]}"; do
        local cmd="${dependency%%:*}"
        local pkg="${dependency##*:}"

        if ! command -v "$cmd" &> /dev/null; then
            missing_dependencies+=("$pkg")
        fi
    done

    if [ ${#missing_dependencies[@]} -ne 0 ]; then
        log_error "Dependências ausentes detectadas:"
        for pkg in "${missing_dependencies[@]}"; do
            echo "  - $pkg"
        done
        
        if [[ "$-" == *i* ]]; then
            log_warning "Você está executando em um shell interativo. Deseja tentar instalar as dependências agora? (s/n)"
            local response
            read -r response
            if [[ "$response" == "s" || "$response" == "S" ]]; then
                log_info "Tentando instalar dependências ausentes..."
                log_verbose "A selecionar o gerenciador de pacotes correto para a instalação..."
                if [[ "$os_type" == "deb" ]]; then
                    if ! exec_logged "apt-get" apt-get update; then
                        log_error "Falha ao atualizar o índice do apt-get. Por favor, verifique sua conexão com a internet e tente novamente."
                        return 1
                    fi
                    if ! exec_logged "apt-get" apt-get install -y --no-install-recommends "${missing_dependencies[@]}"; then
                        log_error "Falha ao instalar algumas dependências. Por favor, instale-as manualmente."
                        return 1
                    fi
                elif [[ "$os_type" == "arch" ]]; then
                    if ! exec_logged "pacman" pacman -Sy --noconfirm; then
                        log_error "Falha ao atualizar o índice do pacman. Por favor, verifique sua conexão com a internet e tente novamente."
                        return 1
                    fi
                    if ! exec_logged "pacman" pacman -S --noconfirm "${missing_dependencies[@]}"; then
                        log_error "Falha ao instalar algumas dependências. Por favor, instale-as manualmente."
                        return 1
                    fi
                fi

                log_info "Dependências instaladas com sucesso."
                return 0
            else
                log_info "Instalação de dependências cancelada pelo usuário."
                return 1
            fi
        else
            log_error "Por favor, instale as dependências acima e tente novamente."
        fi

        return 1
    fi
    return 0
}