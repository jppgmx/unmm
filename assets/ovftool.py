"""
    ovftool.py
    ==============
    Ferramenta de geração de OVF para máquinas virtuais.

    Autor: João Paulo (o Jppgmx)
    Sob licença MIT
"""

import argparse as ap

from ovftool import constants, data, factory


def main(args: ap.Namespace):
    """
    Função principal para gerar OVF.
    """

    ovf, env = factory.envelope()
    refs = factory.references(ovf, env)
    ds = factory.disk_section(ovf, env)
    ns = factory.network_section(ovf, env)

    # Referências de arquivos externos
    if args.refs:
        for ref in data.parse_datalist(args.refs, data.File):
            refs.appendChild(ref.to_xml(ovf))

    # Discos virtuais
    if args.disks:
        for disk in data.parse_datalist(args.disks, data.Disk):
            ds.appendChild(disk.to_xml(ovf))

    # Redes lógicas
    if args.networks:
        for network in data.parse_datalist(args.networks, data.Network):
            ns.appendChild(network.to_xml(ovf))

    # VirtualSystem (Content obrigatório)
    vs = factory.virtual_system(
        ovf, env,
        vs_id=args.vm_id,
        info=args.vm_info or "A virtual machine",
        name=args.vm_name
    )

    # EulaSection (licença)
    if args.license:
        license_text = args.license
        # Se for um caminho de arquivo, ler o conteúdo
        if args.license_file:
            try:
                with open(args.license, "r", encoding="utf-8") as f:
                    license_text = f.read()
            except FileNotFoundError:
                print(f"Aviso: Arquivo de licença '{args.license}' não encontrado. Usando como texto.")
        factory.eula_section(ovf, vs, license_text)

    # OperatingSystemSection
    factory.operating_system_section(
        ovf, vs,
        os_id=args.os_id,
        description=args.os_description,
        version=args.os_version
    )

    # VirtualHardwareSection
    vhs = factory.virtual_hardware_section(ovf, vs)

    # System (VSSD) - identificação do tipo de virtualização
    vssd = data.VSSD(
        instance_id="0",
        element_name="Virtual Hardware Family",
        virtual_system_identifier=args.vm_id,
        virtual_system_type=args.vs_type
    )
    vhs.appendChild(vssd.to_xml(ovf))

    # Contador de instâncias para RASD Items
    instance_counter = 1

    # CPU
    if args.cpu:
        cpu_item = data.RASD(
            instance_id=str(instance_counter),
            resource_type=constants.RESOURCE_TYPE["PROCESSOR"],
            element_name=f"{args.cpu} virtual CPU(s)",
            description="Number of Virtual CPUs",
            virtual_quantity=args.cpu
        )
        vhs.appendChild(cpu_item.to_xml(ovf))
        instance_counter += 1

    # RAM
    if args.ram:
        ram_item = data.RASD(
            instance_id=str(instance_counter),
            resource_type=constants.RESOURCE_TYPE["MEMORY"],
            element_name=f"{args.ram} MB of memory",
            description="Memory Size",
            allocation_units=constants.ALLOCATION_UNITS["MEGABYTES"],
            virtual_quantity=args.ram
        )
        vhs.appendChild(ram_item.to_xml(ovf))
        instance_counter += 1

    # Controlador IDE (se houver discos, precisamos de controlador)
    ide_instance = None
    if args.disks:
        ide_instance = str(instance_counter)
        ide_ctrl = data.RASD(
            instance_id=ide_instance,
            resource_type=constants.RESOURCE_TYPE["IDE_CONTROLLER"],
            element_name="IDE Controller",
            address="0"
        )
        vhs.appendChild(ide_ctrl.to_xml(ovf))
        instance_counter += 1

        # Adicionar referência ao disco no hardware
        for idx, disk_str in enumerate(args.disks):
            disk_data = data.parse_data(disk_str, data.Disk)
            disk_item = data.RASD(
                instance_id=str(instance_counter),
                resource_type=constants.RESOURCE_TYPE["DISK_DRIVE"],
                element_name=f"Disk {idx}",
                host_resource=f"ovf:/disk/{disk_data.disk_id}",
                parent=ide_instance,
                address_on_parent=str(idx)
            )
            vhs.appendChild(disk_item.to_xml(ovf))
            instance_counter += 1

    # NICs (interfaces de rede)
    if args.networks:
        for idx, net_str in enumerate(args.networks):
            net_data = data.parse_data(net_str, data.Network)
            nic_item = data.RASD(
                instance_id=str(instance_counter),
                resource_type=constants.RESOURCE_TYPE["ETHERNET_ADAPTER"],
                element_name=f"Ethernet adapter on {net_data.name}",
                connection=net_data.name,
                automatic_allocation=True
            )
            vhs.appendChild(nic_item.to_xml(ovf))
            instance_counter += 1

    # AnnotationSection (anotação customizada)
    if args.annotation:
        factory.annotation_section(ovf, vs, args.annotation)

    # ProductSection (informações do produto)
    if args.product or args.vendor or args.product_version:
        factory.product_section(
            ovf, vs,
            product=args.product,
            vendor=args.vendor,
            version=args.product_version,
            product_url=args.product_url,
            vendor_url=args.vendor_url
        )

    # Salvar arquivo OVF
    with open(args.output, "w", encoding="utf-8") as f:
        ovf.writexml(f, indent="", addindent="  ", newl="\n", encoding="UTF-8")
    
    print(f"OVF gerado com sucesso: {args.output}")


if __name__ == "__main__":
    parser = ap.ArgumentParser(
        description="Ferramenta de geração de OVF para máquinas virtuais.",
        formatter_class=ap.RawDescriptionHelpFormatter,
        epilog="""
Exemplos:
  python ovftool.py --vm-id myvm --cpu 2 --ram 2048 -o myvm.ovf
  python ovftool.py --vm-id server1 --vm-name "Web Server" --os-id 101 --cpu 4 --ram 4096 -o server.ovf
        """
    )

    # Argumentos obrigatórios
    parser.add_argument("--vm-id",
                        required=True,
                        help="ID único do VirtualSystem (obrigatório)")
    parser.add_argument("-o", "--output",
                        required=True,
                        help="Caminho do arquivo de saída OVF")

    # Informações da VM
    vm_group = parser.add_argument_group("Informações da VM")
    vm_group.add_argument("--vm-name",
                          help="Nome de exibição da VM")
    vm_group.add_argument("--vm-info",
                          help="Descrição da VM")
    vm_group.add_argument("--vs-type",
                          default="vmx-21",
                          help="Tipo do sistema virtual (padrão: vmx-21)")

    # Licença
    lic_group = parser.add_argument_group("Licença")
    lic_group.add_argument("--license", "-l",
                           help="Texto da licença ou caminho para arquivo de licença")
    lic_group.add_argument("--license-file",
                           action="store_true",
                           help="Indica que --license é um caminho de arquivo")

    # Sistema Operacional
    os_group = parser.add_argument_group("Sistema Operacional")
    os_group.add_argument("--os-id",
                          type=int,
                          default=36,
                          help="ID do OS (CIM OsType). Padrão: 36 (Linux)")
    os_group.add_argument("--os-description",
                          help="Descrição do OS (ex: 'Ubuntu 24.04 LTS')")
    os_group.add_argument("--os-version",
                          help="Versão do OS")

    # Hardware
    hw_group = parser.add_argument_group("Hardware")
    hw_group.add_argument("--cpu",
                          type=int,
                          default=1,
                          help="Número de vCPUs (padrão: 1)")
    hw_group.add_argument("--ram",
                          type=int,
                          default=1024,
                          help="Memória RAM em MB (padrão: 1024)")

    # Recursos
    res_group = parser.add_argument_group("Recursos")
    res_group.add_argument("-r", "--ref",
                           action="append",
                           help="Adicionar referência de arquivo. "
                                "Formato: id=<id>,href=<href>[,size=<size>]",
                           dest="refs",
                           metavar="ref")
    res_group.add_argument("-d", "--disk",
                           action="append",
                           help="Adicionar disco. "
                                "Formato: disk_id=<id>,capacity=<cap>[,file_ref=<ref>][,format=<fmt>]",
                           dest="disks",
                           metavar="disk")
    res_group.add_argument("-n", "--network",
                           action="append",
                           help="Adicionar rede. "
                                "Formato: name=<name>[,description=<desc>]",
                           dest="networks",
                           metavar="network")

    # Anotação
    ann_group = parser.add_argument_group("Anotação")
    ann_group.add_argument("--annotation", "-a",
                           help="Texto de anotação customizada para a VM")

    # Produto
    prod_group = parser.add_argument_group("Produto")
    prod_group.add_argument("--product",
                            help="Nome do produto (ex: 'Ubuntu 24.04 LTS')")
    prod_group.add_argument("--vendor",
                            help="Nome do fornecedor (ex: 'UNMM Project')")
    prod_group.add_argument("--product-version",
                            help="Versão do produto")
    prod_group.add_argument("--product-url",
                            help="URL do produto")
    prod_group.add_argument("--vendor-url",
                            help="URL do fornecedor")

    main(parser.parse_args())
