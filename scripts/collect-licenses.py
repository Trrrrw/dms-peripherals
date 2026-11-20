"""Copy dependency notices into the redistributable plugin bundle."""
from pathlib import Path
import json
import shutil
root = Path(__file__).resolve().parents[1]
destination = root / 'plugin/licenses'
for package in (root / 'plugin/bin/native-hid/node_modules').glob('**/package.json'):
    if '/node_modules/' not in str(package):
        continue
    try:
        metadata = json.loads(package.read_text())
    except (ValueError, OSError):
        continue
    name = metadata.get('name', package.parent.name).replace('/', '_')
    for item in package.parent.iterdir():
        if item.is_file() and item.name.lower().startswith(('license', 'copying', 'notice')):
            folder = destination / name
            folder.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(item, folder / item.name)

import subprocess
metadata = json.loads(subprocess.check_output(['cargo', 'metadata', '--manifest-path', str(root / 'backend/Cargo.toml'), '--format-version', '1', '--locked']))
for package in metadata['packages']:
    if package.get('source') is None:
        continue
    folder = Path(package['manifest_path']).parent
    for item in folder.iterdir():
        if item.is_file() and item.name.lower().startswith(('license', 'copying', 'notice')):
            target = destination / ('rust-' + package['name'])
            target.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(item, target / item.name)
