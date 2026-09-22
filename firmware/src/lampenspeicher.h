// lampenspeicher.h - haelt den Lampenzustand ueber einen Neustart hinweg.
//
// Ohne das stuende die Saeule nach Stromausfall, Neustart oder Flashen dunkel,
// bis der naechste Hook zufaellig den Sollzustand schickt - und wartet Claude
// gerade auf Eingabe, feuert keiner. Mit dem Speicher zeigt sie nach dem Start
// wieder das, was sie zuletzt gezeigt hat; der naechste Hook korrigiert, falls
// sich inzwischen etwas geaendert hat.

#pragma once

namespace Lampenspeicher {

// Liest den zuletzt gespeicherten Zustand aus dem NVS und setzt ihn.
// Muss nach Lampen::begin() und vor Lampen::starteEffektTask() laufen, damit
// die Lampen direkt im wiederhergestellten Zustand angehen.
void lade();

// Aus loop() aufrufen. Schreibt verzoegert und nur bei echter Aenderung.
void tick();

}   // namespace Lampenspeicher
