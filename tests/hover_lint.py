import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOVER_AWARE = ("PressScaleStyle", "ActionButtonStyle", "PillButtonStyle", ".hoverHighlight(", "CircleIconButton(")
NATIVE_MENU_CONTEXT = ("contextMenu", "Menu {")
problems = []


def indent(line):
    return len(line) - len(line.lstrip())


def chunk(lines, start):
    base = indent(lines[start])
    end = start + 1
    while end < len(lines):
        line = lines[end]
        if line.strip() == "":
            break
        if indent(line) > base or (indent(line) == base and line.lstrip().startswith((".", "}"))):
            end += 1
        else:
            break
    return "\n".join(lines[start:end])


for path in sorted(glob.glob(os.path.join(ROOT, "Sources", "*.swift"))):
    name = os.path.basename(path)
    if name == "Hover.swift":
        continue
    lines = open(path).read().split("\n")
    in_context_menu = False
    context_indent = -1
    for number, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith((".contextMenu", "Menu {")):
            in_context_menu, context_indent = True, indent(line)
        elif in_context_menu and stripped and indent(line) <= context_indent and not stripped.startswith(("}", ".")):
            in_context_menu = False
        if re.match(r"(return )?Button[ ({]", stripped) and not in_context_menu:
            if not any(marker in chunk(lines, number) for marker in HOVER_AWARE):
                problems.append(f"Sources/{name}:{number + 1}: Button without a hover effect")
        if ".onTapGesture" in stripped:
            context = "\n".join(lines[max(0, number - 14):number + 1])
            if not any(marker in context for marker in (".hoverHighlight(", ".onHover", "SessionRowView(")):
                problems.append(f"Sources/{name}:{number + 1}: tap target without a hover effect")

if problems:
    print("\n".join(problems))
    sys.exit(1)
print("ok")
