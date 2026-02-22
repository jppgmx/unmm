#!/usr/bin/bash
#
# UNMM Dependencies Module
#  - Version: 1.0.0
#  - Description: Módulo de verificação de dependências para UNMM.
#
# Sob licença MIT
#

_REQUIRED_DEPENDENCIES=(
    # --- Manipulação de Disco e Imagem ---
    "qemu-img:qemu-utils"
    "wipefs:util-linux"
    "parted:parted"
    "losetup:util-linux"
    "blkid:util-linux"       # Vital para o fstab UUID
    "mkfs.ext4:e2fsprogs"
    "mkfs.vfat:dosfstools"   # Vital para partição EFI (boot moderno)

    # --- Construção do Sistema ---
    "debootstrap:debootstrap"
    "chroot:coreutils"       # Opcional, mas aceitável manter

    # --- Utilitários de Download e Empacotamento ---
    "wget:wget"
    "tar:tar"
    "awk:gawk"               # Vital para scripts de manipulação de texto
    "grep:grep"
    "sed:sed"                # Vital para substituir XML do OVF
    "sha256sum:coreutils"    # Vital para o Manifesto (.mf)

    "python3:python3"        # ovftool
)

# check_debian_based
# Verifica se o sistema operacional é baseado em Debian.
function check_debian_based() {
    local id=""
    if [ -f /etc/os-release ]; then
        id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')

        if [ -z "$id" ]; then
            local id_like

            id_like=$(grep '^ID_LIKE=' /etc/os-release | cut -d'=' -f2 | tr '[:upper:]' '[:lower:]')
            if [ -z "$id_like" ]; then
                log_error "Não foi possível determinar a distribuição a partir de /etc/os-release."
                return 1
            fi

            id="$id_like"
        fi
    else
        log_error "Arquivo /etc/os-release não encontrado. Não é possível determinar a distribuição."
        return 1
    fi

    if [[ "$id" != *"debian"* ]]; then
        log_error "Este script requer uma distribuição baseada em Debian."
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

    for dependency in "${_REQUIRED_DEPENDENCIES[@]}"; do
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
                if ! exec_logged "apt-get" update; then
                    log_error "Falha ao atualizar o índice do apt-get. Por favor, verifique sua conexão com a internet e tente novamente."
                    return 1
                fi
                if ! exec_logged "apt-get" install -y --no-install-recommends "${missing_dependencies[@]}"; then
                    log_error "Falha ao instalar algumas dependências. Por favor, instale-as manualmente."
                    return 1
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