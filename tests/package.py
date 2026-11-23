"""Build releases/AzerothFamiliar-<version>.zip with one AzerothAssistant top-level folder.
Ships only what the game loads plus README and LICENSE (as in 0.8.x releases)."""
from pathlib import Path
import hashlib
import zipfile

root = Path(__file__).resolve().parents[1]
toc = (root / 'AzerothAssistant.toc').read_text(encoding='utf-8')
version = next(l.split(':', 1)[1].strip() for l in toc.splitlines() if l.startswith('## Version:'))
assert f'AA.VERSION = "{version}"' in (root / 'Core.lua').read_text(encoding='utf-8'), 'Core/TOC version mismatch'
modules = [l.strip().replace('\\', '/') for l in toc.splitlines() if l.strip() and not l.startswith('#')]
for m in modules:
    assert (root / m).is_file(), f'Missing TOC module: {m}'
media = [p.relative_to(root).as_posix() for p in (root / 'Media').glob('*.tga')]
ship = ['AzerothAssistant.toc', 'README.md', 'LICENSE'] + media + modules
target = root.parent / 'releases' / f'AzerothFamiliar-{version}.zip'
assert not target.exists(), f'{target} already exists; bump the version'
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
    for rel in sorted(set(ship)):
        archive.write(root / rel, 'AzerothAssistant/' + rel)
with zipfile.ZipFile(target) as archive:
    assert archive.testzip() is None
    assert 'AzerothAssistant/AzerothAssistant.toc' in archive.namelist()
    count = len(archive.namelist())
print(str(target))
print('SHA256 ' + hashlib.sha256(target.read_bytes()).hexdigest())
print(f'{target.stat().st_size} bytes; {count} files; ZIP and TOC verified')
