import fcntl, json, os, pty, re, select, signal, struct, subprocess, sys, termios, time

BINARY, CLAUDE = sys.argv[1], sys.argv[2]
env = {k: v for k, v in os.environ.items()
       if not (k.startswith(("CLAUDE_CODE_", "CLAUDE_AGENT_SDK", "CLAUDE_PREVIEW"))
               or k in ("CLAUDECODE", "CLAUDE_EFFORT", "CLAUDE_PID", "ANTHROPIC_BASE_URL"))}
env["TERM"] = "xterm-256color"
pid, fd = pty.fork()
if pid == 0:
    os.chdir(sys.argv[3])
    os.execvpe(CLAUDE, [CLAUDE, "--model", "haiku", "--permission-mode", "default",
                        "Reply with only the word READY"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 140, 0, 0))
buffer = ""


def pump(seconds):
    global buffer
    end = time.time() + seconds
    while time.time() < end:
        if select.select([fd], [], [], 0.2)[0]:
            try:
                buffer += os.read(fd, 65536).decode("utf-8", "ignore")
            except OSError:
                return


def visible(text):
    return re.sub(r"\s+", "", re.sub(r"\x1b\[[0-9;?>]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b[=>]", "", text))


def wait_for(word, since, timeout):
    end = time.time() + timeout
    while time.time() < end:
        pump(0.3)
        if word in visible(buffer[since:])[:]:
            return True
    return False


result = {}
result["first_reply_seen"] = wait_for("READY", len("Replywithonlytheword") and 0, 90)
pump(2)
row = None
for _ in range(10):
    rows = json.loads(subprocess.run([BINARY, "--dump"], env=env, capture_output=True, text=True).stdout)
    row = next((r for r in rows if r["pid"] == pid), None)
    if row:
        break
    pump(0.5)
result["row_state_before_send"] = row and row["state"]
mark = len(buffer)
out = subprocess.run([BINARY, "--send", str(pid), "Reply with only the single word made by joining PO and NG"], env=env, capture_output=True, text=True)
result["send_output"] = out.stdout.strip()
result["reply_received_after_send"] = wait_for("PONG", mark, 60)
os.kill(pid, signal.SIGTERM)
time.sleep(1)
try:
    os.kill(pid, signal.SIGKILL)
except OSError:
    pass
print(json.dumps(result, indent=2))
