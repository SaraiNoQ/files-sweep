"""Publish a verified bundle without modifying the executable of a running app."""
import ctypes
import os
from pathlib import Path
import sys


def publish(staged: Path, destination: Path) -> Path | None:
    if staged.parent != destination.parent or not staged.is_dir() or staged.is_symlink():
        raise ValueError("Expected a staged bundle beside the destination")
    if not destination.exists():
        os.rename(staged, destination)
        return None
    if not destination.is_dir() or destination.is_symlink():
        raise ValueError("Refusing to replace a non-bundle destination")
    library = ctypes.CDLL(None, use_errno=True)
    swap = library.renamex_np
    swap.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    swap.restype = ctypes.c_int
    if swap(os.fsencode(staged), os.fsencode(destination), 2) != 0:  # RENAME_SWAP
        raise OSError(ctypes.get_errno(), "Atomic app publication failed")
    # Keep the previous bundle intact: its executable may still be memory-mapped.
    return staged


if __name__ == "__main__":
    previous = publish(Path(sys.argv[1]), Path(sys.argv[2]))
    if previous:
        print(f"Previous running-safe bundle retained: {previous}")
