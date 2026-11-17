<p align="center">
  <img src="Ressources/AppIcon.png" width="140" alt="Icône de Majordome : une touche orange avec un nœud papillon">
</p>

<h1 align="center">Majordome</h1>

<p align="center">Ton Mac, réglé pour aller vite.<br>Une seule app dans la barre des menus, qui ne fait presque rien quand tu ne fais rien.</p>

<p align="center">
  <a href="https://github.com/claudioelbikai-tech/Majordomme/releases/latest/download/Majordome.dmg"><b>Télécharger Majordome.dmg</b></a>
  · macOS 13 ou plus récent · Apple Silicon et Intel
</p>

---

## Installer

1. Télécharge **Majordome.dmg** et ouvre-le.
2. Glisse **Majordome** dans le dossier **Applications**.
3. Ouvre Majordome depuis Applications.

Au premier lancement, macOS indique qu'il ne peut pas vérifier l'app : elle n'est pas encore signée avec un compte développeur Apple. Va dans **Réglages Système → Confidentialité et sécurité**, puis clique sur **Ouvrir quand même** en face de Majordome. Tu ne le feras qu'une fois.

La fenêtre de bienvenue te guide ensuite : accès Accessibilité, notifications, ouverture au démarrage.

## Ce qu'il fait

**Verr. Maj devient la touche Hyper.** Maintenue avec une lettre, elle lance une action ; tapée seule, elle fait Échap. Sans pilote : un réglage intégré à macOS.

| Raccourci | Action |
|---|---|
| Verr. Maj + Espace | Toutes les actions et les scènes |
| Verr. Maj + G | Session de focus : bouclier anti-distraction, ligne de temps, fond noir |
| Verr. Maj + P / O | Mettre de côté tes fenêtres et une phrase, puis reprendre exactement là |
| Verr. Maj + J | Une lettre sur chaque fenêtre pour y sauter |
| Verr. Maj + H | Tableau de bord : heure, priorité, focus, batterie |
| Verr. Maj + I | Noter une idée sans quitter ce que tu fais |
| Verr. Maj + V | Transformer le presse-papiers |
| Verr. Maj + U / L / D | Monotâche · voile de confidentialité · mode sombre |
| Verr. Maj + T F B X N C R E S K | Ouvrir tes apps, ou les cacher si elles sont déjà devant |
| ⌃⌥ + flèches | Fenêtre en moitié, puis en tiers en rappuyant ; ⌃⌥ ↩ plein écran et retour |

**Et tout seul :** ta priorité n° 1 dans la barre des menus, les traqueurs retirés des liens que tu copies, les captures d'écran nommées d'après l'app, les téléchargements rangés par type, le temps de réunion compté quand la caméra s'allume, un rapport chaque soir.

## Sobre et privé

- Majordome réagit aux signaux de macOS (app ouverte, fichier modifié, caméra, réveil) et dort entre deux. Au repos, il regarde seulement le presse-papiers toutes les 2 secondes et l'app active une fois par minute.
- Rien n'est envoyé sur Internet. Tes journaux restent dans `~/.majordome` sur ton Mac.

## Fabriquer soi-même

Sur un Mac avec Xcode :

```bash
swift test
./outils/construire.sh
open build/Majordome.dmg
```

Chaque modification envoyée sur GitHub relance la même fabrication sur un Mac de GitHub et publie le DMG dans **Releases**.

| Dossier | Contenu |
|---|---|
| `Sources/MajordomeCore` | Logique sans interface (liens, texte, journaux, géométrie), testée par `swift test` |
| `Sources/Majordome` | L'app : barre des menus, touche Hyper, fenêtres, focus, fenêtres SwiftUI |
| `Tests` | Tests de la logique |
| `Ressources` | Info.plist, icône, fond de la fenêtre du DMG |
| `outils` | Fabrication de l'app et du DMG, notes de version |
