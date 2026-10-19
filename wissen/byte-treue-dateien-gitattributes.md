---
name: byte-treue-dateien-gitattributes
description: "Fremddateien, deren Prüfsumme zählt, brauchen `-text` in .gitattributes — sonst schreibt `* text=auto eol=lf` sie beim Einchecken um"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 815a2566-49de-45b5-a8a5-5e058405e4d5
  modified: 2026-09-13T11:34:08.426Z
---

Die `.gitattributes` des Hauptrepos beginnt mit `* text=auto eol=lf`. Jede eingecheckte
Datei mit CRLF wird dadurch beim `git add` **umgeschrieben** — der Blob im Index trägt
dann einen anderen sha256 als die Datei auf der Platte.

Aufgefallen am 13.09.2026 beim Einchecken der übernommenen iSFP-Druckschicht: drei der
161 Dateien (`iSFPProjekt.xsd`, `enums.js`, `qwebchannel.js`) haben CRLF. Ihr Manifest
`HERKUNFT.json` hält je Datei den sha256 fest, und `VendorUnveraendertTest` prüft dagegen.
Ohne Gegenmaßnahme wäre der Test hier grün geblieben und **im nächsten Klon rot** —
Dateien gleich aussehend, Prüfsumme falsch.

    resources/isfp/vendor/** -text

**Why:** Zeilenenden sind für Quelltext eine Formsache und für byte-treu übernommene
Fremddateien eine Inhaltsfrage. Wer die Unterscheidung nicht trifft, zerstört genau die
Eigenschaft, die er zusichern wollte — und zwar an einem Ort, an dem niemand sie vermutet.

**How to apply:** Immer wenn Dateien ins Repo kommen, deren **Prüfsumme** zählt statt
ihres Inhalts — übernommene Ausgabeschichten, Testabzüge, Binärvorlagen — vorher eine
`-text`-Regel setzen. Danach gegenprüfen, nicht annehmen: je Datei
`sha256sum <datei>` gegen `git show :<datei> | sha256sum`. Betrifft auch die Skripte in
`bauteile/`, die CRLF haben.

Verwandt: [[git-checkout-nie-blind]], [[isfp-webformular-stand]]
