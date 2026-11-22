# SyntX Guardian v2 — bot MT5 pour les indices synthétiques Weltrade

> ⚠️ **À lire avant tout.** Les indices synthétiques Weltrade sont générés par un
> algorithme du broker, qui est aussi votre contrepartie. Aucun bot ne peut
> garantir un profit. Ce projet fournit un bot **discipliné** et les outils
> pour **mesurer** honnêtement si une stratégie a un avantage réel avant d'y
> mettre de l'argent. Ce n'est pas un conseil financier.

## Contenu

| Fichier | Rôle |
|---|---|
| `mt5/SyntX_Guardian.mq5` | Expert Advisor MetaTrader 5 (4 stratégies, gestion du risque partagée et persistante, journal des trades) |
| `mt5/ExportBars.mq5` | Script qui exporte l'historique d'un graphique en CSV |
| `backtest/syntx_backtest.py` | Backtester : comparaison des stratégies, optimisation, validation hors échantillon, verdict automatique |
| `backtest/analyze_trades.py` | Analyse du journal de trades de l'EA (phase démo puis réel) |

## Nouveautés de la v2

| Défaut de la v1 | Correction |
|---|---|
| Stop journalier et coupe-circuit oubliés au redémarrage | Mémorisés dans les variables globales du terminal : ils survivent à un redémarrage de MT5 ou à un changement de paramètres |
| Aucun plafond de risque entre les graphiques | Risque total ouvert plafonné (2 % par défaut), et limites partagées entre tous les graphiques qui ont le même numéro magique |
| Pas de mesure de la performance réelle | Journal CSV de chaque trade clos (résultat en R), plus `analyze_trades.py` |
| Une seule stratégie pour FX/SFX Vol | Trois stratégies au choix par indice : croisement d'EMA, cassure de canal, retour à la moyenne |
| Pas de sortie quand la tendance s'inverse | Sortie sur croisement inverse (EMA) ou sur cassure inverse (canal) |
| Backtester biaisé en défaveur du suivi de tendance | Exécution neutre : écarts de prix favorables et défavorables traités de la même façon |
| Un hasard pouvait passer pour un avantage | Verdict automatique plus strict (t > 2,5, stabilité sur 4 périodes) |
| Spread non contrôlé par rapport au stop | Trade ignoré si le spread dépasse 10 % de la distance du stop |

## Indices autorisés

Le bot ne trade **que** les indices suivants. Il refuse de démarrer sur tous
les autres (PainX, FX Vol 80/99, FlipX, BreakX…), jugés trop volatils.

- **FX Vol 20, 40, 60** et **SFX Vol 20, 40, 60** : stratégie au choix (voir plus bas).
- **GainX 400, 600, 800, 999, 1200** : stratégie DRIFT.

L'indice est reconnu à partir du nom du symbole (`FX Vol 40`, `SFX Vol 20`,
`GainX 999`…).

## Les stratégies

| Stratégie | Pour | Entrée | Sortie |
|---|---|---|---|
| **Croisement d'EMA** | FX / SFX Vol | L'EMA rapide croise l'EMA lente, avec un ADX assez fort | Stop, objectif, trailing stop, ou croisement inverse |
| **Cassure de canal** | FX / SFX Vol | La clôture casse le plus haut (ou le plus bas) des N dernières barres | Stop, objectif, trailing stop, ou cassure inverse d'un canal deux fois plus court |
| **Retour à la moyenne** | FX / SFX Vol | La clôture sort de la bande de Bollinger avec un RSI extrême, en marché sans tendance (ADX faible) | Retour à la moyenne de Bollinger, stop, ou 40 barres au maximum |
| **DRIFT** | GainX | Achat dans le sens de la dérive, confirmé par une EMA, hors période de pic | Stop, objectif, ou nombre maximal de barres |

Pour GainX, le bot **ne trade pas** si les données montrent des pics
haussiers, c'est-à-dire si l'indice ne se comporte pas comme un GainX.

## Réglages par indice

Tout se règle dans les paramètres de l'EA, sans toucher au code.

**Unité de temps** (groupe « Unite de temps par indice ») :
H1 pour les indices 20, M15 pour les 40 et 60, M1 pour GainX. L'EA affiche un
avertissement si GainX est réglé au-delà de M5.

**Stratégie** (groupe « Strategie par indice ») : croisement d'EMA par défaut
pour les 6 indices FX/SFX. Choisissez-la d'après les résultats de
`--compare` (voir plus bas).

**Préréglages FX / SFX Vol** (le risque effectif = risque de base × coefficient) :

| Indice | UT | Risque | EMA rapide / lente | ADX min | Stop / objectif / trailing (ATR) | Canal | Bollinger / RSI / ADX max |
|---|---|---|---|---|---|---|---|
| FX Vol 20  | H1  | ×1,0 | 20 / 100 | 20 | 2,0 / 4,0 / 2,5 | 20 | 2,0 / 30 / 25 |
| FX Vol 40  | M15 | ×1,0 | 20 / 100 | 22 | 2,2 / 4,0 / 2,5 | 30 | 2,0 / 30 / 25 |
| FX Vol 60  | M15 | ×0,8 | 30 / 150 | 25 | 2,5 / 4,5 / 3,0 | 40 | 2,2 / 28 / 25 |
| SFX Vol 20 | H1  | ×1,0 | 20 / 120 | 22 | 2,2 / 4,0 / 2,8 | 25 | 2,0 / 30 / 25 |
| SFX Vol 40 | M15 | ×0,8 | 25 / 150 | 25 | 2,5 / 4,5 / 3,0 | 35 | 2,2 / 28 / 25 |
| SFX Vol 60 | M15 | ×0,6 | 30 / 200 | 28 | 3,0 / 5,0 / 3,5 | 45 | 2,2 / 28 / 25 |

**Préréglages GainX (M1)** :

| Indice | Risque | Barres analysées | EMA | Attente après pic | Stop | Objectif | Sortie après |
|---|---|---|---|---|---|---|---|
| GainX 400  | ×0,7 | 2000 | 30 | 2 barres | 1,3 pic | 0,5 pic | 30 barres |
| GainX 600  | ×0,8 | 2500 | 40 | 3 barres | 1,2 pic | 0,6 pic | 45 barres |
| GainX 800  | ×0,9 | 3000 | 50 | 3 barres | 1,2 pic | 0,6 pic | 60 barres |
| GainX 999  | ×1,0 | 3500 | 50 | 4 barres | 1,2 pic | 0,6 pic | 80 barres |
| GainX 1200 | ×1,0 | 4000 | 60 | 4 barres | 1,1 pic | 0,7 pic | 100 barres |

> **Ces valeurs sont des points de départ raisonnés, pas des réglages
> validés.** La nature exacte des SFX Vol n'est pas documentée publiquement.
> Validez chaque indice sur ses propres données (voir plus bas), puis ajustez
> `LoadPreset()` (EA) et `PRESETS` (Python), qui doivent rester identiques.
> Pour tout régler à la main : `InpUsePresets = false`.

## Gestion du risque

Ces protections sont partagées entre **tous les graphiques qui ont le même
numéro magique** (laissez `InpMagic` identique partout) et **conservées après
un redémarrage** de MT5 :

| Protection | Défaut | Effet |
|---|---|---|
| Risque par trade | 0,5 % × coefficient de l'indice | Taille de lot calculée. Si même le lot minimum dépasse ce risque, le trade est ignoré. |
| Risque total ouvert | 2 % | Aucun nouveau trade si l'ensemble des positions du bot risquerait plus |
| Perte journalière | 3 % | Plus de nouveau trade jusqu'au lendemain (heure du serveur) |
| Coupe-circuit | 15 % depuis le plus haut | Ferme tout et arrête **tous** les graphiques |
| Trades par jour | 20 par indice | — |
| Spread | ≤ 10 % du stop | Trade ignoré sinon |

- **Rien n'est jamais augmenté après une perte** : ni martingale, ni grille.
- **Le coupe-circuit ne se réarme qu'à la main.** Analysez d'abord les
  résultats, puis passez `InpResetHalt = true` une fois, et remettez-le à
  `false`. Faites de même après un retrait d'argent, qui ferait sinon
  ressembler le compte à une perte.
- **Le bot mesure l'equity de tout le compte.** Utilisez un compte dédié,
  sans trades manuels ni autres robots.

## Mode d'emploi

### 1. Installer

1. Dans MT5 : *Fichier → Ouvrir le dossier des données → MQL5*.
2. Copiez `SyntX_Guardian.mq5` dans `Experts/` et `ExportBars.mq5` dans `Scripts/`.
3. Compilez les deux fichiers dans MetaEditor (F7).
4. Posez l'EA sur un graphique par indice, avec le même numéro magique partout.

### 2. Valider chaque indice (obligatoire)

1. **Exportez l'historique.** Ouvrez un graphique de l'indice dans son unité
   de temps, faites défiler pour charger l'historique (1 an minimum, 2-3 ans
   pour H1), puis lancez `ExportBars`. Le CSV est écrit dans `MQL5/Files/`.
2. **Comparez les stratégies.** Pour FX/SFX Vol :

   ```bash
   pip install pandas numpy
   python backtest/syntx_backtest.py FX_Vol_40_M15.csv --point 0.01 --compare
   ```

   Pour GainX : `python backtest/syntx_backtest.py GainX_999_M1.csv --point 0.01`

   `--point` correspond à la taille du point affichée par `ExportBars`.
   Il sert à convertir le spread réel en prix.
3. **Optimisez la meilleure stratégie et vérifiez-la sur des données jamais vues :**

   ```bash
   python backtest/syntx_backtest.py FX_Vol_40_M15.csv --point 0.01 --strategy breakout --optimize
   ```

   Seul un réglage marqué **VALIDE hors échantillon** est conservé. Les
   indices qui échouent sont retirés : mieux vaut 2 indices rentables que
   7 perdants.
4. **Confirmez dans le testeur MT5** (Ctrl+R) en mode **« Chaque tick basé sur
   des ticks réels »**.

### 3. Compte démo (3 mois minimum), puis petit compte réel (3 mois)

Le journal se trouve dans le dossier commun de MT5 :
*Fichier → Ouvrir le dossier des données → remonter d'un niveau → Common → Files →
`SyntX_Guardian_trades.csv`*.

```bash
python backtest/analyze_trades.py SyntX_Guardian_trades.csv --expected "FX Vol 40=0.15"
```

Le script vérifie les mêmes seuils que le backtester, et l'écart avec le gain
moyen attendu (au plus ±30 %).

## Les seuils de validation

Un indice n'est conservé que s'il passe **tous** ces seuils, d'abord sur les
données jamais vues, puis en démo :

| Critère | Seuil |
|---|---|
| Gain moyen par trade (`E`) | > +0,10 R |
| Fiabilité statistique (`t`) | > 2,5 |
| Nombre de trades | ≥ 100 |
| Profit factor (gains totaux / pertes totales) | > 1,3 |
| Perte maximale depuis un plus haut | < 15 % |
| Stabilité | gagnant sur au moins 3 des 4 périodes successives |

**Pourquoi t > 2,5 et pas 2.** On teste jusqu'à 27 combinaisons indice ×
stratégie. Avec t > 2, environ une sur 40 « passe » par pur hasard. Lors des
tests, un croisement d'EMA sur un marché **purement aléatoire** a obtenu
E = +0,20 R, t = 2,15, 4 périodes sur 4 gagnantes : un faux positif parfait,
que le seuil de 2,5 rejette.

## Ce que les tests de contrôle ont montré

Le backtester contient un **simulateur équitable** (`--simulate`), qui produit
un marché sans aucun avantage exploitable. Il sert à vérifier l'outil :

- **Sans spread, toutes les stratégies tournent autour de 0 R** sur données
  équitables (entre −0,07 et +0,08 R selon le tirage). Le modèle d'exécution
  n'est donc ni optimiste ni pessimiste.
- **La stratégie GainX gagne 75 % de ses trades mais perd au total**
  (E ≈ −0,04 R) : les petits gains fréquents sont effacés par les pics.
- **Un vrai biais est détecté** quand on l'injecte (`--edge 0.3` :
  E = +0,13 R, t = 10, verdict « PROMETTEUR »).
- **Peu de trades, résultats trompeurs.** Avec ~25 trades, un tirage
  aléatoire a donné t = 2,5. C'est pourquoi il faut au moins 100 trades.

**Conclusion honnête.** La rentabilité dépend entièrement de l'existence d'un
biais dans l'algorithme de Weltrade, ce que seules les vraies données peuvent
dire. Ce projet donne les moyens de le mesurer sans se tromper, et protège le
capital si l'avantage n'existe pas.
