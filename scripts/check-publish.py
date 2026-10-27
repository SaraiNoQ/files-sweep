"""Check that publication preserves the old inode and an already-open reader."""
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import tempfile

spec = spec_from_file_location("publisher", Path(__file__).with_name("publish-app.py"))
publisher = module_from_spec(spec)
spec.loader.exec_module(publisher)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    current, staged = root / "FileSweep.app", root / "staged.app"
    for directory, text in [(current, b"old executable"), (staged, b"new executable")]:
        directory.mkdir()
        (directory / "executable").write_bytes(text)
    old_inode = (current / "executable").stat().st_ino
    with (current / "executable").open("rb") as reader:
        previous = publisher.publish(staged, current)
        assert reader.read() == b"old executable"
        assert (previous / "executable").stat().st_ino == old_inode
        assert (current / "executable").read_bytes() == b"new executable"
    assert publisher.publish(previous, root / "first-install.app") is None
print("PASS: atomic publication preserves the running executable")
