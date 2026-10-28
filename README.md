# HomeTrainer To Home Assistant — app iOS

App iOS (SwiftUI) qui se connecte en Bluetooth à un home trainer (Wahoo KICKR ou
tout home trainer FTMS / Cycling Power) et envoie puissance, cadence, vitesse,
fréquence cardiaque, distance et énergie à Home Assistant.

Elle fonctionne avec l'intégration
[HomeTrainer To Home Assistant](https://github.com/lobwick/hometrainer-to-home-assistant-integration),
qui crée l'appareil et ses entités (zone de puissance, « sur le vélo », FTP, couleurs…).

## Mise en route

1. Installer l'intégration via HACS et l'ajouter dans Home Assistant.
2. Copier l'adresse du webhook affichée par l'intégration.
3. Dans l'app : ⚙︎ → coller l'adresse → **Tester la connexion**.
4. Scanner, choisir le home trainer : les mesures partent toutes les secondes.

## Build

Le projet Xcode est généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen)
depuis `project.yml` :

```bash
xcodegen generate
open HomeTrainerHA.xcodeproj
```
