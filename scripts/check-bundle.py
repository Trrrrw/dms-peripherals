"""Check the installable directory without requiring a development checkout."""
from pathlib import Path
import json
import subprocess
root = Path(__file__).resolve().parents[1] / 'plugin'
manifest = json.loads((root / 'plugin.json').read_text())
for key in ('component', 'settings', 'startupCheck'):
    assert (root / manifest[key]).is_file(), key
for name in ('ControlCard.qml','DevicePanel.qml','MouseService.qml','bin/dms-peripherals',
             'bin/native-hid/src/control.mjs','bin/native-hid/src/runtime.mjs',
             'bin/native-hid/src/hid-device-adapter.mjs','licenses/LICENSE',
             'licenses/THIRD_PARTY_NOTICES.md','licenses/BRIDGE_LICENSE.txt','licenses/SOURCE_LINKS.md'):
    assert (root / name).is_file(), name
assert not (root / 'bin/native-hid/node/bin/node').exists(), 'Do not bundle Node.js'
result=subprocess.run([str(root / 'bin/dms-peripherals')],input='{"id":1,"method":"unknown"}\n',capture_output=True,text=True,check=True)
assert json.loads(result.stdout)['error']['code']=='unknown_method'
# Loading the registry exercises dependency resolution and native binding availability.
subprocess.run(['node','--input-type=module','-e',"import('./src/runtime.mjs').then(m=>{if(typeof m.inventory!=='function')process.exit(1)})"],cwd=root/'bin/native-hid',check=True)
print('PASS installable plugin manifest, runtime, native dependency, and protocol')
