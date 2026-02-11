"""
    UNMM OVF Tool Constants
    - Version: 1.0
    - Description: Constantes definidas pelo padrão OVF/CIM para uso no gerador.
"""

# Conforme DSP8023: ResourceType - CIM_ResourceAllocationSettingData.ResourceType
RESOURCE_TYPE = {
    "OTHER": 1,
    "COMPUTER_SYSTEM": 2,
    "PROCESSOR": 3,
    "MEMORY": 4,
    "IDE_CONTROLLER": 5,
    "PARALLEL_SCSI_HBA": 6,
    "FC_HBA": 7,
    "ISCSI_HBA": 8,
    "IB_HCA": 9,
    "ETHERNET_ADAPTER": 10,
    "OTHER_NETWORK_ADAPTER": 11,
    "IO_SLOT": 12,
    "IO_DEVICE": 13,
    "FLOPPY_DRIVE": 14,
    "CD_DRIVE": 15,
    "DVD_DRIVE": 16,
    "DISK_DRIVE": 17,
    "TAPE_DRIVE": 18,
    "STORAGE_EXTENT": 19,
    "OTHER_STORAGE_DEVICE": 20,
    "SERIAL_PORT": 21,
    "PARALLEL_PORT": 22,
    "USB_CONTROLLER": 23,
    "GRAPHICS_CONTROLLER": 24,
    "IEEE_1394_CONTROLLER": 25,
    "PARTITIONABLE_UNIT": 26,
    "BASE_PARTITIONABLE_UNIT": 27,
    "POWER": 28,
    "COOLING_CAPACITY": 29,
    "ETHERNET_SWITCH_PORT": 30,
    "LOGICAL_DISK": 31,
    "STORAGE_VOLUME": 32,
    "ETHERNET_CONNECTION": 33,
}

# Conforme DSP8023: OperatingSystemSection.OSType (Códigos de sistema operacional)
OS_TYPE = {
    "UNKNOWN": 0,
    "OTHER": 1,
    "MACOS": 2,
    "SOLARIS": 29,
    "LINUX": 36,
    "FREEBSD": 42,
    "NETBSD": 43,
    "OPENBSD": 65,
    "WINDOWS_SERVER_2003": 69,
    "WINDOWS_SERVER_2008": 76,
    "WINDOWS_7": 105,
    "WINDOWS_SERVER_2008_R2": 103,
    "CENTOS_32": 106,
    "CENTOS_64": 107,
    "ORACLE_LINUX_32": 108,
    "ORACLE_LINUX_64": 109,
    "UBUNTU_64": 101,
    "DEBIAN_64": 96,
    "RHEL_64": 80,
    "OTHER_LINUX_64": 101,
}
    
# Unidades de alocação comuns (AllocationUnits)
# Formato DMTF programático: "byte * 2^n" ou "hertz * 10^n"
ALLOCATION_UNITS = {
    "BYTES": "byte",
    "KILOBYTES": "byte * 2^10",
    "MEGABYTES": "byte * 2^20",
    "GIGABYTES": "byte * 2^30",
    "HERTZ": "hertz",
    "MEGAHERTZ": "hertz * 10^6",
    "GIGAHERTZ": "hertz * 10^9",
}
