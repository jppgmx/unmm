#!/usr/bin/bash
#
#   UNMM OVA Module
#   - Version: 1.0.0
#   - Description: Módulo para criação de imagens OVA.
#
#   Sob licença MIT
#

# generate_ovf <vm_name> <vmdk_file> <cpus> <ram_mb> <boot_mode> <license_file> <output_ovf>
# Gera o arquivo OVF com base nos parâmetros fornecidos.
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

    local bios_type="bios"
    if [ "$boot_mode" == "uefi" ]; then
        bios_type="efi"
    fi

    log_verbose "Configuração da VM: Nome='$vm_name', CPUs=$cpus, RAM=${ram_mb}MB, Boot=$boot_mode"
    
    # Obter informações do VMDK
    log_verbose "Obtendo informações do arquivo VMDK..."
    local vmdk_basename vmdk_size
    vmdk_basename=$(basename "$vmdk_file")
    vmdk_size=$(stat -c%s "$vmdk_file")
    
    log_verbose "VMDK: arquivo='$vmdk_basename', tamanho=$vmdk_size bytes"
    
    # Ler licença
    log_verbose "Lendo arquivo de licença: $license_file"
    local license_content=""
    if [ -f "$license_file" ]; then
        # Remover sequência ]]> se existir (quebraria o CDATA)
        license_content=$(cat "$license_file" | sed 's/]]>/]] >/g')
        log_verbose "Licença carregada com sucesso (${#license_content} caracteres)"
    else
        log_warning "Arquivo de licença não encontrado: $license_file"
        license_content="Nenhuma licença especificada."
    fi

    log_verbose "Escrevendo manifesto OVF..."
    
    # Determinar configurações de firmware para EFI
    local firmware_config=""
    if [[ "$boot_mode" == "uefi" || "$boot_mode" == "hybrid" ]]; then
        log_verbose "Configurando firmware EFI no manifesto OVF"
        firmware_config='vmw:firmware="efi"'
    else
        log_verbose "Configurando firmware BIOS no manifesto OVF"
        firmware_config='vmw:firmware="bios"'
    fi
    
    # Preparar seção de licença se disponível
    local eula_section=""
    if [[ -n "$license_content" && "$license_content" != "Nenhuma licença especificada." ]]; then
        log_verbose "Incluindo seção EULA no manifesto OVF"
        eula_section="  <EulaSection>
    <Info>End-User License Agreement</Info>
    <License><![CDATA[$license_content]]></License>
  </EulaSection>"
    fi
    
    cat > "$output_ovf" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope vmw:buildId="build-0000000"
  xmlns="http://schemas.dmtf.org/ovf/envelope/1"
  xmlns:cim="http://schemas.dmtf.org/wbem/wscim/1/common"
  xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1"
  xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
  xmlns:vmw="http://www.vmware.com/schema/ovf"
  xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <References>
    <File ovf:href="$vmdk_basename" ovf:id="file1" ovf:size="$vmdk_size"/>
  </References>
  <DiskSection>
    <Info>Virtual disk information</Info>
    <Disk ovf:capacity="8" ovf:capacityAllocationUnits="byte * 2^30" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>
  <NetworkSection>
    <Info>The list of logical networks</Info>
    <Network ovf:name="NAT">
      <Description>The NAT network</Description>
    </Network>
  </NetworkSection>
$eula_section
  <VirtualSystem ovf:id="$vm_name">
    <Info>A virtual machine created by UNMM</Info>
    <Name>$vm_name</Name>
    <OperatingSystemSection ovf:id="94" vmw:osType="ubuntu64Guest" ${firmware_config}>
      <Info>The kind of installed guest operating system</Info>
      <Description>Ubuntu Linux (64-bit)</Description>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemIdentifier>$vm_name</vssd:VirtualSystemIdentifier>
        <vssd:VirtualSystemType>vmx-14</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
        <rasd:Description>Number of Virtual CPUs</rasd:Description>
        <rasd:ElementName>$cpus virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>$cpus</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>${ram_mb}MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>$ram_mb</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Description>SCSI Controller</rasd:Description>
        <rasd:ElementName>SCSI Controller 0</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>lsilogic</rasd:ResourceSubType>
        <rasd:ResourceType>6</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:ElementName>Hard Disk 1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>NAT</rasd:Connection>
        <rasd:Description>E1000 ethernet adapter on NAT</rasd:Description>
        <rasd:ElementName>Ethernet 1</rasd:ElementName>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:ResourceSubType>E1000</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
      </Item>
    </VirtualHardwareSection>
    <AnnotationSection>
      <Info>Custom annotation for the virtual machine</Info>
      <Annotation>Virtual machine created by UNMM (Ubuntu Noble Minimal Maker)
Boot Mode: $boot_mode
Firmware: $bios_type
Generated: $(date '+%Y-%m-%d %H:%M:%S')</Annotation>
    </AnnotationSection>
    <ProductSection>
      <Info>Product information about the virtual machine</Info>
      <Product>Ubuntu 24.04 LTS</Product>
      <Vendor>UNMM Project</Vendor>
      <Version>1.0.0</Version>
      <ProductUrl>https://ubuntu.com</ProductUrl>
    </ProductSection>
  </VirtualSystem>
</Envelope>
EOF

    log_info "Manifesto OVF gerado com sucesso em '$output_ovf'"
    log_verbose "Sistema Virtual: $vm_name, CPUs: $cpus, RAM: ${ram_mb}MB"
    log_verbose "Modo de Boot: $boot_mode, Firmware: $bios_type"
    if [[ -n "$eula_section" ]]; then
        log_verbose "Licença embutida no OVF (${#license_content} caracteres)"
    else
        log_verbose "Nenhuma licença incluída no OVF"
    fi
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
