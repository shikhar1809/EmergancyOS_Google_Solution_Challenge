"""Replace const Text('...', style: with Text(context.opsTr('...'), style:"""
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..", "lib")
DIRS = [
    os.path.join(ROOT, "features", "staff", "presentation"),
    os.path.join(ROOT, "features", "hospital_bridge", "presentation"),
    os.path.join(ROOT, "features", "operations", "presentation"),
]
IMPORT = "import 'package:emergency_os/core/l10n/dashboard_l10n.dart';\n"

PAT_SQ = re.compile(
    r"const Text\(\s*'((?:\\'|[^'])*)'\s*,\s*style:",
)
def dart_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def repl_sq(m: re.Match) -> str:
    inner = m.group(1).replace(r"\'", "'")
    return f"Text(context.opsTr('{dart_escape(inner)}'), style:"


def main():
    for d in DIRS:
        if not os.path.isdir(d):
            continue
        for dirpath, _, files in os.walk(d):
            for fn in files:
                if not fn.endswith(".dart"):
                    continue
                path = os.path.join(dirpath, fn)
                text = open(path, encoding="utf-8").read()
                orig = text
                text = PAT_SQ.sub(repl_sq, text)
                if text != orig:
                    if "package:emergency_os/core/l10n/dashboard_l10n.dart" not in text:
                        lines = text.split("\n")
                        insert_at = 0
                        for i, line in enumerate(lines):
                            if line.startswith("import "):
                                insert_at = i + 1
                        lines.insert(insert_at, IMPORT.rstrip())
                        text = "\n".join(lines)
                    open(path, "w", encoding="utf-8", newline="\n").write(text)
                    print(path)


if __name__ == "__main__":
    main()
