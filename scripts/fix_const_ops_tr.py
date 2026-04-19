"""Remove invalid const before Text(context.opsTr(...)) etc."""
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "lib")

REPLACEMENTS = [
    ("const Text(context.opsTr", "Text(context.opsTr"),
    ("const SnackBar(content: Text(context.opsTr", "SnackBar(content: Text(context.opsTr"),
    ("label: const Text(context.opsTr", "label: Text(context.opsTr"),
    ("title: const Text(context.opsTr", "title: Text(context.opsTr"),
    ("child: const Text(context.opsTr", "child: Text(context.opsTr"),
    ("content: const Text(context.opsTr", "content: Text(context.opsTr"),
]


def main():
    for dirpath, _, files in os.walk(ROOT):
        for fn in files:
            if not fn.endswith(".dart"):
                continue
            path = os.path.join(dirpath, fn)
            text = open(path, encoding="utf-8").read()
            orig = text
            for a, b in REPLACEMENTS:
                text = text.replace(a, b)
            if text != orig:
                open(path, "w", encoding="utf-8", newline="\n").write(text)
                print(path)


if __name__ == "__main__":
    main()
