"""Bettet die Dateien aus web/ als gzip-Bytefeld in include/web_assets.h ein.

Laeuft als pre-Skript bei jedem Build. Damit bleibt der Web-Quelltext eine
normale, editierbare Datei, und trotzdem genuegt ein einziger Upload-Schritt -
kein separates Flashen eines Dateisystems, das man nach einem OTA garantiert
vergisst.

Gzip statt Rohtext aus zwei Gruenden: es spart rund zwei Drittel Flash, und ein
C++-Rohstring wuerde in dem Moment brechen, in dem im HTML die Zeichenfolge des
Trennzeichens auftaucht. Ein Bytefeld kann das nicht passieren.

PROGMEM braucht es auf dem ESP32 nicht - der Flash ist in den Adressraum
eingeblendet, ein const-Feld liegt ohnehin in .rodata und ist ganz normal
lesbar.
"""

import gzip
import hashlib
import os
import textwrap

Import("env")   # noqa: F821  (von SCons bereitgestellt)

PROJEKT = env["PROJECT_DIR"]            # noqa: F821
QUELLEN = {
    "INDEX_HTML": os.path.join(PROJEKT, "web", "index.html"),
    "SETUP_HTML": os.path.join(PROJEKT, "web", "setup.html"),
}
ZIEL = os.path.join(PROJEKT, "include", "web_assets.h")


def baue_header():
    teile = [
        "// Erzeugt von scripts/embed_web.py - nicht von Hand aendern.\n",
        "// Quelle sind die Dateien in web/; Aenderungen dort wirken beim naechsten Build.\n",
        "\n#pragma once\n\n#include <stddef.h>\n#include <stdint.h>\n\n",
    ]

    for symbol, pfad in QUELLEN.items():
        with open(pfad, "rb") as datei:
            roh = datei.read()

        # mtime=0, damit zwei Builds derselben Quelle byteweise dasselbe
        # Ergebnis liefern - sonst aendert sich der Header bei jedem Build und
        # erzwingt eine vollstaendige Neuuebersetzung.
        gepackt = gzip.compress(roh, compresslevel=9, mtime=0)
        etag = hashlib.sha1(roh).hexdigest()[:16]

        bytes_text = ", ".join("0x%02x" % b for b in gepackt)
        teile.append(
            "// %s: %d Bytes roh, %d Bytes gepackt\n" % (os.path.basename(pfad), len(roh), len(gepackt))
        )
        teile.append("static const uint8_t %s_GZ[] = {\n" % symbol)
        teile.append(textwrap.fill(bytes_text, 96, initial_indent="    ", subsequent_indent="    "))
        teile.append("\n};\n")
        teile.append("static const size_t %s_GZ_LEN = %d;\n" % (symbol, len(gepackt)))
        teile.append('static const char %s_ETAG[] = "%s";\n\n' % (symbol, etag))

    return "".join(teile)


def main():
    fehlend = [p for p in QUELLEN.values() if not os.path.isfile(p)]
    if fehlend:
        raise SystemExit("embed_web: Quelldatei fehlt: " + ", ".join(fehlend))

    neu = baue_header()

    alt = None
    if os.path.isfile(ZIEL):
        with open(ZIEL, "r", encoding="utf-8") as datei:
            alt = datei.read()

    if alt == neu:
        return

    os.makedirs(os.path.dirname(ZIEL), exist_ok=True)
    with open(ZIEL, "w", encoding="utf-8", newline="\n") as datei:
        datei.write(neu)
    print("embed_web: include/web_assets.h neu erzeugt")


main()
