import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent / "Sources"
rules = [
    (re.compile(r"\bMenu\s*[{(]"), "plain Menu: use RichPicker"),
    (re.compile(r"\.pickerStyle\(\.(segmented|menu|radioGroup)\)"), "system picker style: use RichPicker"),
    (re.compile(r"\bPicker\("), "plain Picker: use RichPicker (context-menu pickers use .pickerStyle(.inline))"),
]
problems = []
for path in sorted(root.glob("*.swift")):
    if path.name == "RichPicker.swift":
        continue
    for number, line in enumerate(path.read_text().splitlines(), 1):
        for pattern, message in rules:
            if pattern.search(line) and "pickerStyle(.inline)" not in line and not line.strip().startswith("Picker(\"⌘"):
                problems.append(f"{path.name}:{number}: {message}")
for problem in problems:
    print(problem)
print("ok" if not problems else "problems")
