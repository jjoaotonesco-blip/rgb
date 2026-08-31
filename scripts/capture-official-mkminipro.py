import frida
import os
import pathlib
import subprocess
import sys
import time
from datetime import datetime

CAPTURE_SECONDS = int(os.environ.get("CAPTURE_SECONDS", "120"))
OUT = pathlib.Path(os.environ.get("TRACE_OUT", "official-mkminipro-hid-trace.txt"))

candidates = [
    pathlib.Path(r"C:\Program Files (x86)\Keyboard YH-MKMINIPRO\MKMINIPRO.exe"),
    pathlib.Path(r"C:\Program Files\Keyboard YH-MKMINIPRO\MKMINIPRO.exe"),
]
exe = next((p for p in candidates if p.exists()), None)
if exe is None:
    raise SystemExit("Official MKMINIPRO.exe not found in expected Program Files path")

# Only the vendor application's own WriteFile/ReadFile calls are traced. The hook
# ignores everything except 64/65-byte HID-like packets beginning with 0x55 and
# ACK-like reads containing 0xAA, so normal keyboard input is not captured.
subprocess.run(["taskkill", "/IM", "MKMINIPRO.exe", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1)
proc = subprocess.Popen([str(exe)], cwd=str(exe.parent))
time.sleep(3)

session = frida.attach(proc.pid)

js = r'''
function hexBytes(ptr, n) {
    try {
        const a = new Uint8Array(ptr.readByteArray(n));
        let s = '';
        for (let i = 0; i < a.length; i++) {
            if (i) s += ' ';
            s += ('0' + a[i].toString(16)).slice(-2).toUpperCase();
        }
        return {hex:s, first:a.length > 0 ? a[0] : -1, second:a.length > 1 ? a[1] : -1};
    } catch (e) { return null; }
}

function findExport(name) {
    const mods = ['kernel32.dll', 'KernelBase.dll'];
    for (const m of mods) {
        try {
            const p = Module.getGlobalExportByName(name);
            if (p) return p;
        } catch (e) {}
        try {
            const mod = Process.getModuleByName(m);
            const p = mod.getExportByName(name);
            if (p) return p;
        } catch (e) {}
    }
    return null;
}

const wp = findExport('WriteFile');
const rp = findExport('ReadFile');
if (!wp || !rp) {
    send({type:'fatal', text:'WriteFile/ReadFile export not found'});
} else {
    send({type:'ready', write:wp.toString(), read:rp.toString()});

    Interceptor.attach(wp, {
        onEnter(args) {
            this.buf = args[1];
            this.n = args[2].toInt32();
            this.capture = false;
            if (this.n === 64 || this.n === 65) {
                const h = hexBytes(this.buf, this.n);
                if (h && (h.first === 0x55 || h.second === 0x55)) {
                    this.capture = true;
                    this.h = h.hex;
                }
            }
        },
        onLeave(retval) {
            if (this.capture) send({type:'write', n:this.n, ok:!retval.isNull(), hex:this.h});
        }
    });

    Interceptor.attach(rp, {
        onEnter(args) {
            this.buf = args[1];
            this.requested = args[2].toInt32();
            this.readPtr = args[3];
        },
        onLeave(retval) {
            if (retval.isNull()) return;
            if (!(this.requested === 64 || this.requested === 65)) return;
            let n = this.requested;
            try { if (!this.readPtr.isNull()) n = this.readPtr.readU32(); } catch (e) {}
            if (n <= 0 || n > 65) return;
            const h = hexBytes(this.buf, n);
            if (h && (h.first === 0xAA || h.second === 0xAA || h.first === 0x55 || h.second === 0x55)) {
                send({type:'read', n:n, hex:h.hex});
            }
        }
    });
}
'''

lines = []
def log(text):
    stamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    line = f"[{stamp}] {text}"
    print(line, flush=True)
    lines.append(line)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

def on_message(message, data):
    if message.get("type") == "send":
        p = message.get("payload", {})
        t = p.get("type")
        if t == "write":
            log(f"WRITE n={p.get('n')} ok={p.get('ok')} :: {p.get('hex')}")
        elif t == "read":
            log(f"READ  n={p.get('n')} :: {p.get('hex')}")
        elif t == "ready":
            log(f"HOOK_READY WriteFile={p.get('write')} ReadFile={p.get('read')}")
        else:
            log(f"FRIDA {p}")
    else:
        log(f"FRIDA_MESSAGE {message}")

script = session.create_script(js)
script.on("message", on_message)
script.load()

log(f"TARGET={exe}")
log(f"PID={proc.pid}")
log(f"CAPTURE_SECONDS={CAPTURE_SECONDS}")
log("ACTION: in the official MKMINIPRO window choose a known static/custom RGB configuration and click its Apply/Save button ONCE.")

try:
    deadline = time.time() + CAPTURE_SECONDS
    while time.time() < deadline and proc.poll() is None:
        time.sleep(0.25)
finally:
    try: script.unload()
    except Exception: pass
    try: session.detach()
    except Exception: pass

log("CAPTURE_FINISHED")
