"""Exercise refresh coalescing against a real stdio subprocess."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

with tempfile.TemporaryDirectory(prefix='dms-peripherals-refresh-') as directory:
    root = Path(directory)
    shutil.copy(Path(__file__).resolve().parents[1] / 'plugin/MouseService.qml', root)
    backend = root / 'backend'
    backend.write_text('''#!/usr/bin/python3
import json,sys
from pathlib import Path
for line in sys.stdin:
    request=json.loads(line)
    with open(Path(__file__).with_name('requests'),'a') as log: log.write(request['method']+'\\n')
    print(json.dumps({'id':request['id'],'result':{'status':{'name':'Test','batteryPercent':65,'dpi':800},'capabilities':{},'options':{}}}),flush=True)
''')
    backend.chmod(0o755)
    (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
    MouseService { id: service; selectedDeviceId: "test"; backendPath: %s }
    Timer {
        interval: 100; repeat: true; running: true
        property int phase: 0
        onTriggered: {
            if (service.busy || !service.status) return;
            if (phase === 0) {
                service.ensureFresh(); service.ensureFresh();
                phase = 1;
            } else if (phase === 1) {
                service.readDetails();
                service.ensureFresh(0);
                service.setSetting("dpi", 800);
                if (!service.writing) throw new Error("Queued write must lock write controls");
                phase = 2;
            } else { console.warn("REFRESH_PASS"); Qt.quit(); }
        }
    }
}
''' % json.dumps(str(backend)))
    result = subprocess.run(['quickshell', '-p', directory], env=dict(os.environ, QT_QPA_PLATFORM='offscreen', XDG_RUNTIME_DIR=directory), capture_output=True, text=True, timeout=15)
    assert 'REFRESH_PASS' in result.stdout + result.stderr, result.stdout + result.stderr
    requests = (root / 'requests').read_text().splitlines()
    assert requests == ['get_details', 'get_details', 'set_setting'], requests
    print('PASS startup reads once, repeated ensureFresh calls coalesce, manual refresh still reads, settings wait for an active read')
