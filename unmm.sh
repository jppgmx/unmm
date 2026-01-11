#!/usr/bin/bash
#
#   CLI do UNMM - Ubuntu Noble Minimal Maker
#   ---------------------------------------------
#   Script principal para criação de imagens do Ubuntu Noble mínimas
#   baseado em catálogos e add-ons.
#
#   Sob licença MIT
#

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CATALOG_DIR="$SCRIPT_DIR/catalog"
LIB_DIR="$SCRIPT_DIR/lib"
ADDONS_DIR="$SCRIPT_DIR/addons"
ASSETS_DIR="$SCRIPT_DIR/assets"

if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh" || exit 1
# shellcheck source=lib/logging.sh
source "$LIB_DIR/logging.sh" || exit 1
# shellcheck source=lib/depends.sh
source "$LIB_DIR/depends.sh" || exit 1
# shellcheck source=lib/diskpart.sh
source "$LIB_DIR/diskpart.sh" || exit 1
# shellcheck source=lib/chroot.sh
source "$LIB_DIR/chroot.sh" || exit 1
# shellcheck source=lib/ova.sh
source "$LIB_DIR/ova.sh" || exit 1

check_debian_based || exit 1
check_dependencies || exit 1

# shellcheck disable=SC2120
cleanup() {
    # Geralmente o trap não passa argumentos, mas se passar, o primeiro argumento
    # indica que o cleanup foi chamado manualmente e não pelo trap.
    if [[ $# -gt 0 ]]; then
        local unregister=$0
        if [[ "$unregister" == true ]]; then
            trap - EXIT INT TERM ERR
        fi
    fi

    chroot_cleanup
    diskpart_free_all_loop_devices
    if [[ $# == 0 ]]; then
        log_info "Deletando imagem incompleta..."
        rm -f "$disk_image_path"
        rm -f "$OUTPUT_PATH/$HOSTNAME.vmdk"
        rm -f "$OUTPUT_PATH/$HOSTNAME.ovf"
        rm -f "$OUTPUT_PATH/$HOSTNAME.mf"
        rm -f "$OUTPUT_PATH/$HOSTNAME.ova"
    fi
}

# help
# Printa a mensagem de ajuda
help() {
    cat << EOF
UNMM - Ubuntu Noble Minimal Maker
Script especializado na criação de imagens do Ubuntu Noble de forma mínima baseado em catálogos e add-ons.

Uso: unmm.sh [options] [<catalog> [addon1 addon2 ...]]
Opções:
  -h, --help                   Mostra esta mensagem de ajuda e sai
  --list                       Lista todos os catálogos e add-ons disponíveis
  --create-ova                 Cria um arquivo OVA e mantém a imagem RAW
  --mountpoint=MOUNTPOINT      Especifica o ponto de montagem para a criação da imagem
  --maximum-size=SIZE          Especifica o tamanho máximo da imagem (ex: 10G, 500M)
  -o, --output=OUTPUT_PATH     Especifica o caminho do novo arquivo de imagem
  -b, --boot-mode=MODE         Especifica o modo de boot para a imagem (ex: bios, uefi, hybrid)
  -n, --hostname=HOSTNAME      Define o hostname do sistema instalado (padrão: unmm-system)
  -u, --username=USERNAME      Define o nome do usuário padrão (padrão: user)
  -p, --password=PASSWORD      Define a senha do usuário padrão (padrão: password)
  -l, --license=LICENSE        Especifica o caminho para o arquivo de licença a ser incluído
  -v, --verbose                Habilita logging verboso
  <catalog>                    Nome do catálogo a ser usado (padrão: base)
  [addon1 addon2 ...]          Lista de add-ons a serem aplicados após o catálogo

Notas:
  - O script deve ser executado com privilégios de superusuário (root).
  - Certifique-se de ter espaço suficiente em disco para a criação da imagem.
  - Os catálogos e add-ons disponíveis podem ser listados usando a opção --list.
  - O disco gerado será salvo como caminho/para/output/HOSTNAME.img
  - A ordem dos add-ons importa, pois eles serão aplicados na sequência fornecida.

Exemplo:
    # Criar uma imagem básica (usa catálogo 'base' e salva em ./output/unmm-system.img)
    sudo ./unmm.sh

    # Criar uma imagem com múltiplos add-ons
    sudo ./unmm.sh base build-tools network-tools

    # Criar uma máquina virtual completa em formato OVA
    sudo ./unmm.sh --create-ova base lxqt

    # Personalizar hostname e usuário
    sudo ./unmm.sh -n webserver -u admin -p MyP@ssw0rd base

    # Criar imagem UEFI com tamanho específico
    sudo ./unmm.sh -b uefi --maximum-size=10G -o /tmp server

    # Criar sistema com catálogo específico e salvar em diretório customizado
    sudo ./unmm.sh -o /var/images -n database-server server

    # Modo verbose para debug e troubleshooting
    sudo ./unmm.sh --verbose -n test-system base

    # Criar imagem híbrida (BIOS + UEFI) com add-ons de segurança
    sudo ./unmm.sh -b hybrid security-suite monitoring-tools base

    # Incluir licença personalizada na imagem
    sudo ./unmm.sh -l /path/to/LICENSE.txt -n production-server base

    # Listar todos os catálogos e add-ons disponíveis
    sudo ./unmm.sh --list

Glossário:
  catálogo        Conjunto predefinido de pacotes e configurações para o sistema Ubuntu Noble. Atendendo a
                    expectativa de ser o mais mínimo possível.
  add-on          Módulo adicional que pode ser aplicado a um catálogo para estender suas funcionalidades
EOF
}

if [[ $# -eq 0 ]]; then
    help
    exit 0
fi

# Valores padrão
CREATE_OVA=false
MOUNTPOINT="/mnt/unmm"
MAXIMUM_SIZE="8G"
OUTPUT_PATH=$(to_absolute_path "./output")
BOOT_MODE="bios"
HOSTNAME="unmm-system"
USERNAME="user"
PASSWORD="password"
CATALOG="base"
LICENSE_FILE="$ASSETS_DIR/generic_LICENSE"
ENABLE_VERBOSE=false

# Processamento dos argumentos
while [[ $# -ne 0 ]]; do
    case "$1" in
        -h|--help)
            help
            exit 0
            ;;
        --list)
            log_info "Catálogos disponíveis:"
            for catalog_file in "$CATALOG_DIR"/*; do
                # shellcheck disable=SC1090
                source "$catalog_file"
                log_info " - $CATALOG_NAME: $CATALOG_DISPLAY_NAME (Versão: $CATALOG_VERSION)"
                log_info "   $CATALOG_DESCRIPTION"
                log_info
            done

            log_info "Add-ons disponíveis:"
            for addon_file in "$ADDONS_DIR"/*; do
                # shellcheck disable=SC1090
                source "$addon_file"
                log_info " - $ADDON_NAME: $ADDON_DISPLAY_NAME (Versão: $ADDON_VERSION)"
                log_info "   $ADDON_DESCRIPTION"
                log_info
            done

            exit 0
            ;;
        --create-ova)
            CREATE_OVA=true
            shift
            ;;
        --mountpoint=*)
            MOUNTPOINT="${1#*=}"
            shift
            ;;
        --maximum-size=*)
            MAXIMUM_SIZE="${1#*=}"
            shift
            ;;
        -o|--output=*)
            if [[ "$1" == -o ]]; then
                shift
                OUTPUT_PATH="$1"
                shift
                continue
            else
                OUTPUT_PATH="${1#*=}"
                shift
            fi

            OUTPUT_PATH=$(to_absolute_path "$OUTPUT_PATH")
            if [[ ! -d "$OUTPUT_PATH" ]]; then
                mkdir -p "$OUTPUT_PATH"
            fi
            ;;
        -b|--boot-mode=*)
            if [[ "$1" == -b ]]; then
                shift
                BOOT_MODE="$1"
                shift
                continue
            else
                BOOT_MODE="${1#*=}"
                shift
            fi
            ;;
        -n|--hostname=*)
            if [[ "$1" == -n ]]; then
                shift
                HOSTNAME="$1"
                shift
                continue
            else
                HOSTNAME="${1#*=}"
                shift
            fi
            ;;
        -u|--username=*)
            if [[ "$1" == -u ]]; then
                shift
                USERNAME="$1"
                shift
                continue
            else
                USERNAME="${1#*=}"
                shift
            fi
            ;;
        -p|--password=*)
            if [[ "$1" == -p ]]; then
                shift
                PASSWORD="$1"
                shift
                continue
            else
                PASSWORD="${1#*=}"
                shift
            fi
            ;;
        -l|--license=*)
            if [[ "$1" == -l ]]; then
                shift
                LICENSE_FILE="$1"
                shift
                continue
            else
                LICENSE_FILE="${1#*=}"
                shift
            fi

            if [[ ! -f "$LICENSE_FILE" ]]; then
                log_error "O arquivo de licença especificado '$LICENSE_FILE' não existe."
                exit 1
            fi
            ;;
        -v|--verbose)
            ENABLE_VERBOSE=true
            shift
            ;;
        -*)
            log_error "Opção desconhecida: $1"
            help
            exit 1
            ;;
        *)
            CATALOG="$1"
            shift
            ADDONS=("$@")
            break
            ;;
    esac
done

trap cleanup EXIT INT TERM ERR

log_verbose "Parâmetros de configuração:"
log_verbose "  CREATE_OVA: $CREATE_OVA"
log_verbose "  MOUNTPOINT: $MOUNTPOINT"
log_verbose "  MAXIMUM_SIZE: $MAXIMUM_SIZE"
log_verbose "  OUTPUT_PATH: $OUTPUT_PATH"
log_verbose "  BOOT_MODE: $BOOT_MODE"
log_verbose "  HOSTNAME: $HOSTNAME"
log_verbose "  USERNAME: $USERNAME"
log_verbose "  PASSWORD: [HIDDEN]"
log_verbose "  CATALOG: $CATALOG"
log_verbose "  ADDONS: ${ADDONS[*]}"

log_info "Iniciando criação da imagem com o catálogo '$CATALOG' e add-ons: ${ADDONS[*]}"
log_verbose "Sourcing catálogo..."

# shellcheck disable=SC1090
source "$CATALOG_DIR/$CATALOG" || {
    log_error "Falha ao carregar o catálogo '$CATALOG'."
    exit 1
}

disk_image_path=$(to_absolute_path "$OUTPUT_PATH/$HOSTNAME.img")
mkdir -p "$(dirname "$disk_image_path")"

if size_less_than "$MAXIMUM_SIZE" "$CATALOG_PREFFERED_SIZE"; then
    log_error "O tamanho máximo especificado ($MAXIMUM_SIZE) é menor que o tamanho preferido do catálogo ($CATALOG_PREFFERED_SIZE)."
    log_error "Considere aumentar o tamanho máximo ou escolher um catálogo diferente."
    exit 1
fi

log_info "Preparando imagem de disco..."
diskpart_create_raw_disk "$disk_image_path" "$MAXIMUM_SIZE"
log_info "Imagem de disco criada em '$disk_image_path'."

device=$(diskpart_setup_loop_device "$disk_image_path")
log_verbose "Dispositivo loop é: $device"
diskpart_track_loop_device "$device"

log_info "Formatação e particionamento do disco..."
if [[ "$BOOT_MODE" == "uefi" ]]; then
    diskpart_create_image_gpt_layout "$device" false
elif [[ "$BOOT_MODE" == "bios" ]]; then
    diskpart_create_image_mbr_layout "$device"
elif [[ "$BOOT_MODE" == "hybrid" ]]; then
    diskpart_create_image_gpt_layout "$device" true
fi

log_info "Instalando sistema base..."

export CATALOG_INSTALL_ARG_MOUNTPOINT="$MOUNTPOINT"
export CATALOG_INSTALL_ARG_HOSTNAME="$HOSTNAME"
export CATALOG_INSTALL_ARG_USERNAME="$USERNAME"
export CATALOG_INSTALL_ARG_PASSWORD="$PASSWORD"
export CATALOG_INSTALL_ARG_DEVICE="$device"
export CATALOG_INSTALL_ARG_BOOTMODE="$BOOT_MODE"
export CATALOG_INSTALL_ARG_DISKIMAGEPATH="$disk_image_path"
CATALOG_INSTALL_ARG_SIZE=$(stat -c %s "$disk_image_path")
export CATALOG_INSTALL_ARG_SIZE
catalog_install

unset CATALOG_INSTALL_ARG_MOUNTPOINT
unset CATALOG_INSTALL_ARG_HOSTNAME
unset CATALOG_INSTALL_ARG_USERNAME
unset CATALOG_INSTALL_ARG_PASSWORD
unset CATALOG_INSTALL_ARG_DEVICE
unset CATALOG_INSTALL_ARG_BOOTMODE
unset CATALOG_INSTALL_ARG_DISKIMAGEPATH
unset CATALOG_INSTALL_ARG_SIZE

addon_count=${#ADDONS[@]}
if [[ $addon_count -gt 0 ]]; then
    log_info "Aplicando $addon_count add-ons..."
    for addon in "${ADDONS[@]}"; do
        log_verbose "Sourcing add-on '$addon'..."

        # shellcheck disable=SC1090
        source "$ADDONS_DIR/$addon" || {
            log_error "Falha ao carregar o add-on '$addon'."
            exit 1
        }
        log_info "Aplicando add-on '$addon'..."

        export ADDON_INSTALL_ARG_MOUNTPOINT="$MOUNTPOINT"
        export ADDON_INSTALL_ARG_HOSTNAME="$HOSTNAME"
        export ADDON_INSTALL_ARG_USERNAME="$USERNAME"
        export ADDON_INSTALL_ARG_PASSWORD="$PASSWORD"
        export ADDON_INSTALL_ARG_DEVICE="$device"
        export ADDON_INSTALL_ARG_BOOTMODE="$BOOT_MODE"
        export ADDON_INSTALL_ARG_DISKIMAGEPATH="$disk_image_path"
        ADDON_INSTALL_ARG_SIZE=$(stat -c %s "$disk_image_path")
        export ADDON_INSTALL_ARG_SIZE
        export ADDON_INSTALL_ARG_INSTALLED_CATALOG="$CATALOG"
        addon_install

        unset ADDON_INSTALL_ARG_MOUNTPOINT
        unset ADDON_INSTALL_ARG_HOSTNAME
        unset ADDON_INSTALL_ARG_USERNAME
        unset ADDON_INSTALL_ARG_PASSWORD
        unset ADDON_INSTALL_ARG_DEVICE
        unset ADDON_INSTALL_ARG_BOOTMODE
        unset ADDON_INSTALL_ARG_DISKIMAGEPATH
        unset ADDON_INSTALL_ARG_SIZE
        unset ADDON_INSTALL_ARG_INSTALLED_CATALOG
    done
else
    log_info "Nenhum add-on especificado. Pulando etapa de add-ons."
fi

log_info "Finalizando imagem..."
cleanup true

log_info "Imagem do Ubuntu Noble criada com sucesso em '$disk_image_path'."
if [[ "$CREATE_OVA" == true ]]; then
    ova_output_path="$OUTPUT_PATH/$HOSTNAME.ova"
    log_info "Criando arquivo OVA em '$ova_output_path'..."
    diskpart_img_to_vmdk "$disk_image_path" "$OUTPUT_PATH/$HOSTNAME.vmdk"
    ova_generate_ovf

    log_info "Arquivo OVA criado com sucesso em '$ova_output_path'."
fi