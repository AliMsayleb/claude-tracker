import fcntl, glob, json, os, pty, re, select, signal, struct, subprocess, sys, termios, time

BINARY, HOOK, WORKDIR, HOME = sys.argv[1:5]
os.makedirs(os.path.join(HOME, "requests"), exist_ok=True)
settings = os.path.join(HOME, "settings.json")
json.dump({"hooks": {"PermissionRequest": [{"hooks": [{"type": "command", "command": '"%s"' % HOOK, "timeout": 630}]}]}}, open(settings, "w"))
env = {k: v for k, v in os.environ.items()
       if not (k.startswith(("CLAUDE_CODE_", "CLAUDE_AGENT_SDK", "CLAUDE_PREVIEW"))
               or k in ("CLAUDECODE", "CLAUDE_EFFORT", "CLAUDE_PID", "ANTHROPIC_BASE_URL"))}
env.update(TERM="xterm-256color", CLAUDE_WIDGET_HOME=HOME, CLAUDE_CODE_ENABLE_ASK_USER_QUESTION_TOOL="1")
prompt = ("Use the AskUserQuestion tool exactly once to ask me which color I prefer. Give exactly two options: "
          "Red and Blue. Wait for my answer, then reply with only the letters of the chosen color name written backwards, in capital letters.")
pid, fd = pty.fork()
if pid == 0:
    os.chdir(WORKDIR)
    os.execvpe("claude", ["claude", "--model", "haiku", "--permission-mode", "default", "--settings", settings, prompt], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 45, 140, 0, 0))
buffer = ""


def pump(seconds):
    global buffer
    end = time.time() + seconds
    while time.time() < end:
        with open(os.path.join(HOME, "heartbeat"), "w") as f:
            f.write(str(time.time()))
        if select.select([fd], [], [], 0.2)[0]:
            try:
                buffer += os.read(fd, 65536).decode("utf-8", "ignore")
            except OSError:
                return


def visible(text):
    return re.sub(r"\s+", "", re.sub(r"\x1b\[[0-9;?>]*[A-Za-z]|\x1b\][^\x07]*\x07|\x1b[=>]", "", text))


result = {}
request_id = None
end = time.time() + 90
while time.time() < end and not request_id:
    pump(0.5)
    for path in glob.glob(os.path.join(HOME, "requests", "*.json")):
        if "AskUserQuestion" in open(path).read():
            request_id = os.path.basename(path)[:-5]
result["question_reached_the_widget"] = bool(request_id)
if request_id:
    payload = json.load(open(os.path.join(HOME, "requests", request_id + ".json")))
    questions = payload["tool_input"]["questions"]
    result["options_offered"] = [o["label"] for o in questions[0]["options"]]
    mark = len(buffer)
    out = subprocess.run([BINARY, "--answer", request_id, "1"], env=env, capture_output=True, text=True)
    result["widget_answer"] = out.stdout.strip()
    end = time.time() + 60
    while time.time() < end and "EULB" not in visible(buffer[mark:]).upper():
        pump(0.5)
    tail = visible(buffer[mark:])
    result["claude_replied_with_chosen_option"] = "EULB" in tail.upper() and "DER" not in tail.upper().replace("DERIVED", "")
    result["native_dialog_still_waiting"] = "EULB" not in tail.upper()
os.kill(pid, signal.SIGTERM)
time.sleep(1)
try:
    os.kill(pid, signal.SIGKILL)
except OSError:
    pass
print(json.dumps(result, indent=2))
