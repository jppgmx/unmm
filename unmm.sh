#!/usr/bin/bash
#
#   CLI do UNMM - Ubuntu Noble Minimal Maker
#   ---------------------------------------------
#   Script principal para criação de imagens do Ubuntu Noble mínimas
#   baseado em catálogos e add-ons.
#
#   Sob licença MIT
#

if [ -z "$BASH_VERSION" ]; then
    echo "** Este script deve ser executado com bash."
    exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CATALOG_DIR="$SCRIPT_DIR/catalog"
LIB_DIR="$SCRIPT_DIR/lib"
ADDONS_DIR="$SCRIPT_DIR/addons"
ASSETS_DIR="$SCRIPT_DIR/assets"

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
    --nologo                     Alias para a opção General.NoLogo
    --mountpoint=MOUNTPOINT      Alias para a opção General.MountPoint
    -o, --output=OUTPUT_PATH     Alias para a opção General.OutputDir
    -l, --license=LICENSE        Alias para a opção General.License
    -k, --keep                   Alias para a opção General.KeepOnErrors=true
    --maximum-size=SIZE          Alias para a opção Image.MaximumSize (ex: 10G, 500M)
    -f, --format=FORMAT          Alias para as opções Export.Type e Export.Subtype
    -b, --boot-mode=MODE         Alias para a opção System.BootMode (bios, uefi, hybrid)
    -n, --hostname=HOSTNAME      Alias para a opção System.Hostname
    -u, --username=USERNAME      Alias para a opção System.User
    -p, --password=PASSWORD      Alias para a opção System.Password
    -opt, --option KEY=VALUE     Alias para a opção um override direto (formato: Secao.Subsecao.Chave=Valor)
    -v, --verbose                Alias para a opção Lib.Logging.Verbose=true
    --display-vars               Mostra as variáveis da configuração processadas, ativa modo verboso e sai
    <catalog>                    Nome do catálogo a ser usado (padrão: base)
    [addon1 addon2 ...]          Lista de add-ons a serem aplicados após o catálogo

Notas:
  - O script deve ser executado com privilégios de superusuário (root).
  - Certifique-se de ter espaço suficiente em disco para a criação da imagem.
  - Os catálogos e add-ons disponíveis podem ser listados usando a opção --list.
  - As opções de CLI sobrescrevem valores do arquivo unmm.conf, 
    consulte o arquivo de configuração para mais detalhes sobre as opções disponíveis.
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

# Fazer sourcing dos essenciais
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh" || (echo "Falha ao tentar source common.sh"; exit 1)
# shellcheck source=lib/logging.sh
source "$LIB_DIR/logging.sh" || (echo "Falha ao tentar source logging.sh"; exit 1)
# shellcheck source=lib/runner.sh
source "$LIB_DIR/runner.sh" || (echo "Falha ao tentar source runner.sh"; exit 1)

# shellcheck source=defaults
source "$SCRIPT_DIR/defaults" || (echo "Falha ao tentar source defaults"; exit 1)
# shellcheck source=lib/config/system
with_config system
# shellcheck source=lib/config/export
with_config export export.ova
CATALOG="base"
ADDONS=()
DISPLAY_VARS=false
declare -a SET_LIST=()

# Processamento dos argumentos
while [[ $# -ne 0 ]]; do
    case "$1" in
        -h|--help)
            help
            exit 0
            ;;
        --list)
            runner_list_available "$CATALOG_DIR" "$ADDONS_DIR"
            exit 0
            ;;
        --nologo)
            SET_LIST+=("General.NoLogo=true")
            shift
            ;;
        --mountpoint=*)
            SET_LIST+=("General.MountPoint=${1#*=}")
            shift
            ;;
        -o|--output=*)
            if [[ "$1" == -o ]]; then
                shift
                OUTPUT_PATH="$1"
                shift
            else
                OUTPUT_PATH="${1#*=}"
                shift
            fi

            OUTPUT_PATH=$(to_absolute_path "$OUTPUT_PATH")
            SET_LIST+=("General.OutputDir=$OUTPUT_PATH")
            ;;
        -l|--license=*)
            if [[ "$1" == -l ]]; then
                shift
                LICENSE_FILE="$1"
                shift
            else
                LICENSE_FILE="${1#*=}"
                shift
            fi
            SET_LIST+=("General.License=$LICENSE_FILE")
            ;;
        -k|--keep)
            SET_LIST+=("General.KeepOnErrors=true")
            shift
            ;;
        --maximum-size=*)
            SET_LIST+=("Lib.DiskPart.MaximumSize=${1#*=}")
            shift
            ;;
        -f|--format=*)
            if [[ "$1" == -f ]]; then
                shift
                FORMAT_RAW="$1"
            else
                FORMAT_RAW="${1#*=}"
            fi

            IFS=',' read -r -a format_parts <<< "$FORMAT_RAW"
            if [[ ${#format_parts[@]} -eq 0 ]]; then
                log_error "Formato inválido para a opção -f|--format. \
                           Espera-se algo como tipo,subtipo. Consulte unmm.conf para mais informações."
                exit 1
            fi
            
            FORMAT_TYPE="${format_parts[0]}"
            FORMAT_SUBTYPE="${format_parts[1]:-}"

            SET_LIST+=("Export.Type=$FORMAT_TYPE")
            if [[ -n "$FORMAT_SUBTYPE" ]]; then
                SET_LIST+=("Export.Subtype=$FORMAT_SUBTYPE")
            fi

            shift
            ;;
        -b|--boot-mode=*)
            if [[ "$1" == -b ]]; then
                shift
                BOOT_MODE="$1"
                shift
            else
                BOOT_MODE="${1#*=}"
                shift
            fi
            SET_LIST+=("System.BootMode=$BOOT_MODE")
            ;;
        -n|--hostname=*)
            if [[ "$1" == -n ]]; then
                shift
                HOSTNAME="$1"
                shift
            else
                HOSTNAME="${1#*=}"
                shift
            fi
            SET_LIST+=("System.Hostname=$HOSTNAME")
            ;;
        -u|--username=*)
            if [[ "$1" == -u ]]; then
                shift
                USERNAME="$1"
                shift
            else
                USERNAME="${1#*=}"
                shift
            fi
            SET_LIST+=("System.User=$USERNAME")
            ;;
        -p|--password=*)
            if [[ "$1" == -p ]]; then
                shift
                PASSWORD="$1"
                shift
            else
                PASSWORD="${1#*=}"
                shift
            fi
            SET_LIST+=("System.Password=$PASSWORD")
            ;;
        -v|--verbose)
            SET_LIST+=("Lib.Logging.Verbose=true")
            shift
            ;;
        -opt|--option)
            SET_LIST+=("$2")
            shift 2
            ;;
        --display-vars)
            DISPLAY_VARS=true
            SET_LIST+=("Lib.Logging.Verbose=true")
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
            ADDONS+=("$@")
            break
            ;;
    esac
done

load_config "$SCRIPT_DIR/unmm.conf" "${SET_LIST[@]}"

if [[ "$(export_type)" == "ova" ]]; then
    CREATE_OVA=true
else
    CREATE_OVA=false
fi

runner_execute() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "** Script deve ser executado como superusuário."
        exit 1
    fi

    if [[ "$UNMM_GENERAL_NO_LOGO" != true ]]; then
        logo
    fi

    MOUNTPOINT="$UNMM_GENERAL_MOUNT_POINT"
    MAXIMUM_SIZE="$UNMM_LIB_DISKPART_MAXIMUM_SIZE"
    OUTPUT_PATH="$UNMM_GENERAL_OUTPUT_DIR"
    BOOT_MODE="$UNMM_SYSTEM_BOOT_MODE"
    HOSTNAME="$UNMM_SYSTEM_HOSTNAME"
    USERNAME="$UNMM_SYSTEM_USER"
    PASSWORD="$UNMM_SYSTEM_PASSWORD"
    LICENSE_FILE="$UNMM_GENERAL_LICENSE"
    ENABLE_VERBOSE="${UNMM_LIB_LOGGING_VERBOSE:-false}"
    KEEP_ON_FAILURE="$UNMM_GENERAL_KEEP_ON_ERRORS"

    if [[ "$DISPLAY_VARS" == true ]]; then
        log_info "Exibindo valores atuais das variáveis de configuração processadas:"
    fi
    log_verbose "Parâmetros de configuração:"
    if [[ "$DISPLAY_VARS" == true || "$ENABLE_VERBOSE" == true ]]; then

        declare | grep -E "^UNMM_.*=" | while read -r line; do
            var_name=$(echo "$line" | cut -d= -f1)
            var_value=$(echo "$line" | cut -d= -f2-)
            if [[ "$var_name" == *PASSWORD* ]]; then
                var_value="[HIDDEN]"
            fi
            log_verbose "  $var_name: $var_value"
        done

        if [[ "$DISPLAY_VARS" == true ]]; then
            exit 0
        fi
    fi

    OUTPUT_PATH=$(to_absolute_path "$OUTPUT_PATH")
    if [[ ! -d "$OUTPUT_PATH" ]]; then
        mkdir -p "$OUTPUT_PATH"
    fi

    if [[ ! -f "$LICENSE_FILE" ]]; then
        log_error "O arquivo de licença especificado '$LICENSE_FILE' não existe."
        exit 1
    fi

    # shellcheck source=lib/depends.sh
    source "$LIB_DIR/depends.sh" || (echo "Falha ao tentar source depends.sh"; exit 1)
    # shellcheck source=lib/uc.sh
    source "$LIB_DIR/uc.sh" || (echo "Falha ao tentar source uc.sh"; exit 1)
    # shellcheck source=lib/diskpart.sh
    source "$LIB_DIR/diskpart.sh" || (echo "Falha ao tentar source diskpart.sh"; exit 1)
    # shellcheck source=lib/chroot.sh
    source "$LIB_DIR/chroot.sh" || (echo "Falha ao tentar source chroot.sh"; exit 1)
    # shellcheck source=lib/ova.sh
    source "$LIB_DIR/ova.sh" || (echo "Falha ao tentar source ova.sh"; exit 1)

    check_if_supports_debootstrap || exit 1
    check_dependencies || exit 1
    check_python_version || exit 1

    # shellcheck disable=SC2120
    cleanup() {
        trap - EXIT INT TERM ERR

        chroot_cleanup
        diskpart_cleanup
        if [[ $# == 0 && "$KEEP_ON_FAILURE" == false ]]; then
            log_info "Deletando imagem incompleta..."
            rm -f "$disk_image_path"
            rm -f "$OUTPUT_PATH/$HOSTNAME.vmdk"
            rm -f "$OUTPUT_PATH/$HOSTNAME.ovf"
            rm -f "$OUTPUT_PATH/$HOSTNAME.mf"
            rm -f "$OUTPUT_PATH/$HOSTNAME.ova"
        fi
    }

    log_verbose "Registrando trap para limpeza em EXIT, INT, TERM e ERR..."
    trap cleanup EXIT INT TERM ERR

    log_info "Iniciando criação da imagem com o catálogo '$CATALOG' e add-ons: ${ADDONS[*]}"
    log_verbose "Sourcing catálogo..."

    # shellcheck disable=SC1090
    source "$CATALOG_DIR/$CATALOG/install" || {
        log_error "Falha ao carregar o catálogo '$CATALOG'."
        exit 1
    }

    log_verbose "Determinando o disco a ser criado..."
    disk_image_path="$OUTPUT_PATH/$(diskpart_filename "$HOSTNAME")"
    mkdir -p "$(dirname "$disk_image_path")"

    log_info "Um novo disco será criado em $disk_image_path"

    TOTAL_SIZE=$(catalog_preferred_size)
    if enable_swap; then
        SWAP_SIZE=$(swap_size)
        log_verbose "Tamanho do swap configurado: $SWAP_SIZE"
        TOTAL_SIZE=$(uc_add "$TOTAL_SIZE" "$SWAP_SIZE" "G")
    fi
    if size_less_than "$MAXIMUM_SIZE" "$TOTAL_SIZE"; then
        log_error "O tamanho máximo especificado ($MAXIMUM_SIZE) é menor que o tamanho total necessário ($TOTAL_SIZE)."
        log_error "Considere aumentar o tamanho máximo ou escolher um catálogo diferente."
        log_warning "Por enquanto não há suporte para determinar tamanho para add-ons, então certifique-se de que \
o tamanho máximo seja suficiente para o catálogo mais os add-ons desejados."
        exit 1
    fi

    log_info "Preparando imagem de disco..."
    disk_image=$(diskpart_create_disk "$disk_image_path" "$MAXIMUM_SIZE")
    log_info "Imagem de disco criada em '$disk_image_path'."

    log_info "Criando dispositivo de blocos para a imagem de disco..."
    disk_device=$(diskpart_create_device "$disk_image")
    diskpart_track_device "$disk_device"

    IFS=':' read -r device _disk_image_path _disk_backend <<< "$disk_device"
    log_verbose "Dispositivo do diskpart é: $device"

    log_info "Formatação e particionamento do disco..."
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        diskpart_create_image_gpt_layout "$device" false
    elif [[ "$BOOT_MODE" == "bios" ]]; then
        diskpart_create_image_mbr_layout "$device"
    elif [[ "$BOOT_MODE" == "hybrid" ]]; then
        diskpart_create_image_gpt_layout "$device" true
    fi

    log_info "Instalando sistema base..."

    catalog_install "$disk_device"

    addon_count=${#ADDONS[@]}
    if [[ $addon_count -gt 0 ]]; then
        log_info "Aplicando $addon_count add-ons..."
        for addon in "${ADDONS[@]}"; do
            log_verbose "Sourcing add-on '$addon'..."

            # shellcheck disable=SC1090
            source "$ADDONS_DIR/$addon/install" || {
                log_error "Falha ao carregar o add-on '$addon'."
                exit 1
            }
            log_info "Aplicando add-on '$addon'..."

            addon_install "$disk_device"
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
        diskpart_disk_convert "$disk_image" vmdk
        ova_generate "$HOSTNAME" "$OUTPUT_PATH" "$BOOT_MODE" "$LICENSE_FILE"

        log_info "Arquivo OVA criado com sucesso em '$ova_output_path'."
    fi
}

( runner_execute )
