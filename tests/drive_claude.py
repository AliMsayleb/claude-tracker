import fcntl
import json
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

HOOK = sys.argv[1]
WORKDIR = sys.argv[2]
MODE = sys.argv[3]
WIDGET_HOME = sys.argv[4]
TEST_FILE = os.path.join(WORKDIR, "harness-test-file.txt")
SETTINGS = os.path.join(WIDGET_HOME, "settings.json")

os.makedirs(os.path.join(WIDGET_HOME, "requests"), exist_ok=True)
with open(SETTINGS, "w") as f:
    json.dump({"hooks": {"PermissionRequest": [{"hooks": [
        {"type": "command", "command": '"%s"' % HOOK, "timeout": 630}
    ]}]}}, f)

if os.path.exists(TEST_FILE):
    os.remove(TEST_FILE)

heartbeat = os.path.join(WIDGET_HOME, "heartbeat")
beat_stop = False


def beat():
    if MODE == "widget-live":
        return
    with open(heartbeat, "w") as f:
        f.write(str(time.time()))


beat()
inherited = {k: v for k, v in os.environ.items()
             if not (k.startswith(("CLAUDE_CODE_", "CLAUDE_AGENT_SDK", "CLAUDE_PREVIEW"))
                     or k in ("CLAUDECODE", "CLAUDE_EFFORT", "CLAUDE_PID", "ANTHROPIC_BASE_URL"))}
env = dict(inherited, CLAUDE_WIDGET_HOME=WIDGET_HOME, CLAUDE_WIDGET_HOOK_WAIT="600", TERM="xterm-256color")
argv = ["claude", "--model", "haiku", "--permission-mode", "default", "--settings", SETTINGS,
        "Run exactly this bash command and nothing else: touch harness-test-file.txt"]

pid, fd = pty.fork()
if pid == 0:
    os.chdir(WORKDIR)
    os.execvpe("claude", argv, env)

fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 140, 0, 0))
buffer = ""
start = time.time()


def pump(seconds):
    global buffer
    end = time.time() + seconds
    while time.time() < end:
        beat()
        ready, _, _ = select.select([fd], [], [], 0.2)
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return False
            if not data:
                return False
            buffer += data.decode("utf-8", "ignore")
    return True


def visible(text):
    text = re.sub(r"\x1b\[[0-9;?>]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b[=>]", "", text)
    return re.sub(r"\s+", "", text)


def wait_for(pattern, timeout):
    end = time.time() + timeout
    while time.time() < end:
        pump(0.3)
        if re.search(pattern, visible(buffer), re.I):
            return True
    return False


def hooks_running():
    out = subprocess.run(["pgrep", "-f", "permission-hook.sh"], capture_output=True, text=True).stdout.split()
    return len(out)


def requests_listed():
    return sorted(n for n in os.listdir(os.path.join(WIDGET_HOME, "requests")) if n.endswith(".json"))


result = {}
if not wait_for(r"Doyouwanttoproceed", 90):
    with open(os.path.join(WIDGET_HOME, "pty.log"), "w") as f:
        f.write(buffer)
    print(json.dumps({"error": "dialog never appeared", "pty_log": os.path.join(WIDGET_HOME, "pty.log"),
                      "request_files": requests_listed(), "hooks_running": hooks_running()}))
    os.kill(pid, signal.SIGKILL)
    sys.exit(1)

t_dialog = time.time()
pump(2.5)
result["request_files_while_dialog_open"] = requests_listed()
try:
    registry = json.load(open(os.path.expanduser("~/.claude/sessions/%d.json" % pid)))
    result["registry_while_dialog_open"] = {"status": registry.get("status"), "waitingFor": registry.get("waitingFor"),
                                            "sessionId": registry.get("sessionId")}
except (OSError, ValueError) as error:
    result["registry_while_dialog_open"] = str(error)
result["hook_processes_while_dialog_open"] = hooks_running()

if MODE == "native":
    t_answer = time.time()
    os.write(fd, b"\r")
    deadline = time.time() + 30
    while time.time() < deadline and not os.path.exists(TEST_FILE):
        pump(0.1)
    result["command_ran"] = os.path.exists(TEST_FILE)
    result["seconds_from_native_answer_to_command"] = round(time.time() - t_answer, 2)
    pump(3)
    result["hook_processes_after_native_answer"] = hooks_running()
    result["request_files_after_native_answer"] = requests_listed()
elif MODE == "widget-live":
    binary = sys.argv[5]
    row = None
    began = time.time()
    while time.time() < began + 15 and row is None:
        dumped = subprocess.run([binary, "--dump"], env=env, capture_output=True, text=True).stdout
        mine = [r for r in json.loads(dumped) if r["pid"] == pid]
        if mine and mine[0]["requests"]:
            row = mine[0]
        else:
            pump(0.5)
    if row is None:
        result["error"] = "widget never showed the request"
    else:
        request = row["requests"][0]
        result["widget_row"] = {"state": row["state"], "tool": request["toolName"], "detail": request["detail"],
                                "origin": row["origin"], "seconds_until_widget_shows_it": round(time.time() - t_dialog, 2)}
        pump(float(sys.argv[6]) if len(sys.argv) > 6 else 0)
        t_answer = time.time()
        subprocess.run([binary, "--decide", request["id"], "allow"], env=env)
        deadline = time.time() + 15
        while time.time() < deadline and not os.path.exists(TEST_FILE):
            pump(0.1)
        result["command_ran"] = os.path.exists(TEST_FILE)
        result["seconds_from_decide_to_command"] = round(time.time() - t_answer, 2)
        pump(2)
        result["hook_processes_after"] = hooks_running()
        result["request_files_after"] = requests_listed()
elif MODE == "widget-allow" or MODE == "widget-deny":
    files = requests_listed()
    if files:
        request_id = files[0][:-5]
        t_answer = time.time()
        answer_mark = len(buffer)
        with open(os.path.join(WIDGET_HOME, "requests", request_id + ".decision"), "w") as f:
            f.write("allow" if MODE == "widget-allow" else "deny")
        deadline = time.time() + 15
        while time.time() < deadline:
            pump(0.2)
            if MODE == "widget-allow" and os.path.exists(TEST_FILE):
                break
            if MODE == "widget-deny" and re.search(r"Deniedfromthe|denied|rejected|interrupted", visible(buffer[answer_mark:]), re.I):
                break
        result["command_ran"] = os.path.exists(TEST_FILE)
        result["seconds_from_widget_answer"] = round(time.time() - t_answer, 2)
        pump(2)
        result["hook_processes_after"] = hooks_running()
        result["request_files_after"] = requests_listed()
    else:
        result["error"] = "no request file appeared"

os.kill(pid, signal.SIGTERM)
time.sleep(1)
for _ in range(2):
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        break
if os.path.exists(TEST_FILE):
    os.remove(TEST_FILE)
print(json.dumps(result, indent=2))
