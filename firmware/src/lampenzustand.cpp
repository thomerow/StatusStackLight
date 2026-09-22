#include "lampenzustand.h"

#include <WebServer.h>

#include "lampen.h"

const char *effektName(Effekt e)
{
    switch (e) {
        case Effekt::Blinken:   return "blink";
        case Effekt::Pulsieren: return "pulse";
        default:                return "steady";
    }
}

bool effektAusName(const char *name, Effekt &ziel)
{
    if (name == nullptr)              return false;
    if (!strcmp(name, "steady"))    { ziel = Effekt::Dauer;     return true; }
    if (!strcmp(name, "blink"))     { ziel = Effekt::Blinken;   return true; }
    if (!strcmp(name, "pulse"))     { ziel = Effekt::Pulsieren; return true; }
    return false;
}

// --- Hilfen fuer die Pruefung ----------------------------------------------

static Pruefergebnis fehler(const String &text)
{
    Pruefergebnis e;
    e.ok     = false;
    e.fehler = text;
    return e;
}

static String bereichstext(const char *feld, const String &wert, const String &von, const String &bis)
{
    return String("field '") + feld + "' out of range: got " + wert + ", expected " + von + "..." + bis;
}

// --- JSON ------------------------------------------------------------------

Pruefergebnis uebernimmJson(Lampenzustand &zustand, JsonObjectConst quelle, bool vollstaendig)
{
    // Auf einer Kopie arbeiten: schlaegt irgendein Feld fehl, bleibt der
    // uebergebene Zustand komplett unberuehrt.
    Lampenzustand neu = vollstaendig ? Lampenzustand{} : zustand;

    for (JsonPairConst feld : quelle) {
        const char *schluessel = feld.key().c_str();

        if (!strcmp(schluessel, "on")) {
            if (!feld.value().is<bool>()) {
                return fehler("field 'on' must be a boolean");
            }
            neu.an = feld.value().as<bool>();

        } else if (!strcmp(schluessel, "effect")) {
            Effekt e;
            if (!feld.value().is<const char *>() || !effektAusName(feld.value().as<const char *>(), e)) {
                return fehler("field 'effect' must be one of: steady, blink, pulse");
            }
            neu.effekt = e;

        } else if (!strcmp(schluessel, "brightness")) {
            if (!feld.value().is<int>()) {
                return fehler("field 'brightness' must be an integer");
            }
            int w = feld.value().as<int>();
            if (w < HELLIGKEIT_MIN || w > HELLIGKEIT_MAX) {
                return fehler(bereichstext("brightness", String(w), String(HELLIGKEIT_MIN), String(HELLIGKEIT_MAX)));
            }
            neu.helligkeit = (uint8_t) w;

        } else if (!strcmp(schluessel, "frequency")) {
            if (!feld.value().is<float>()) {
                return fehler("field 'frequency' must be a number");
            }
            float w = feld.value().as<float>();
            if (w < FREQUENZ_MIN || w > FREQUENZ_MAX) {
                return fehler(bereichstext("frequency", String(w, 2), String(FREQUENZ_MIN, 1), String(FREQUENZ_MAX, 1)));
            }
            neu.frequenz = w;

        } else if (!strcmp(schluessel, "duty")) {
            if (!feld.value().is<int>()) {
                return fehler("field 'duty' must be an integer");
            }
            int w = feld.value().as<int>();
            if (w < TASTGRAD_MIN || w > TASTGRAD_MAX) {
                return fehler(bereichstext("duty", String(w), String(TASTGRAD_MIN), String(TASTGRAD_MAX)));
            }
            neu.tastgrad = (uint8_t) w;

        } else if (!strcmp(schluessel, "id") || !strcmp(schluessel, "channel") ||
                   !strcmp(schluessel, "gpio") || !strcmp(schluessel, "name") ||
                   !strcmp(schluessel, "color") || !strcmp(schluessel, "level")) {
            // Vom Geraet selbst gelieferte Felder. Ein Client, der eine
            // gelesene Lampe unveraendert zurueckschickt, soll nicht an seiner
            // eigenen Antwort scheitern - deshalb stillschweigend ignorieren.

        } else {
            return fehler(String("unknown field: '") + schluessel + "'");
        }
    }

    zustand = neu;
    return Pruefergebnis{};
}

// --- Query-Parameter -------------------------------------------------------

Pruefergebnis uebernimmQuery(Lampenzustand &zustand, WebServer &server)
{
    // Der bequeme Weg: die Parameter in ein JSON-Objekt umfuellen und dieselbe
    // Pruefung wie oben laufen lassen. Ein zweiter Satz Grenzwerte waere die
    // sichere Quelle fuer spaetere Abweichungen zwischen beiden Wegen.
    JsonDocument doc;
    JsonObject   o = doc.to<JsonObject>();

    for (int i = 0; i < server.args(); i++) {
        const String name = server.argName(i);
        const String wert = server.arg(i);

        if (name == "on") {
            o["on"] = (wert == "1" || wert == "true");
        } else if (name == "effect") {
            o["effect"] = wert;
        } else if (name == "brightness") {
            o["brightness"] = wert.toInt();
        } else if (name == "frequency") {
            o["frequency"] = wert.toFloat();
        } else if (name == "duty") {
            o["duty"] = wert.toInt();
        } else if (name == "plain") {
            // Vom WebServer selbst eingefuegt, kein Nutzerparameter.
        } else {
            return fehler(String("unknown query parameter: '") + name + "'");
        }
    }

    // JsonObject wandelt sich implizit in JsonObjectConst - ein .as<>() gibt es
    // an dieser Klasse in ArduinoJson 7 nicht.
    return uebernimmJson(zustand, o, false);
}

// --- Ausgabe ---------------------------------------------------------------

void schreibeJson(const Lampenzustand &zustand, uint8_t index, JsonObject ziel)
{
    const LampenKanal &kanal = LAMPEN[index];

    ziel["id"]         = kanal.id;
    ziel["channel"]    = index + 1;        // Kanalnummer wie in der Gehaeuse-README
    ziel["gpio"]       = kanal.gpio;
    ziel["name"]       = kanal.name;
    ziel["color"]      = kanal.farbe;

    ziel["on"]         = zustand.an;
    ziel["effect"]     = effektName(zustand.effekt);
    ziel["brightness"] = zustand.helligkeit;
    ziel["frequency"]  = zustand.frequenz;
    ziel["duty"]       = zustand.tastgrad;

    // Momentan tatsaechlich ausgegebene Helligkeit (0...100). Damit kann das
    // Web-Interface anzeigen, was die Lampe gerade macht, statt nur, was
    // eingestellt ist.
    ziel["level"]      = Lampen::aktuellesNiveau(index);
}
