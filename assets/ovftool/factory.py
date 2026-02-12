"""
    UNMM OVF Tool Factory
    - Version: 1.0
    - Description: Módulo que provê as funções de fábrica para criar os elementos básicos do OVF.
"""

from xml.dom import minidom as md

from ovftool.data import XMLNS_OVF, XMLNS_RASD, XMLNS_VSSD, XMLNS_CIM

def envelope() -> tuple[md.Document, md.Element]:
    """
    Inicia a criação do envelope OVF.
    Retorna o documento OVF e o elemento Envelope.
    """
    ovf = md.Document()
    env = ovf.createElement("ovf:Envelope")
    env.setAttribute("xmlns", XMLNS_OVF)
    env.setAttribute("xmlns:ovf", XMLNS_OVF)
    env.setAttribute("xmlns:cim", XMLNS_CIM)
    env.setAttribute("xmlns:vssd", XMLNS_VSSD)
    env.setAttribute("xmlns:rasd", XMLNS_RASD)
    env.setAttribute("xml:lang", "en-US")
    ovf.appendChild(env)
    return ovf, env

def references(ovf: md.Document, env: md.Element) -> md.Element:
    """
    Cria o elemento References no OVF.
    Retorna o elemento References.
    """
    refs = ovf.createElement("ovf:References")
    env.appendChild(refs)
    return refs

def disk_section(ovf: md.Document, env: md.Element) -> md.Element:
    """
    Cria a seção de metadados dos discos (DiskSection).
    Esta seção é obrigatória se houver discos na VM.
    """
    ds = ovf.createElement("ovf:DiskSection")

    # Pela norma, toda Section precisa ter um filho <Info>
    info = ovf.createElement("ovf:Info")
    info.appendChild(ovf.createTextNode("List of the virtual disks used in the package"))
    ds.appendChild(info)

    env.appendChild(ds)
    return ds


def network_section(ovf: md.Document, env: md.Element) -> md.Element:
    """
    Cria a seção de redes lógicas (NetworkSection).
    Descreve as redes lógicas usadas no pacote.
    """
    ns = ovf.createElement("ovf:NetworkSection")

    # Pela norma, toda Section precisa ter um filho <Info>
    info = ovf.createElement("ovf:Info")
    info.appendChild(ovf.createTextNode("Descriptions of logical networks used within the package"))
    ns.appendChild(info)

    env.appendChild(ns)
    return ns

def virtual_system(ovf: md.Document, env: md.Element, 
                   vs_id: str, info: str = "A virtual machine",
                   name: str = None) -> md.Element:
    """
    Cria o elemento VirtualSystem (Content obrigatório no OVF).
    
    Args:
        ovf: Documento OVF
        env: Elemento Envelope pai
        vs_id: ID único do VirtualSystem (required)
        info: Descrição do sistema virtual
        name: Nome de exibição opcional
    
    Returns:
        Elemento VirtualSystem
    """
    vs = ovf.createElement("ovf:VirtualSystem")
    vs.setAttribute("ovf:id", vs_id)
    
    # Info é obrigatório em Content_Type
    info_elem = ovf.createElement("ovf:Info")
    info_elem.appendChild(ovf.createTextNode(info))
    vs.appendChild(info_elem)
    
    # Name é opcional
    if name is not None:
        name_elem = ovf.createElement("ovf:Name")
        name_elem.appendChild(ovf.createTextNode(name))
        vs.appendChild(name_elem)
    
    env.appendChild(vs)
    return vs

def operating_system_section(ovf: md.Document, parent: md.Element,
                             os_id: int, description: str = None,
                             version: str = None,
                             info: str = "Specifies the operating system installed") -> md.Element:
    """
    Cria OperatingSystemSection dentro de um VirtualSystem.
    
    Args:
        ovf: Documento OVF
        parent: Elemento pai (VirtualSystem)
        os_id: ID do OS (CIM_OperatingSystem.OsType enumeration)
        description: Descrição do OS (ex: "Ubuntu 64-bit")
        version: Versão do OS
        info: Texto informativo da seção
    
    Returns:
        Elemento OperatingSystemSection
    """
    oss = ovf.createElement("ovf:OperatingSystemSection")
    oss.setAttribute("ovf:id", str(os_id))
    
    if version is not None:
        oss.setAttribute("ovf:version", version)
    
    # Info é obrigatório em Section_Type
    info_elem = ovf.createElement("ovf:Info")
    info_elem.appendChild(ovf.createTextNode(info))
    oss.appendChild(info_elem)
    
    # Description é opcional
    if description is not None:
        desc = ovf.createElement("ovf:Description")
        desc.appendChild(ovf.createTextNode(description))
        oss.appendChild(desc)
    
    parent.appendChild(oss)
    return oss

def virtual_hardware_section(ovf: md.Document, parent: md.Element,
                             section_id: str = None,
                             transport: str = None,
                             info: str = "Virtual hardware requirements") -> md.Element:
    """
    Cria VirtualHardwareSection dentro de um VirtualSystem.
    
    Args:
        ovf: Documento OVF
        parent: Elemento pai (VirtualSystem)
        section_id: ID opcional da seção (para múltiplas configurações)
        transport: Tipo de transporte para propriedades OVF (iso, com.vmware.guestInfo)
        info: Texto informativo da seção
    
    Returns:
        Elemento VirtualHardwareSection
    """
    vhs = ovf.createElement("ovf:VirtualHardwareSection")
    
    if section_id is not None:
        vhs.setAttribute("ovf:id", section_id)
    
    if transport is not None:
        vhs.setAttribute("ovf:transport", transport)
    
    # Info é obrigatório em Section_Type
    info_elem = ovf.createElement("ovf:Info")
    info_elem.appendChild(ovf.createTextNode(info))
    vhs.appendChild(info_elem)
    
    parent.appendChild(vhs)
    return vhs


def eula_section(ovf: md.Document, parent: md.Element,
                 license_text: str,
                 info: str = "End-User License Agreement") -> md.Element:
    """
    Cria EulaSection dentro de um VirtualSystem ou Envelope.
    
    Args:
        ovf: Documento OVF
        parent: Elemento pai (VirtualSystem ou Envelope)
        license_text: Texto da licença (obrigatório)
        info: Texto informativo da seção
    
    Returns:
        Elemento EulaSection
    """
    eula = ovf.createElement("ovf:EulaSection")
    
    # Info é obrigatório em Section_Type
    info_elem = ovf.createElement("ovf:Info")
    info_elem.appendChild(ovf.createTextNode(info))
    eula.appendChild(info_elem)
    
    # License é obrigatório em EulaSection_Type
    license_elem = ovf.createElement("ovf:License")
    license_elem.appendChild(ovf.createTextNode(license_text))
    eula.appendChild(license_elem)
    
    parent.appendChild(eula)
    return eula


def annotation_section(ovf: md.Document, parent: md.Element,
                       annotation: str,
                       info: str = "Custom annotation") -> md.Element:
    """
    Cria AnnotationSection dentro de um VirtualSystem ou Envelope.
    
    Args:
        ovf: Documento OVF
        parent: Elemento pai (VirtualSystem ou Envelope)
        annotation: Texto da anotação (obrigatório)
        info: Texto informativo da seção
    
    Returns:
        Elemento AnnotationSection
    """
    ann = ovf.createElement("ovf:AnnotationSection")
    
    # Info é obrigatório em Section_Type
    info_elem = ovf.createElement("ovf:Info")
    info_elem.appendChild(ovf.createTextNode(info))
    ann.appendChild(info_elem)
    
    # Annotation é obrigatório em AnnotationSection_Type
    ann_elem = ovf.createElement("ovf:Annotation")
    ann_elem.appendChild(ovf.createTextNode(annotation))
    ann.appendChild(ann_elem)
    
    parent.appendChild(ann)
    return ann


def product_section(ovf: md.Document, parent: md.Element,
                    product: str = None,
                    vendor: str = None,
                    version: str = None,
                    full_version: str = None,
                    product_url: str = None,
                    vendor_url: str = None,
                    info: str = "Product information") -> md.Element:
    """
    Cria ProductSection dentro de um VirtualSystem ou Envelope.
    
    Args:
        ovf: Documento OVF
        parent: Elemento pai (VirtualSystem ou Envelope)
        product: Nome do produto
        vendor: Nome do fornecedor
        version: Versão curta
        full_version: Versão completa
        product_url: URL do produto
        vendor_url: URL do fornecedor
        info: Texto informativo da seção
    
    Returns:
        Elemento ProductSection
    """
    ps = ovf.createElement("ovf:ProductSection")
    
    # Info é obrigatório em Section_Type
    info_elem = ovf.createElement("ovf:Info")
    info_elem.appendChild(ovf.createTextNode(info))
    ps.appendChild(info_elem)
    
    # Elementos opcionais
    if product is not None:
        elem = ovf.createElement("ovf:Product")
        elem.appendChild(ovf.createTextNode(product))
        ps.appendChild(elem)
    
    if vendor is not None:
        elem = ovf.createElement("ovf:Vendor")
        elem.appendChild(ovf.createTextNode(vendor))
        ps.appendChild(elem)
    
    if version is not None:
        elem = ovf.createElement("ovf:Version")
        elem.appendChild(ovf.createTextNode(version))
        ps.appendChild(elem)
    
    if full_version is not None:
        elem = ovf.createElement("ovf:FullVersion")
        elem.appendChild(ovf.createTextNode(full_version))
        ps.appendChild(elem)
    
    if product_url is not None:
        elem = ovf.createElement("ovf:ProductUrl")
        elem.appendChild(ovf.createTextNode(product_url))
        ps.appendChild(elem)
    
    if vendor_url is not None:
        elem = ovf.createElement("ovf:VendorUrl")
        elem.appendChild(ovf.createTextNode(vendor_url))
        ps.appendChild(elem)
    
    parent.appendChild(ps)
    return ps
