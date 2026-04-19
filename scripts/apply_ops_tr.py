"""Replace Text('...') etc. with Text(context.opsTr('...')) in dashboard Dart files."""
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..", "lib")
DIRS = [
    os.path.join(ROOT, "features", "staff", "presentation"),
    os.path.join(ROOT, "features", "hospital_bridge", "presentation"),
    os.path.join(ROOT, "features", "operations", "presentation"),
]

IMPORT = "import 'package:emergency_os/core/l10n/dashboard_l10n.dart';\n"


def extract_strings_from_line(line: str) -> list[str]:
    out = []
    for rx in (
        r"(?:const\s+)?Text\(\s*'((?:\\'|[^'])*)'",
        r'Text\(\s*"((?:\\"|[^"])*)"',
        r"subtitle:\s*(?:const\s+)?Text\(\s*'((?:\\'|[^'])*)'",
        r'subtitle:\s*(?:const\s+)?Text\(\s*"((?:\\"|[^"])*)"',
        r"label:\s*(?:const\s+)?Text\(\s*'((?:\\'|[^'])*)'",
        r"content:\s*(?:const\s+)?Text\(\s*'((?:\\'|[^'])*)'",
        r"content:\s*Text\(\s*'((?:\\'|[^'])*)'",
        r"title:\s*(?:const\s+)?Text\(\s*'((?:\\'|[^'])*)'",
        r"title:\s*Text\(\s*'((?:\\'|[^'])*)'",
        r"child:\s*(?:const\s+)?Text\(\s*'((?:\\'|[^'])*)'",
        r"labelText:\s*'((?:\\'|[^'])*)'",
        r"hintText:\s*'((?:\\'|[^'])*)'",
        r"tooltip:\s*'((?:\\'|[^'])*)'",
        r"semanticLabel:\s*'((?:\\'|[^'])*)'",
    ):
        for m in re.finditer(rx, line):
            s = m.group(1)
            if "\\'" in s:
                s = s.replace("\\'", "'")
            if '\\"' in s:
                s = s.replace('\\"', '"')
            out.append(s)
    return out


def dart_escape_single(s: str) -> str:
    return s.replace("\\", "\\\\").replace("'", "\\'")


def main():
    seen = {}
    for d in DIRS:
        if not os.path.isdir(d):
            continue
        for dirpath, _, files in os.walk(d):
            for fn in files:
                if not fn.endswith(".dart"):
                    continue
                path = os.path.join(dirpath, fn)
                try:
                    lines = open(path, encoding="utf-8").readlines()
                except OSError:
                    continue
                for line in lines:
                    for s in extract_strings_from_line(line):
                        if not s or len(s) > 280:
                            continue
                        if "$" in s or "${" in s:
                            continue
                        if s.strip() == "":
                            continue
                        seen.setdefault(s, path)

    strings = sorted(seen.keys(), key=len, reverse=True)

    for d in DIRS:
        if not os.path.isdir(d):
            continue
        for dirpath, _, files in os.walk(d):
            for fn in files:
                if not fn.endswith(".dart"):
                    continue
                if fn == "dashboard_l10n.dart":
                    continue
                path = os.path.join(dirpath, fn)
                text = open(path, encoding="utf-8").read()
                orig = text
                for s in strings:
                    de = dart_escape_single(s)
                    text = text.replace(f"Text('{de}')", f"Text(context.opsTr('{de}'))")
                    text = text.replace(f'Text("{de}")', f'Text(context.opsTr("{de}"))')
                    text = text.replace(f"const Text('{de}')", f"Text(context.opsTr('{de}'))")
                    text = text.replace(f'const Text("{de}")', f'Text(context.opsTr("{de}"))')
                    text = text.replace(
                        f"SnackBar(content: Text('{de}'))",
                        f"SnackBar(content: Text(context.opsTr('{de}')))",
                    )
                    text = text.replace(
                        f"SnackBar(content: const Text('{de}'))",
                        f"SnackBar(content: Text(context.opsTr('{de}')))",
                    )
                    text = text.replace(f"label: Text('{de}')", f"label: Text(context.opsTr('{de}'))")
                    text = text.replace(f"label: const Text('{de}')", f"label: Text(context.opsTr('{de}'))")
                    text = text.replace(f"title: Text('{de}')", f"title: Text(context.opsTr('{de}'))")
                    text = text.replace(f"title: const Text('{de}')", f"title: Text(context.opsTr('{de}'))")
                    text = text.replace(f"subtitle: Text('{de}')", f"subtitle: Text(context.opsTr('{de}'))")
                    text = text.replace(f"subtitle: const Text('{de}')", f"subtitle: Text(context.opsTr('{de}'))")
                    text = text.replace(f"content: Text('{de}')", f"content: Text(context.opsTr('{de}'))")
                    text = text.replace(f"content: const Text('{de}')", f"content: Text(context.opsTr('{de}'))")
                    text = text.replace(f"child: Text('{de}')", f"child: Text(context.opsTr('{de}'))")
                    text = text.replace(f"child: const Text('{de}')", f"child: Text(context.opsTr('{de}'))")
                    text = text.replace(f"labelText: '{de}'", f"labelText: context.opsTr('{de}')")
                    text = text.replace(f"hintText: '{de}'", f"hintText: context.opsTr('{de}')")
                    text = text.replace(f"tooltip: '{de}'", f"tooltip: context.opsTr('{de}')")

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
                    print(f"Updated {path}")


if __name__ == "__main__":
    main()
