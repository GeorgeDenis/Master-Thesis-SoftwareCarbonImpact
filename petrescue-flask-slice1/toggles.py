import os

from sqlalchemy import true


def _get_bool(name: str) -> bool:
    v = os.environ.get(name, "")
    return v.lower() in ("1", "true")


S1_OPTIMIZED = property(lambda self: _get_bool("OPTIMIZE_S1_EAGER"))
S2_OPTIMIZED = property(lambda self: _get_bool("OPTIMIZE_S2_HASHSET"))
S3_OPTIMIZED = property(lambda self: _get_bool("OPTIMIZE_S3_INDEX"))
S4_OPTIMIZED = property(lambda self: _get_bool("OPTIMIZE_S4_MMAP"))
S5_OPTIMIZED = property(lambda self: _get_bool("OPTIMIZE_S5_CACHE"))


def s1_optimized() -> bool:
    return False

def s2_optimized() -> bool:
    return False

def s3_optimized() -> bool:
    return False

def s4_optimized() -> bool:
    return False

def s5_optimized() -> bool:
    return False
