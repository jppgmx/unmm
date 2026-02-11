#!/usr/bin/bash
#
#   UNMM OVA Module
#   - Version: 1.1.0
#   - Description: Módulo para criação de imagens OVA.
#
#   Sob licença MIT
#

# Caminho para o script Python ovftool.py
OVFTOOL_SCRIPT="${SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")/..}/assets/ovftool.py"

# generate_ovf <vm_name> <vmdk_file> <cpus> <ram_mb> <boot_mode> <license_file> <output_ovf>
# Gera o arquivo OVF com base nos parâmetros fornecidos usando ovftool.py.
#
# Argumentos:
#   vm_name - Nome da máquina virtual.
#   vmdk_file - Caminho para o arquivo VMDK.
#   cpus - Número de CPUs virtuais.
#   ram_mb - Quantidade de RAM em MB.
#   boot_mode - Modo de boot (bios, uefi, hybrid).
#   license_file - Caminho para o arquivo de licença.
#   output_ovf - Caminho para o arquivo OVF de saída.
generate_ovf() {
    local vm_name="$1"
    local vmdk_file="$2"
    local cpus="$3"
    local ram_mb="$4"
    local boot_mode="$5"
    local license_file="$6"
    local output_ovf="$7"

    log_info "Gerando arquivo OVF em '$output_ovf'..."

    # Determinar tipo de firmware baseado no boot_mode
    local vs_type="vmx-14"
    local firmware_info="BIOS"
    if [[ "$boot_mode" == "uefi" || "$boot_mode" == "hybrid" ]]; then
        firmware_info="EFI"
    fi

    log_verbose "Configuração da VM: Nome='$vm_name', CPUs=$cpus, RAM=${ram_mb}MB, Boot=$boot_mode"
    
    # Obter informações do VMDK
    log_verbose "Obtendo informações do arquivo VMDK..."
    local vmdk_basename vmdk_size
    vmdk_basename=$(basename "$vmdk_file")
    vmdk_size=$(stat -c%s "$vmdk_file")
    
    log_verbose "VMDK: arquivo='$vmdk_basename', tamanho=$vmdk_size bytes"
    
    # Preparar texto de anotação
    local annotation_text="Virtual machine created by UNMM (Ubuntu Noble Minimal Maker)
Boot Mode: $boot_mode
Firmware: $firmware_info
Generated: $(date '+%Y-%m-%d %H:%M:%S')"

    log_verbose "Invocando ovftool.py para gerar manifesto OVF..."
    
    # Construir comando ovftool.py
    local ovftool_cmd=(
        python3 "$OVFTOOL_SCRIPT"
        --vm-id "$vm_name"
        --vm-name "$vm_name"
        --vm-info "A virtual machine created by UNMM"
        --vs-type "$vs_type"
        --os-id 94
        --os-description "Ubuntu Linux (64-bit)"
        --cpu "$cpus"
        --ram "$ram_mb"
        -r "id=file1,href=$vmdk_basename,size=$vmdk_size"
        -d "disk_id=vmdisk1,capacity=8,capacity_allocation_units=byte * 2^30,file_ref=file1,format=http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"
        -n "name=NAT,description=The NAT network"
        --annotation "$annotation_text"
        --product "Ubuntu 24.04 LTS"
        --vendor "UNMM Project"
        --product-version "1.0.0"
        --product-url "https://ubuntu.com"
        -o "$output_ovf"
    )
    
    # Adicionar licença se disponível
    if [[ -f "$license_file" ]]; then
        log_verbose "Incluindo licença do arquivo: $license_file"
        ovftool_cmd+=(--license "$license_file" --license-file)
    fi
    
    # Executar ovftool.py
    if ! "${ovftool_cmd[@]}"; then
        log_error "Falha ao gerar o arquivo OVF com ovftool.py"
        exit 1
    fi

    log_info "Manifesto OVF gerado com sucesso em '$output_ovf'"
    log_verbose "Sistema Virtual: $vm_name, CPUs: $cpus, RAM: ${ram_mb}MB"
    log_verbose "Modo de Boot: $boot_mode, Firmware: $firmware_info"
}

# generate_manifest <ovf_file> <vmdk_file> <output_mf>
# Gera o arquivo manifesto (.mf) com os checksums SHA256 dos arquivos OVF e VMDK.
#
# Argumentos:
#   ovf_file - Caminho para o arquivo OVF.
#   vmdk_file - Caminho para o arquivo VMDK.
#   output_mf - Caminho para o arquivo manifesto de saída.
generate_manifest() {
    local ovf_file="$1"
    local vmdk_file="$2"
    local output_mf="$3"

    log_info "Gerando arquivo manifesto (.mf) em '$output_mf'..."
    log_verbose "Calculando checksums SHA256 para os arquivos..."

    local ovf_basename vmdk_basename ovf_sha256 vmdk_sha256
    ovf_basename=$(basename "$ovf_file")
    vmdk_basename=$(basename "$vmdk_file")

    log_verbose "Calculando checksum do OVF: $ovf_file"
    ovf_sha256=$(sha256sum "$ovf_file" | awk '{print $1}')
    log_verbose "SHA256($ovf_basename) = $ovf_sha256"

    log_verbose "Calculando checksum do VMDK: $vmdk_file"
    vmdk_sha256=$(sha256sum "$vmdk_file" | awk '{print $1}')
    log_verbose "SHA256($vmdk_basename) = $vmdk_sha256"

    cat > "$output_mf" <<EOF
SHA256($ovf_basename)= $ovf_sha256
SHA256($vmdk_basename)= $vmdk_sha256
EOF

    log_info "Arquivo manifesto gerado com sucesso"
    log_verbose "Manifesto contém checksums para 2 arquivos: OVF e VMDK"
}

# create_ova_package <ovf_file> <vmdk_file> <mf_file> <output_ova>
# Cria o pacote OVA a partir dos arquivos OVF, VMDK e MF.
#
# Argumentos:
#   ovf_file - Caminho para o arquivo OVF.
#   vmdk_file - Caminho para o arquivo VMDK.
#   mf_file - Caminho para o arquivo manifesto.
#   output_ova - Caminho para o arquivo OVA de saída.
create_ova_package() {
    local ovf_file="$1"
    local vmdk_file="$2"
    local mf_file="$3"
    local output_ova="$4"

    log_info "Criando pacote OVA em '$output_ova'..."
    log_verbose "Empacotando arquivos: OVF, MF e VMDK"

    local ovf_basename vmdk_basename mf_basename work_dir
    ovf_basename=$(basename "$ovf_file")
    vmdk_basename=$(basename "$vmdk_file")
    mf_basename=$(basename "$mf_file")
    work_dir=$(dirname "$ovf_file")

    log_verbose "Diretório de trabalho: $work_dir"
    log_verbose "Ordem dos arquivos no TAR: 1) $ovf_basename, 2) $mf_basename, 3) $vmdk_basename"

    # OVA = TAR sem compressão na ordem específica: OVF, MF, VMDK
    if ! exec_logged "TAR" tar -cf "$output_ova" -C "$work_dir" "$ovf_basename" "$mf_basename" "$vmdk_basename"; then
        log_error "Falha ao criar o arquivo OVA"
        exit 1
    fi

    log_info "Pacote OVA criado com sucesso"
    local ova_size
    ova_size=$(stat -c%s "$output_ova")
    log_verbose "Tamanho do OVA: $ova_size bytes ($(numfmt --to=iec-i --suffix=B "$ova_size"))"
}

# ova_generate <hostname> <output_path> <boot_mode> <license_file>
# Combina todas as etapas para gerar o arquivo OVA completo.
#
# Argumentos:
#   hostname - Nome do host/VM.
#   output_path - Caminho do diretório de saída.
#   boot_mode - Modo de boot (bios, uefi, hybrid).
#   license_file - Caminho para o arquivo de licença.
ova_generate() {
    log_info "Iniciando processo de geração OVA..."
    
    local hostname output_path boot_mode license_file
    hostname="$1"
    output_path="$2"
    boot_mode="$3"
    license_file="$4"

    # Parâmetros padrão para a VM
    local vm_name="$hostname"
    local cpus="2"
    local ram_mb="2048"
    local boot_mode="$boot_mode"
    local vmdk_file="$output_path/$hostname.vmdk"
    local license_file="$license_file"
    
    log_verbose "Configuração da VM OVA:"
    log_verbose "  Nome: $vm_name"
    log_verbose "  CPUs: $cpus"
    log_verbose "  RAM: ${ram_mb}MB"
    log_verbose "  Boot Mode: $boot_mode"
    log_verbose "  VMDK: $vmdk_file"
    log_verbose "  Licença: $license_file"
    
    # Arquivos de saída
    local ovf_file="$output_path/$hostname.ovf"
    local mf_file="$output_path/$hostname.mf"
    local ova_file="$output_path/$hostname.ova"
    
    log_verbose "Arquivos de saída:"
    log_verbose "  OVF: $ovf_file"
    log_verbose "  MF: $mf_file"
    log_verbose "  OVA: $ova_file"

    # Verificar se VMDK existe
    if [ ! -f "$vmdk_file" ]; then
        log_error "Arquivo VMDK não encontrado: $vmdk_file"
        exit 1
    fi
    log_verbose "VMDK verificado: $(stat -c%s "$vmdk_file") bytes"

    # Gerar OVF
    generate_ovf "$vm_name" "$vmdk_file" "$cpus" "$ram_mb" "$boot_mode" "$license_file" "$ovf_file"
    
    # Gerar Manifesto
    generate_manifest "$ovf_file" "$vmdk_file" "$mf_file"
    
    # Criar pacote OVA
    create_ova_package "$ovf_file" "$vmdk_file" "$mf_file" "$ova_file"
    
    log_info "Processo de geração OVA concluído com sucesso"
    log_info "Arquivo OVA disponível em: $ova_file"
    
    # Limpeza dos arquivos intermediários (opcional)
    log_verbose "Mantendo arquivos intermediários para referência: OVF, MF, VMDK"
}
