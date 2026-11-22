# SyntX Guardian v2.1 — bot MT5 pour les indices synthétiques Weltrade

> ⚠️ **À lire avant tout.** Les indices synthétiques Weltrade sont générés par un
> algorithme du broker, qui est aussi votre contrepartie. Aucun bot ne peut
> garantir un profit. Ce projet fournit un bot **discipliné** et les outils
> pour **mesurer** honnêtement si une stratégie a un avantage réel avant d'y
> mettre de l'argent. Ce n'est pas un conseil financier.

## Contenu

| Fichier | Rôle |
|---|---|
| `mt5/SyntX_Guardian.mq5` | Expert Advisor MetaTrader 5 (4 stratégies, réglages par indice, gestion du risque partagée et persistante, journal) |
| `mt5/ExportBars.mq5` | Script : exporte en une fois tous les indices autorisés et leurs caractéristiques réelles |
| `backtest/calibrate.py` | **Calibration** : choisit, pour chaque indice, l'unité de temps, la stratégie et les réglages sur vos données, et désactive les indices sans avantage |
| `backtest/syntx_backtest.py` | Backtester : comparaison des stratégies, optimisation, verdict automatique |
| `backtest/analyze_trades.py` | Analyse du journal de trades de l'EA (phase démo puis réel) |
| `backtest/check_indicators.py` | Vérifie que le backtester calcule les indicateurs exactement comme MT5 |
| `backtest/test_syntx.py` | Tests automatiques (cohérence EA/Python, absence de triche sur le futur, etc.) |

## Nouveautés de la v2.1

**Rentabilité.** Le seul levier qui ne soit pas un pari : ne trader que ce
qui a fait ses preuves, avec les réglages propres à chaque indice.

- **Calibration par indice** (`calibrate.py`) : pour chaque indice, le
  meilleur couple unité de temps × stratégie × réglages est choisi sur le
  début de l'historique. Il est ensuite testé **une seule fois** sur la fin,
  jamais vue. L'indice est activé seulement s'il passe tous les seuils.
- **Les caractéristiques réelles de chaque indice** (spread, swap, distances
  minimales, lots) sont exportées depuis MT5 et prises en compte dans les tests.
- **Le backtest suit l'EA au plus près** :
  - ADX de Wilder des deux côtés ; ATR en moyenne simple, comme MT5 ;
  - trailing stop une fois par barre ;
  - swap à chaque nuit ;
  - même filtre de spread ;
  - même plafond de 20 trades par jour.
- **La parité des indicateurs se vérifie** avec `check_indicators.py`, qui
  compare les valeurs calculées par MT5 lui-même à celles du backtester.
- **Écarts connus restants** :
  - l'EA place stop et objectif à partir du prix d'exécution (ask/bid), le
    backtester à partir de l'ouverture de la barre ;
  - le plafond de risque total et la perte journalière, qui portent sur tout
    le portefeuille, ne sont pas simulés.
- **Les indices non calibrés ne tradent pas sur un compte réel.** Sur compte
  réel, un indice absent du fichier de calibration est refusé
  (`InpRequireCalibReal`). En démo et dans le testeur, il trade avec les
  préréglages intégrés, avec un avertissement.

**Robustesse.**

- **État de risque propre à chaque compte.** Un compte démo et un compte
  réel sur le même terminal ne partagent plus le coupe-circuit.
- **Dépôts et retraits pris en compte** : l'equity est suivie nette des
  dépôts et retraits (lus dans l'historique du compte). Un retrait ne
  déclenche donc jamais le coupe-circuit.
- **Contrôles avant chaque ordre** :
  - mode de trading du symbole (fermé, achat seul…) ;
  - distances minimales et niveau de gel du broker ;
  - marge disponible ;
  - lot maximal ;
  - code retour de chaque ordre.
- **Une fermeture qui échoue est retentée à chaque tick.**
- **Données pas prêtes = signal pas perdu** : la barre n'est traitée qu'une
  fois les indicateurs disponibles.
- **Paramètres vérifiés au démarrage** ; interrupteur d'activation par indice.
- **Tests automatiques** : les préréglages de l'EA et du backtester ne
  peuvent plus diverger sans que les tests échouent.

## Nouveautés de la v2.0

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

Tout se règle sans toucher au code. Pour chaque indice, l'EA applique, par
ordre de priorité :

1. **le fichier de calibration** `SyntX_Guardian_presets.csv` (dossier commun
   de MT5), produit par `calibrate.py`. Un indice qui y est marqué désactivé
   ne trade pas ;
2. **les entrées** « Unite de temps par indice » et « Strategie par indice » ;
3. **les préréglages intégrés** ci-dessous.

Les interrupteurs du groupe « Activation par indice » permettent aussi de
couper un indice à la main.

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

Ces protections sont partagées entre **tous les graphiques du même compte qui
ont le même numéro magique** (laissez `InpMagic` identique partout) et **conservées après
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
  `false`. Les dépôts et retraits sont pris en compte automatiquement.
- **L'état est propre à chaque compte** (numéro de compte + numéro magique) :
  démo et réel sur le même terminal ne se mélangent pas.
- **Contrôles avant chaque ordre** : marge (un trade n'utilise pas plus de
  50 % de la marge libre), distances minimales du broker, mode de trading du
  symbole, lot maximal.
- **Le bot mesure l'equity de tout le compte.** Utilisez un compte dédié,
  sans trades manuels ni autres robots.

## Mode d'emploi

### 1. Installer

1. Dans MT5 : *Fichier → Ouvrir le dossier des données → MQL5*.
2. Copiez `SyntX_Guardian.mq5` dans `Experts/` et `ExportBars.mq5` dans `Scripts/`.
3. Compilez les deux fichiers dans MetaEditor (F7). **S'il y a des erreurs de
   compilation, copiez-les-moi** : le code n'a pas pu être compilé ici.
4. *Outils → Options → Graphiques → Barres max. dans le graphique* : **Illimité**,
   sinon l'historique exporté est tronqué.

### 2. Exporter les données (une seule fois)

Lancez le script `ExportBars` sur n'importe quel graphique. Il exporte tous les
indices autorisés (GainX en M1 ; FX/SFX Vol en M15 et H1) et leurs
caractéristiques réelles dans *Dossier commun → Files → SyntX_data*.
(Dossier commun : *Fichier → Ouvrir le dossier des données*, remonter d'un
niveau, puis *Common*.)

### 3. Vérifier les indicateurs, puis calibrer

```bash
pip install pandas numpy
python backtest/check_indicators.py "<Dossier commun>/Files/SyntX_data"
python backtest/calibrate.py "<Dossier commun>/Files/SyntX_data"
```

**Si `check_indicators.py` signale un écart, envoyez-moi le résultat avant
de calibrer** : le backtest ne correspondrait pas à l'EA.

Pour chaque indice, le script affiche :
- les essais sur la période d'apprentissage ;
- le choix retenu ;
- le résultat sur la période jamais vue ;
- la décision **ACTIVE** ou **DESACTIVE**.

Il écrit `SyntX_Guardian_presets.csv` : copiez-le dans *Dossier commun → Files*.
Un indice sans données ou sans avantage validé est désactivé. Une unité de
temps dont l'historique est trop court pour atteindre 100 trades sur la
période de test est écartée : exportez plus d'historique si besoin.

Le plafond de 20 trades par jour s'applique aussi à la calibration. Si vous
changez `InpMaxTradesPerDay` dans l'EA, passez la même valeur à
`calibrate.py --max-trades-day`.

Pour explorer un indice à la main :

```bash
python backtest/syntx_backtest.py FX_Vol_40_M15.csv --point 0.01 --compare
python backtest/syntx_backtest.py FX_Vol_40_M15.csv --point 0.01 --strategy breakout --optimize
```

### 4. Confirmer dans le testeur MT5

Mode **« Chaque tick basé sur des ticks réels »**, sur la période jamais vue
(les 30 % les plus récents de l'historique), avec le fichier de calibration en
place. Les résultats doivent être proches de ceux de `calibrate.py`.

### 5. Compte démo (3 mois minimum), puis petit compte réel (3 mois)

Posez l'EA sur un graphique par indice **activé**, avec le même numéro magique
partout. Le journal est écrit dans *Dossier commun → Files →
`SyntX_Guardian_trades.csv`*.

```bash
python backtest/analyze_trades.py SyntX_Guardian_trades.csv --expected "FX Vol 40=0.15"
```

Indiquez dans `--expected` le gain moyen « E test » donné par `calibrate.py`.
L'écart doit rester dans ±30 %.

### Tests automatiques

```bash
cd backtest && python -m pytest test_syntx.py -q
```

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

**Un seul test final par indice.** La calibration choisit le réglage sur
l'apprentissage, puis teste **ce seul réglage** sur la période jamais vue.
Tester plusieurs réglages sur cette période et garder le meilleur
reviendrait à tricher : le hasard finirait par en faire passer un.

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
