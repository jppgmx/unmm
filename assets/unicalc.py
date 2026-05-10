"""
    unitcalc.py
    =========================

    Calculadora de unidades de dados.
"""

import argparse as ap
import enum
import re
from decimal import Decimal
import sys

class UnitType(enum.Enum):
    """
        Tipos de unidades de dados, com seus fatores de conversão para bytes.
    """
    BYTE = Decimal("1")
    KILOBYTE = Decimal("1000")
    MEGABYTE = Decimal("1000") ** 2
    GIGABYTE = Decimal("1000") ** 3
    TERABYTE = Decimal("1000") ** 4

    BIT = Decimal("1") / Decimal("8")
    KILOBIT = Decimal("1000") / Decimal("8")
    MEGABIT = (Decimal("1000") ** 2) / Decimal("8")
    GIGABIT = (Decimal("1000") ** 3) / Decimal("8")
    TERABIT = (Decimal("1000") ** 4) / Decimal("8")

    KIBIBIT = Decimal("1024") / Decimal("8")
    MEBIBIT = (Decimal("1024") ** 2) / Decimal("8")
    GIBIBIT = (Decimal("1024") ** 3) / Decimal("8")
    TEBIBIT = (Decimal("1024") ** 4) / Decimal("8")

    KIBIBYTE = Decimal("1024")
    MEBIBYTE = Decimal("1024") ** 2
    GIBIBYTE = Decimal("1024") ** 3
    TEBIBYTE = Decimal("1024") ** 4

    def is_byte(self):
        """
            Verifica se a unidade é uma unidade de byte (em oposição a bit).
        """
        return self in {
            UnitType.BYTE,
            UnitType.KILOBYTE,
            UnitType.MEGABYTE,
            UnitType.GIGABYTE,
            UnitType.TERABYTE,
            UnitType.KIBIBYTE,
            UnitType.MEBIBYTE,
            UnitType.GIBIBYTE,
            UnitType.TEBIBYTE,
        }

    def is_bit(self):
        """
            Verifica se a unidade é uma unidade de bit (em oposição a byte).
        """
        return not self.is_byte()

UNITS_STR = [
    "B", "K", "M", "G", "T",
    "KB", "MB", "GB", "TB",
    "b", "Kb", "Mb", "Gb", "Tb",
    "Kbit", "Mbit", "Gbit", "Tbit",
    "Kib", "Mib", "Gib", "Tib",
    "KiB", "MiB", "GiB", "TiB"
]

CMP_CHOICES = ["eq", "ne", "lt", "le", "gt", "ge"]

UNIT_MAPPINGS = {
    # Aliases comuns
    "B": UnitType.BYTE,
    "K": UnitType.KILOBYTE,
    "M": UnitType.MEGABYTE,
    "G": UnitType.GIGABYTE,
    "T": UnitType.TERABYTE,

    # Familia de unidades decimais de byte
    "KB": UnitType.KILOBYTE,
    "MB": UnitType.MEGABYTE,
    "GB": UnitType.GIGABYTE,
    "TB": UnitType.TERABYTE,

    # Familia de unidades decimais de bit e aliases
    "b": UnitType.BIT,
    "Kb": UnitType.KILOBIT,
    "Mb": UnitType.MEGABIT,
    "Gb": UnitType.GIGABIT,
    "Tb": UnitType.TERABIT,

    "Kbit": UnitType.KILOBIT,
    "Mbit": UnitType.MEGABIT,
    "Gbit": UnitType.GIGABIT,
    "Tbit": UnitType.TERABIT,

    # Familia de unidades binárias de bit
    "Kib": UnitType.KIBIBIT,
    "Mib": UnitType.MEBIBIT,
    "Gib": UnitType.GIBIBIT,
    "Tib": UnitType.TEBIBIT,

    # Familia de unidades binárias de byte
    "KiB": UnitType.KIBIBYTE,
    "MiB": UnitType.MEBIBYTE,
    "GiB": UnitType.GIBIBYTE,
    "TiB": UnitType.TEBIBYTE,
}

def _normalize_unit_str(unit_str):
    """
        Normaliza a string da unidade para um formato reconhecido, tentando várias heurísticas.
    """
    unit_str = unit_str.strip()
    if unit_str in UNIT_MAPPINGS:
        return unit_str

    if len(unit_str) == 1:
        normalized = unit_str.upper()
        if normalized in UNIT_MAPPINGS:
            return normalized
        raise ValueError(f"Unidade desconhecida: {unit_str}")

    if unit_str.lower().endswith("bit"):
        prefix = unit_str[0].upper()
        normalized = f"{prefix}bit"
        if normalized in UNIT_MAPPINGS:
            return normalized
        raise ValueError(f"Unidade desconhecida: {unit_str}")

    if unit_str.lower().endswith("ib"):
        prefix = unit_str[0].upper()
        normalized = f"{prefix}ib"
        if normalized in UNIT_MAPPINGS:
            return normalized
        normalized = f"{prefix}iB"
        if normalized in UNIT_MAPPINGS:
            return normalized
        raise ValueError(f"Unidade desconhecida: {unit_str}")

    suffix = unit_str[-1]
    prefix = unit_str[0].upper()
    if suffix == "b":
        normalized = f"{prefix}b"
        if normalized in UNIT_MAPPINGS:
            return normalized
    if suffix == "B":
        normalized = f"{prefix}B"
        if normalized in UNIT_MAPPINGS:
            return normalized

    normalized = unit_str.upper()
    if normalized in UNIT_MAPPINGS:
        return normalized

    raise ValueError(f"Unidade desconhecida: {unit_str}")


def parse_unittype(unit_str):
    """
        Converte uma string de unidade para o tipo UnitType correspondente
        após tentar normalizar a string usando heurísticas para lidar com variações comuns.
    """
    normalized = _normalize_unit_str(unit_str)
    return UNIT_MAPPINGS[normalized]

def unit_type_to_str(unit_type, variant=0):
    """
        Imprime a unidade em um formato de string, usando o mapeamento reverso 
        para encontrar uma representação legível da unidade, com suporte para 
        variantes de formatação.
        (Exemplo: "GB" e "G" para gigabyte, "Mb" e "Mbit" para megabit, etc.)
    """
    mapping = {}

    for key, value in UNIT_MAPPINGS.items():
        if value == unit_type:
            if not value in mapping:
                mapping[value] = []
            mapping[value].append(key)

    if unit_type not in mapping:
        raise ValueError(f"Tipo não encontrado: {unit_type}")

    return mapping[unit_type][variant] \
        if 0 <= variant < len(mapping[unit_type]) \
        else mapping[unit_type][0]

class Unit:
    """
        Representa uma quantidade de dados com um valor numérico e um tipo de unidade,
        e fornece métodos para conversão, comparação e operações aritméticas entre unidades.
    """
    UNIT_REGEX = r"^(?P<value>\d+(\.\d+)?)(\s*)(?P<unit>[A-Za-z]+)$"

    def __init__(self, *args):
        if len(args) == 1:
            self._parse_from_string(args[0])
        elif len(args) == 2:
            self.value = Decimal(str(args[0]))
            if isinstance(args[1], str):
                unit_str = args[1]
                self.unit_type = parse_unittype(unit_str)
            elif isinstance(args[1], UnitType):
                self.unit_type = args[1]
            else:
                raise ValueError("Invalid unit type")
        else:
            raise ValueError("Invalid number of arguments")

    def is_byte(self):
        """
            Alias de UnitType.is_byte() para conveniência.
        """
        return self.unit_type.is_byte()

    def is_bit(self):
        """
            Alias de UnitType.is_bit() para conveniência.
        """
        return self.unit_type.is_bit()

    def _to_base_bytes(self):
        """
            Converte a unidade atual para bytes como base para comparação e conversão.
        """
        return self.value * self.unit_type.value

    def to(self, target_unit):
        """
            Converte uma unidade para outra unidade especificada, 
            retornando uma nova instância de Unit com o valor convertido.
        """
        if isinstance(target_unit, str):
            target_type = parse_unittype(target_unit)
        elif isinstance(target_unit, UnitType):
            target_type = target_unit
        else:
            raise ValueError("Invalid target unit type")

        if target_type == self.unit_type:
            return Unit(self.value, self.unit_type)

        # Converter para bytes como base
        base_value = self._to_base_bytes()

        # Converter para a unidade alvo
        return Unit(base_value / target_type.value, target_type)

    def __str__(self):
        return self.strvariant()

    def strvariant(self, variant=0):
        """
            Retorna a representação em string da unidade usando uma variante 
            de formatação específica conforme unit_type_to_str.
        """
        return f"{self.value}{unit_type_to_str(self.unit_type, variant)}"

    def __add__(self, other):
        if not isinstance(other, Unit):
            return NotImplemented

        other = other.to(self.unit_type)
        return Unit(self.value + other.value, self.unit_type)

    def __sub__(self, other):
        if not isinstance(other, Unit):
            return NotImplemented

        other = other.to(self.unit_type)
        return Unit(self.value - other.value, self.unit_type)

    def __mul__(self, other):
        if isinstance(other, (int, float, Decimal)):
            return Unit(self.value * Decimal(str(other)), self.unit_type)
        return NotImplemented

    def __truediv__(self, other):
        if isinstance(other, (int, float, Decimal)):
            return Unit(self.value / Decimal(str(other)), self.unit_type)
        return NotImplemented

    def __eq__(self, other):
        if not isinstance(other, Unit):
            return NotImplemented
        return self._to_base_bytes() == other._to_base_bytes()

    def __ne__(self, other):
        if not isinstance(other, Unit):
            return NotImplemented
        return self._to_base_bytes() != other._to_base_bytes()

    def __lt__(self, other):
        if not isinstance(other, Unit):
            return NotImplemented
        return self._to_base_bytes() < other._to_base_bytes()

    def __le__(self, other):
        if not isinstance(other, Unit):
            return NotImplemented
        return self._to_base_bytes() <= other._to_base_bytes()

    def __gt__(self, other):
        if not isinstance(other, Unit):
            return NotImplemented
        return self._to_base_bytes() > other._to_base_bytes()

    def __ge__(self, other):
        if not isinstance(other, Unit):
            return NotImplemented
        return self._to_base_bytes() >= other._to_base_bytes()

    def _parse_from_string(self, value):
        """
            Analisa uma string de unidade (ex: "10 GB") e extrai 
            o valor numérico e o tipo de unidade.
        """
        match = re.match(self.UNIT_REGEX, value.strip())
        if not match:
            raise ValueError(f"Invalid unit format: {value}")

        unit_str = match.group("unit")
        self.unit_type = parse_unittype(unit_str)
        self.value = Decimal(match.group("value"))

def build_parser():
    """
        Configura a CLI do programa usando argparse, definindo subcomandos para 
        conversão, adição, subtração, multiplicação, divisão e comparação de unidades.
    """
    parser = ap.ArgumentParser(description="Calculadora de unidades de dados")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Conversão de unidades
    convert_parser = subparsers.add_parser("convert", aliases=["conv"],
                                           help="Converter entre unidades")
    convert_parser.add_argument("value", help="Valor a ser convertido (ex: '10 GB')")
    convert_parser.add_argument("target_unit", choices=UNITS_STR, help="Unidade alvo (ex: 'MB')")
    convert_parser.add_argument("variant", nargs="?", type=int, default=0,
                                help="Variante de formatação (opcional)")

    # Soma de unidades
    add_parser = subparsers.add_parser("add", help="Somar duas unidades")
    add_parser.add_argument("unit1", help="Primeira unidade (ex: '10 GB')")
    add_parser.add_argument("unit2", help="Segunda unidade (ex: '5 MB')")
    add_parser.add_argument("target_unit", choices=UNITS_STR, nargs="?",
                            help="Unidade alvo para o resultado (opcional)")
    add_parser.add_argument("variant", nargs="?", type=int, default=0,
                            help="Variante de formatação para o resultado (opcional)")

    # Subtração de unidades
    sub_parser = subparsers.add_parser("subtract", aliases=["sub"], help="Subtrair duas unidades")
    sub_parser.add_argument("unit1", help="Primeira unidade (ex: '10 GB')")
    sub_parser.add_argument("unit2", help="Segunda unidade (ex: '5 MB')")
    sub_parser.add_argument("target_unit", choices=UNITS_STR, nargs="?",
                            help="Unidade alvo para o resultado (opcional)")
    sub_parser.add_argument("variant", nargs="?", type=int, default=0,
                            help="Variante de formatação para o resultado (opcional)")

    # Multiplicação de unidade por um número
    mul_parser = subparsers.add_parser("multiply", aliases=["mul"],
                                       help="Multiplicar uma unidade por um número")
    mul_parser.add_argument("unit", help="Unidade (ex: '10 GB')")
    mul_parser.add_argument("factor", type=float, help="Fator de multiplicação (ex: 2.5)")
    mul_parser.add_argument("target_unit", choices=UNITS_STR, nargs="?",
                            help="Unidade alvo para o resultado (opcional)")
    mul_parser.add_argument("variant", nargs="?", type=int, default=0,
                            help="Variante de formatação para o resultado (opcional)")

    # Divisão de unidade por um número
    div_parser = subparsers.add_parser("divide", aliases=["div"],
                                       help="Dividir uma unidade por um número")
    div_parser.add_argument("unit", help="Unidade (ex: '10 GB')")
    div_parser.add_argument("divisor", type=float, help="Divisor (ex: 2.5)")
    div_parser.add_argument("target_unit", choices=UNITS_STR, nargs="?",
                            help="Unidade alvo para o resultado (opcional)")
    div_parser.add_argument("variant", nargs="?", type=int, default=0,
                            help="Variante de formatação para o resultado (opcional)")

    # Comparação de unidades
    cmp_parser = subparsers.add_parser("compare", aliases=["cmp"], help="Comparar duas unidades")
    cmp_parser.add_argument("unit1", help="Primeira unidade (ex: '10 GB')")
    cmp_parser.add_argument("unit2", help="Segunda unidade (ex: '5 MB')")
    cmp_parser.add_argument("comparison", choices=CMP_CHOICES,
                            help="Operação de comparação (eq, ne, lt, le, gt, ge)")

    return parser

def main(args):
    """
        Função principal do programa.
    """
    if args.command in ["convert", "conv"]:
        unit = Unit(args.value)
        converted = unit.to(args.target_unit)
        print(converted.strvariant(args.variant))
    elif args.command == "add":
        unit1 = Unit(args.unit1)
        unit2 = Unit(args.unit2)
        result = unit1 + unit2
        if args.target_unit:
            result = result.to(args.target_unit)
        print(result.strvariant(args.variant))
    elif args.command in ["subtract", "sub"]:
        unit1 = Unit(args.unit1)
        unit2 = Unit(args.unit2)
        result = unit1 - unit2
        if args.target_unit:
            result = result.to(args.target_unit)
        print(result.strvariant(args.variant))
    elif args.command in ["multiply", "mul"]:
        unit = Unit(args.unit)
        result = unit * args.factor
        if args.target_unit:
            result = result.to(args.target_unit)
        print(result.strvariant(args.variant))
    elif args.command in ["divide", "div"]:
        unit = Unit(args.unit)
        result = unit / args.divisor
        if args.target_unit:
            result = result.to(args.target_unit)
        print(result.strvariant(args.variant))
    elif args.command in ["compare", "cmp"]:
        unit1 = Unit(args.unit1)
        unit2 = Unit(args.unit2)
        comparison = args.comparison
        if comparison == "eq":
            return 0 if unit1 == unit2 else 1
        elif comparison == "ne":
            return 0 if unit1 != unit2 else 1
        elif comparison == "lt":
            return 0 if unit1 < unit2 else 1
        elif comparison == "le":
            return 0 if unit1 <= unit2 else 1
        elif comparison == "gt":
            return 0 if unit1 > unit2 else 1
        elif comparison == "ge":
            return 0 if unit1 >= unit2 else 1

    return 0

if __name__ == "__main__":
    sys.exit(main(build_parser().parse_args()))
