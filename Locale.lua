-- Locale: texts keyed by their English wording; German on German clients, English otherwise

local _, ns = ...

-- missing keys give back the English text itself
local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

if GetLocale() == "deDE" then
  local de = {
    -- settings page
    ["Enabled"] = "Aktiviert",
    ["Mark estimated damage on enemy health bars"] = "Geschätzten Schaden auf den Lebensleisten von Gegnern markieren",
    ["Nameplates"] = "Namensplaketten",
    ["Mark the damage on enemy nameplates"] = "Schaden auf gegnerischen Namensplaketten markieren",
    ["Target and focus"] = "Ziel und Fokus",
    ["Mark the damage on the target and focus frames"] = "Schaden auf dem Ziel- und dem Fokusfenster markieren",
    ["Own casts"] = "Eigene Zauber",
    ["Show the damage of your own cast on your target"] = "Schaden deines eigenen Zaubers auf deinem Ziel anzeigen",
    ["Crit extension"] = "Krit-Erweiterung",
    ["Add a bar part for a possible crit of your own cast, with your crit damage talents"] =
      "Fügt einen Balkenteil für einen möglichen kritischen Treffer deines Zaubers hinzu, inklusive deiner Talente für kritischen Schaden",
    ["Unit frame color"] = "Farbe Einheitenfenster",
    ["Bar color on target and focus frames; Custom opens the color picker"] =
      "Balkenfarbe auf Ziel- und Fokusfenster; \"Eigene...\" öffnet den Farbwähler",
    ["Nameplate color"] = "Farbe Namensplaketten",
    ["Bar color on nameplates; Custom opens the color picker"] =
      "Balkenfarbe auf Namensplaketten; \"Eigene...\" öffnet den Farbwähler",
    ["Unit frame crit color"] = "Krit-Farbe Einheitenfenster",
    ["Crit extension color on target and focus frames"] = "Farbe der Krit-Erweiterung auf Ziel- und Fokusfenster",
    ["Nameplate crit color"] = "Krit-Farbe Namensplaketten",
    ["Crit extension color on nameplates"] = "Farbe der Krit-Erweiterung auf Namensplaketten",
    ["Bar opacity (%)"] = "Balken-Deckkraft (%)",
    ["How solid the damage bar is"] = "Wie deckend der Schadensbalken ist",
    -- colors
    ["Dark red"] = "Dunkelrot",
    ["Red"] = "Rot",
    ["Orange"] = "Orange",
    ["Purple"] = "Lila",
    ["Blue"] = "Blau",
    ["Black"] = "Schwarz",
    ["Custom..."] = "Eigene...",
    -- commands and chat lines
    ["turn the estimates on"] = "Schätzungen einschalten",
    ["turn the estimates off"] = "Schätzungen ausschalten",
    ["show why no estimate appears"] = "zeigt, warum keine Schätzung erscheint",
    ["pick a free bar color"] = "freie Balkenfarbe wählen",
    ["set the bar opacity in percent"] = "Balken-Deckkraft in Prozent setzen",
    ["open the settings page"] = "Einstellungsseite öffnen",
    ["(turn on with %s)"] = "(einschalten mit %s)",
    ["opacity %s"] = "Deckkraft %s",
    ["on"] = "an",
    ["off"] = "aus",
    -- shared command texts
    ["commands:"] = "Befehle:",
    ["show this help"] = "diese Hilfe anzeigen",
    [" from %s to %s"] = " von %s bis %s",
    ["%s must be a number"] = "%s muss eine Zahl sein",
    ["%s must be one of %s"] = "%s muss eines von %s sein",
    ["unknown option --%s"] = "unbekannte Option --%s",
    ["too many arguments"] = "zu viele Argumente",
    ["missing %s"] = "%s fehlt",
    ["%s - usage: %s"] = "%s - Aufruf: %s",
    ["unknown command: %s - see %s help"] = "unbekannter Befehl: %s - siehe %s help",
  }
  for key, text in pairs(de) do
    L[key] = text
  end
end
