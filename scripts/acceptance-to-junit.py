#!/usr/bin/env python3
"""Convert acceptance smoke test output to a minimal JUnit XML.

We parse lines like:
  [acceptance] ok: <name>

Usage:
  scripts/acceptance-to-junit.py <input_log> <output_xml>
"""

from __future__ import annotations

import sys
import time
import xml.etree.ElementTree as ET


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: acceptance-to-junit.py <input_log> <output_xml>", file=sys.stderr)
        return 2

    inp, outp = sys.argv[1], sys.argv[2]

    checks: list[str] = []
    with open(inp, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip("\n")
            if line.startswith("[acceptance] ok:"):
                checks.append(line.split("[acceptance] ok:", 1)[1].strip())

    suite = ET.Element("testsuite")
    suite.set("name", "acceptance")
    suite.set("timestamp", time.strftime("%Y-%m-%dT%H:%M:%S"))
    suite.set("tests", str(len(checks)))
    suite.set("failures", "0")

    for name in checks:
        tc = ET.SubElement(suite, "testcase")
        tc.set("name", name)
        tc.set("classname", "gitw")
        tc.set("time", "0")

    tree = ET.ElementTree(suite)
    ET.indent(tree, space="  ")
    with open(outp, "wb") as f:
        tree.write(f, encoding="utf-8", xml_declaration=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
