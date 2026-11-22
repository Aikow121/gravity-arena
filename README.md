# Gravity Arena — FPS à gravité personnelle (Godot 4)

Des joueurs s'affrontent au pistolet dans une grande salle fermée. Chaque joueur peut
**changer sa propre gravité** : la surface qu'il vise devient son nouveau sol, ce qui
permet de courir sur les murs, au plafond ou sur les faces du cube flottant central.

## Lancer le projet
1. Installer **Godot 4.3 ou plus récent** (version standard, pas besoin de .NET).
2. Dans le gestionnaire de projets : *Importer* → choisir `project.godot`.
3. Appuyer sur **F5**.

## Modes de jeu
- **Solo** : vous contre 0 à 7 bots (ils changent aussi de gravité).
- **Héberger** : ouvre une partie sur le port UDP **7777** (les bots choisis sont ajoutés).
- **Rejoindre** : entrer l'adresse IP de l'hôte. En réseau local, utiliser l'IP locale de
  l'hôte (ex. `192.168.1.x`). Par Internet, l'hôte doit rediriger le port UDP 7777 sur sa box.

## Commandes
| Action | Touche |
|---|---|
| Se déplacer | ZQSD (AZERTY) / WASD (QWERTY) / flèches |
| Sprint (en avançant) | Maj (maintenir) |
| Sauter / double saut | Espace (appuyer à nouveau en l'air) |
| Glissade (en courant) | Ctrl ou C |
| Tirer | Clic gauche |
| Gravité vers la surface visée | Clic droit ou **E** (cercle vert = possible) |
| Revenir à la gravité normale | **F** |
| Recharger | R |
| Tableau des scores | Tab (maintenir) |
| Libérer la souris | Échap (cliquer pour reprendre) |

Pendant un changement de gravité, la caméra garde sa position et sa direction : seul l'horizon pivote.
Astuce : glisser puis sauter garde l'élan de la glissade.

Pistolet : 12 balles, 25 dégâts au corps, 60 à la tête, 100 PV par joueur, réapparition après 2,5 s.

## Organisation du code
- `scripts/main.gd` — menu, réseau ENet, apparition des joueurs, dégâts, morts et scores
  (le serveur fait autorité sur la vie et les scores).
- `scripts/player.gd` — déplacement avec gravité orientable, rotation douce du corps,
  tir par rayon, IA des bots, synchronisation de la position.
- `scripts/arena.gd` — génération de la salle (faces colorées avec quadrillage,
  piliers, poutres, cube central, plateformes, points d'apparition sur les 6 faces).
- `scripts/hud.gd` — viseur, PV, munitions, gravité actuelle, fil des éliminations, scores.

## Idées pour aller plus loin
- Sons (tir, impact, changement de gravité) avec `AudioStreamPlayer3D`.
- Modèles 3D et animations à la place des capsules.
- Limite de changements de gravité (jauge) pour plus de stratégie.
- Modes de jeu : match à 20 éliminations, équipes, capture de drapeau.
- Validation des tirs côté serveur pour limiter la triche.
