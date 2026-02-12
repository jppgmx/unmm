"""
    UNMM OVF Tool Data
    - Version: 1.0
    - Description: Módulo que provê os tipos de dados do manifesto OVF.
"""

from abc import abstractmethod

from dataclasses import dataclass, fields, MISSING
from typing import TypeVar
from xml.dom import minidom as md

XMLNS_OVF = "http://schemas.dmtf.org/ovf/envelope/1"
XMLNS_VSSD = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
XMLNS_RASD = "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
XMLNS_CIM = "http://schemas.dmtf.org/wbem/wscim/1/common"

class OVFData:
    """
        Classe base para todos os tipos de dados OVF.
    """

    @abstractmethod
    def to_xml(self, ovf_doc: md.Document) -> md.Element:
        """
            Converte a instância do tipo de dado em um elemento XML.
        """

    def __str__(self) -> str:
        return md.parseString(self.to_xml(md.Document()).toxml()).toprettyxml(indent="  ")

    def _ensure_ovf_namespace(self, ovf_doc: md.Document):
        """
            Garante que o namespace OVF esteja presente no documento XML.
        """
        root = ovf_doc.documentElement
        if not root.hasAttribute("xmlns:ovf"):
            root.setAttribute("xmlns:ovf", XMLNS_OVF)

@dataclass
class File(OVFData):
    """
        Representa o elemento File no OVF.
    """

    id: str
    href: str
    size: int = None
    compression: str = None
    chunk_size: int = None

    def to_xml(self, ovf_doc: md.Document) -> md.Element:
        self._ensure_ovf_namespace(ovf_doc)
        file_elem = ovf_doc.createElement("ovf:File")
        file_elem.setAttribute("ovf:id", self.id)
        file_elem.setAttribute("ovf:href", self.href)
        if self.size is not None:
            file_elem.setAttribute("ovf:size", str(self.size))
        if self.compression is not None:
            file_elem.setAttribute("ovf:compression", self.compression)
        if self.chunk_size is not None:
            file_elem.setAttribute("ovf:chunkSize", str(self.chunk_size))
        return file_elem

@dataclass
class Disk(OVFData):
    """
    Representa o elemento Disk no OVF (VirtualDiskDesc_Type).
    """
    disk_id: str
    capacity: str
    file_ref: str = None
    capacity_allocation_units: str = "byte"
    format: str = None
    populated_size: int = None
    parent_ref: str = None

    def to_xml(self, ovf_doc: md.Document) -> md.Element:
        self._ensure_ovf_namespace(ovf_doc)
        disk = ovf_doc.createElement("ovf:Disk")
        disk.setAttribute("ovf:diskId", self.disk_id)
        disk.setAttribute("ovf:capacity", self.capacity)
        if self.file_ref is not None:
            disk.setAttribute("ovf:fileRef", self.file_ref)
        if self.capacity_allocation_units != "byte":
            disk.setAttribute("ovf:capacityAllocationUnits", self.capacity_allocation_units)
        if self.format is not None:
            disk.setAttribute("ovf:format", self.format)
        if self.populated_size is not None:
            disk.setAttribute("ovf:populatedSize", str(self.populated_size))
        if self.parent_ref is not None:
            disk.setAttribute("ovf:parentRef", self.parent_ref)
        return disk

@dataclass
class Network(OVFData):
    """
    Representa o elemento Network no OVF (dentro de NetworkSection).
    """
    name: str
    description: str = None

    def to_xml(self, ovf_doc: md.Document) -> md.Element:
        self._ensure_ovf_namespace(ovf_doc)
        network = ovf_doc.createElement("ovf:Network")
        network.setAttribute("ovf:name", self.name)
        if self.description is not None:
            desc = ovf_doc.createElement("ovf:Description")
            desc.appendChild(ovf_doc.createTextNode(self.description))
            network.appendChild(desc)
        return network


@dataclass
class VSSD(OVFData):
    """
    Representa o elemento System dentro de VirtualHardwareSection.
    Define as configurações do sistema virtual (tipo de virtualização).
    """
    instance_id: str
    element_name: str = "Virtual Hardware Family"
    virtual_system_identifier: str = None
    virtual_system_type: str = None  # Ex: "vmx-21", "virtualbox-2.2"

    def to_xml(self, ovf_doc: md.Document) -> md.Element:
        system = ovf_doc.createElement("ovf:System")

        # ElementName (obrigatório pelo CIM)
        elem_name = ovf_doc.createElement("vssd:ElementName")
        elem_name.appendChild(ovf_doc.createTextNode(self.element_name))
        system.appendChild(elem_name)

        # InstanceID (obrigatório pelo CIM)
        inst_id = ovf_doc.createElement("vssd:InstanceID")
        inst_id.appendChild(ovf_doc.createTextNode(self.instance_id))
        system.appendChild(inst_id)

        # VirtualSystemIdentifier (opcional)
        if self.virtual_system_identifier is not None:
            vs_id = ovf_doc.createElement("vssd:VirtualSystemIdentifier")
            vs_id.appendChild(ovf_doc.createTextNode(self.virtual_system_identifier))
            system.appendChild(vs_id)

        # VirtualSystemType (opcional, mas comum)
        if self.virtual_system_type is not None:
            vs_type = ovf_doc.createElement("vssd:VirtualSystemType")
            vs_type.appendChild(ovf_doc.createTextNode(self.virtual_system_type))
            system.appendChild(vs_type)

        return system

@dataclass
class RASD(OVFData):
    """
    Representa o elemento Item dentro de VirtualHardwareSection.
    Define um recurso de hardware virtual (CPU, RAM, Disco, NIC, etc).
    
    ResourceType valores comuns:
        3  = Processor
        4  = Memory
        5  = IDE Controller
        6  = SCSI Controller
        10 = Ethernet Adapter
        14 = Floppy Drive
        15 = CD Drive
        17 = Disk Drive
    """
    instance_id: str
    resource_type: int

    # Campos opcionais comuns
    element_name: str = None
    description: str = None
    allocation_units: str = None
    virtual_quantity: int = None
    reservation: int = None
    limit: int = None
    weight: int = None
    automatic_allocation: bool = None

    # Para conexões (discos/redes)
    address: str = None
    address_on_parent: str = None
    parent: str = None
    host_resource: str = None  # Ref ao disco: "ovf:/disk/diskId"
    connection: str = None     # Nome da rede lógica

    # Atributos OVF extras (conforme RASD_Type no XSD)
    required: bool = None
    configuration: str = None
    bound: str = None  # "min", "max", "normal"

    def to_xml(self, ovf_doc: md.Document) -> md.Element:
        item = ovf_doc.createElement("ovf:Item")

        # Atributos OVF (se definidos)
        if self.required is not None and not self.required:
            item.setAttribute("ovf:required", "false")
        if self.configuration is not None:
            item.setAttribute("ovf:configuration", self.configuration)
        if self.bound is not None:
            item.setAttribute("ovf:bound", self.bound)

        # Elementos RASD (ordem importa para validação)
        if self.address is not None:
            elem = ovf_doc.createElement("rasd:Address")
            elem.appendChild(ovf_doc.createTextNode(self.address))
            item.appendChild(elem)

        if self.address_on_parent is not None:
            elem = ovf_doc.createElement("rasd:AddressOnParent")
            elem.appendChild(ovf_doc.createTextNode(self.address_on_parent))
            item.appendChild(elem)

        if self.allocation_units is not None:
            elem = ovf_doc.createElement("rasd:AllocationUnits")
            elem.appendChild(ovf_doc.createTextNode(self.allocation_units))
            item.appendChild(elem)

        if self.automatic_allocation is not None:
            elem = ovf_doc.createElement("rasd:AutomaticAllocation")
            elem.appendChild(ovf_doc.createTextNode(str(self.automatic_allocation).lower()))
            item.appendChild(elem)

        if self.connection is not None:
            elem = ovf_doc.createElement("rasd:Connection")
            elem.appendChild(ovf_doc.createTextNode(self.connection))
            item.appendChild(elem)

        if self.description is not None:
            elem = ovf_doc.createElement("rasd:Description")
            elem.appendChild(ovf_doc.createTextNode(self.description))
            item.appendChild(elem)

        if self.element_name is not None:
            elem = ovf_doc.createElement("rasd:ElementName")
            elem.appendChild(ovf_doc.createTextNode(self.element_name))
            item.appendChild(elem)

        if self.host_resource is not None:
            elem = ovf_doc.createElement("rasd:HostResource")
            elem.appendChild(ovf_doc.createTextNode(self.host_resource))
            item.appendChild(elem)

        # InstanceID (obrigatório)
        elem = ovf_doc.createElement("rasd:InstanceID")
        elem.appendChild(ovf_doc.createTextNode(self.instance_id))
        item.appendChild(elem)

        if self.limit is not None:
            elem = ovf_doc.createElement("rasd:Limit")
            elem.appendChild(ovf_doc.createTextNode(str(self.limit)))
            item.appendChild(elem)

        if self.parent is not None:
            elem = ovf_doc.createElement("rasd:Parent")
            elem.appendChild(ovf_doc.createTextNode(self.parent))
            item.appendChild(elem)

        if self.reservation is not None:
            elem = ovf_doc.createElement("rasd:Reservation")
            elem.appendChild(ovf_doc.createTextNode(str(self.reservation)))
            item.appendChild(elem)

        # ResourceType (obrigatório)
        elem = ovf_doc.createElement("rasd:ResourceType")
        elem.appendChild(ovf_doc.createTextNode(str(self.resource_type)))
        item.appendChild(elem)

        if self.virtual_quantity is not None:
            elem = ovf_doc.createElement("rasd:VirtualQuantity")
            elem.appendChild(ovf_doc.createTextNode(str(self.virtual_quantity)))
            item.appendChild(elem)

        if self.weight is not None:
            elem = ovf_doc.createElement("rasd:Weight")
            elem.appendChild(ovf_doc.createTextNode(str(self.weight)))
            item.appendChild(elem)

        return item

ArgDict = dict[str, str]
AnyOVFData = TypeVar('AnyOVFData', bound=OVFData)

def parse_dict(dstr: str) -> ArgDict:
    """
        Converte uma string de formato chave1=valor1,chave2=valor2,...,chaveN=valorN em
        um dicionário de strings.
    """

    result = {}
    if not dstr:
        return result

    pairs = dstr.split(',')
    for pair in pairs:
        if '=' not in pair:
            raise ValueError(
                f"Par inválido no mapeamento: '{pair}'. Deve estar no formato chave=valor."
                )
        key, value = pair.split('=', 1)
        result[key.strip()] = value.strip()

    return result

def parse_data(dstr: str, data_cls: type[AnyOVFData]) -> AnyOVFData:
    """
        Converte uma string de formato chave1=valor1,chave2=valor2,...,chaveN=valorN em
        uma instância do tipo de dado OVF especificado.
    """

    params = parse_dict(dstr)
    dfds = fields(data_cls)
    fd_names = {fd.name for fd in dfds}
    for fd in dfds:
        if fd.default is MISSING and fd.name not in params:
            raise ValueError(f"Campo obrigatório '{fd.name}' ausente na string de dados.")

        if fd.name in params:
            field_type = fd.type
            value_str = params[fd.name]
            try:
                if field_type == int:
                    params[fd.name] = int(value_str)
                elif field_type == str:
                    params[fd.name] = value_str
                else:
                    raise ValueError(f"Tipo de campo '{field_type}' não suportado para '{fd.name}'.")
            except ValueError as e:
                raise ValueError(f"Valor inválido para campo '{fd.name}': {e}") from e

    for key in params:
        if key not in fd_names:
            raise ValueError(f"Campo desconhecido '{key}' na string de dados para {data_cls.__name__}.")

    return data_cls(**params)

def parse_datalist(dstrs: list[str], data_cls: type[AnyOVFData]) -> list[AnyOVFData]:
    """
        Converte uma lista de strings de formato chave1=valor1,chave2=valor2,...,chaveN=valorN em
        uma lista de instâncias do tipo de dado OVF especificado.
    """

    result = []
    for dstr in dstrs:
        data_instance = parse_data(dstr, data_cls)
        result.append(data_instance)
    return result
