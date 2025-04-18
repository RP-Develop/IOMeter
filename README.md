# IOMeter - Fhem
## IOMeter - Fhem Integration

**76_IOMeter.pm**

Das Modul verbindet sich lokal mit der Bridge eines Ablesekopfes von IOMeter für Energiezähler. Die API von IOMeter wird dafür benutzt. Dokumentation unter [GitHub iometer.py/docs/api.md](https://github.com/iometer-gmbh/iometer.py/blob/main/docs/api.md)

**update**

`update add https://raw.githubusercontent.com/RP-Develop/IOMeter/main/controls_IOMeter.txt`

### Voraussetzung:
IOMeter ist in Betrieb genommen und liefert Daten in die App vom Hersteller.

### Fhem  - 76_IOMeter.pm
`define <name> IOMeter <ip>`

Parameter <ip> ist die lokale IP-Adresse welche die Bridge bekommen hat, beim Einrichten.

`set <name> Update`

Ruft alle Readings und Statuswerte von der Bridge ab.

`set <name> UpdateReading`

Ruft nur dies Readings (Energiewerte) von der Bridge ab.

`set <name> UpdateStatus`

Ruft nur den aktuellen Status ab, welcher Informationen über den Zustand der Verbindungen beinhaltet.

`get <name> Reading`

Zeigt die Antwort der Reading Abfrage.

`get <name> Status`

Zeigt die Antwort der StatusAbfrage.

`attr <name> UpdateInterval`

default = 0;
Bei einem Wert >0 werden nach angegebener Zeit die Readings und Statuswerte von der Bridge geholt.

`attr <name> expert`

default = 0;
Bei Wert 1, werden die alle Readings zusätzlich als OBIS Wert angezeigt.


### Quellen
[GitHub iometer.py/docs/api.md](https://github.com/iometer-gmbh/iometer.py/blob/main/docs/api.md)
