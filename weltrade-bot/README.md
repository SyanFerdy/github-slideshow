# SyntX Guardian — bot MT5 pour les indices synthétiques Weltrade

> ⚠️ **À lire avant tout.** Les indices synthétiques Weltrade sont générés par un
> algorithme du broker, qui est aussi votre contrepartie. Aucun bot ne peut
> garantir un profit. Ce projet ne promet pas un « bot rentable » : il fournit
> un bot **discipliné** et un outil pour **mesurer** honnêtement si une
> stratégie a un avantage réel avant d'y mettre de l'argent.
> Ce n'est pas un conseil financier.

## Contenu

| Fichier | Rôle |
|---|---|
| `mt5/SyntX_Guardian.mq5` | Expert Advisor MetaTrader 5 (deux moteurs + gestion du risque) |
| `mt5/ExportBars.mq5` | Script qui exporte l'historique d'un graphique en CSV |
| `backtest/syntx_backtest.py` | Backtester Python : analyse des pics, backtest, optimisation avec validation hors échantillon |

## Indices autorisés

Le bot ne trade **que** les indices suivants. Il refuse de démarrer sur tous
les autres (PainX, FX Vol 80/99, FlipX, BreakX…), jugés trop volatils.

- **FX Vol 20, 40, 60** et **SFX Vol 20, 40, 60** : moteur TREND.
- **GainX 400, 600, 800, 999, 1200** : moteur DRIFT.

L'indice est reconnu à partir du nom du symbole (`FX Vol 40`, `SFX Vol 20`,
`GainX 999`…).

## Les deux moteurs

**TREND (FX Vol / SFX Vol).** Le bot entre sur un croisement d'EMA
rapide/lente filtré par l'ADX. Le stop et l'objectif sont en ATR, avec un
trailing stop.

**DRIFT (GainX).** GainX monte lentement puis chute par pics brutaux, en
moyenne tous les N ticks. Le bot :

- trade dans le sens de la dérive (à l'achat), confirmé par une EMA ;
- place son stop et son objectif en multiples de la taille moyenne d'un pic ;
- ferme la position après un nombre maximal de barres ;
- **par sécurité, ne trade pas** si les données montrent des pics haussiers,
  c'est-à-dire si l'indice ne se comporte pas comme un GainX.

## Unité de temps par indice

L'unité de temps de chaque indice se règle dans le groupe
**« Unite de temps par indice »** des paramètres de l'EA, sans toucher au code :

| Paramètre | Indice | Par défaut |
|---|---|---|
| `InpTF_FXVol20` / `InpTF_SFXVol20` | FX / SFX Vol 20 | **H1** |
| `InpTF_FXVol40` / `InpTF_SFXVol40` | FX / SFX Vol 40 | **M15** |
| `InpTF_FXVol60` / `InpTF_SFXVol60` | FX / SFX Vol 60 | **M15** |
| `InpTF_GainX` | GainX | **M1** (l'EA affiche un avertissement au-delà de M5) |

Le bot calcule ses signaux dans cette unité de temps, quel que soit le
graphique sur lequel il est posé. Pour comparer M15 et H1 sur un indice,
lancez-le deux fois dans le testeur MT5 avec chaque valeur. Avec le
backtester Python, exportez les barres dans chaque unité de temps et lancez
le script sur chaque fichier.

## Préréglages par indice

Chaque indice a son propre jeu de paramètres, chargé automatiquement
(`InpUsePresets = true`). Le risque effectif d'un trade est le risque de base
(`InpRiskPercent`, 0,5 % par défaut) multiplié par le coefficient de risque.

**FX Vol / SFX Vol (TREND)**

| Indice | UT | Risque | EMA rapide / lente | ADX min | Stop | Objectif | Trailing |
|---|---|---|---|---|---|---|---|
| FX Vol 20  | H1  | ×1,0 | 20 / 100 | 20 | 2,0 ATR | 4,0 ATR | 2,5 ATR |
| FX Vol 40  | M15 | ×1,0 | 20 / 100 | 22 | 2,2 ATR | 4,0 ATR | 2,5 ATR |
| FX Vol 60  | M15 | ×0,8 | 30 / 150 | 25 | 2,5 ATR | 4,5 ATR | 3,0 ATR |
| SFX Vol 20 | H1  | ×1,0 | 20 / 120 | 22 | 2,2 ATR | 4,0 ATR | 2,8 ATR |
| SFX Vol 40 | M15 | ×0,8 | 25 / 150 | 25 | 2,5 ATR | 4,5 ATR | 3,0 ATR |
| SFX Vol 60 | M15 | ×0,6 | 30 / 200 | 28 | 3,0 ATR | 5,0 ATR | 3,5 ATR |

**GainX (DRIFT, en M1)**

| Indice | Risque | Barres analysées | EMA | Attente après pic | Stop | Objectif | Sortie après |
|---|---|---|---|---|---|---|---|
| GainX 400  | ×0,7 | 2000 | 30 | 2 barres | 1,3 pic | 0,5 pic | 30 barres |
| GainX 600  | ×0,8 | 2500 | 40 | 3 barres | 1,2 pic | 0,6 pic | 45 barres |
| GainX 800  | ×0,9 | 3000 | 50 | 3 barres | 1,2 pic | 0,6 pic | 60 barres |
| GainX 999  | ×1,0 | 3500 | 50 | 4 barres | 1,2 pic | 0,6 pic | 80 barres |
| GainX 1200 | ×1,0 | 4000 | 60 | 4 barres | 1,1 pic | 0,7 pic | 100 barres |

La logique de ces réglages :

- **Plus l'indice est volatil** (60 > 40 > 20, et SFX que je suppose plus
  agité que FX), plus les tendances doivent être confirmées (EMA plus
  longues, ADX plus élevé), plus les stops sont larges et plus le risque par
  trade est réduit.
- **Les indices à 20** bougent peu : le spread pèse plus lourd par rapport au
  mouvement. Ils travaillent donc en H1, où le spread coûte environ 2,5 fois
  moins par trade qu'en M15, mais avec environ 4 fois moins de trades.
- **Les indices à 40 et 60** travaillent en M15. Le M5 coûtait nettement plus
  cher en spread pour un avantage incertain.
- **Les GainX à pics fréquents** (400) imposent des positions plus courtes et
  un risque plus faible. Les GainX à pics rares (1200) laissent plus de temps
  à la dérive.

> **Important :** ces valeurs sont des **points de départ raisonnés**, pas
> des réglages validés. Je n'ai pas encore eu accès aux vraies données
> Weltrade, et la nature exacte de SFX Vol n'est pas documentée publiquement.
> Validez chaque préréglage avec `--optimize` sur les données de l'indice
> concerné, puis ajustez-le dans `LoadPreset()` (EA) et `PRESETS` (Python).
> Pour régler tout à la main, passez `InpUsePresets = false`.

## Gestion du risque (intégrée, non désactivable)

- Taille de lot calculée pour risquer **X % de l'equity** par trade (0,5 % par défaut).
  Si même le lot minimum dépasse ce risque, le trade est **ignoré**.
- **Limite de perte journalière** (3 %) : le bot arrête de trader jusqu'au lendemain.
- **Coupe-circuit** à 15 % de drawdown depuis le plus haut : le bot ferme tout et s'arrête.
- Nombre maximal de trades par jour, filtre de spread, une seule position à la fois.
- **Aucune martingale, aucune grille.**

## Mode d'emploi

### 1. Installer l'EA

1. Dans MT5 : *Fichier → Ouvrir le dossier des données → MQL5*.
2. Copiez `SyntX_Guardian.mq5` dans `Experts/` et `ExportBars.mq5` dans `Scripts/`.
3. Compilez les deux fichiers dans MetaEditor (F7).

### 2. Tester avant tout (obligatoire)

1. **Testeur de stratégie MT5** (Ctrl+R) : choisissez le mode
   **« Chaque tick basé sur des ticks réels »**. C'est le seul mode qui
   reproduit correctement les pics qui sautent par-dessus le stop.
2. **Backtester Python** sur les vraies données Weltrade :
   - Ouvrez un graphique de l'indice **dans l'UT de son préréglage** (M1 pour
     GainX, H1 pour les indices 20, M15 pour les 40 et 60) et faites défiler l'historique.
   - Lancez le script `ExportBars` : le CSV est écrit dans `MQL5/Files/`.
   - Puis :

   ```bash
   pip install pandas numpy
   # Analyse des pics + backtest avec les paramètres par défaut
   python backtest/syntx_backtest.py GainX_999_M1.csv --point 0.01
   python backtest/syntx_backtest.py FX_Vol_40_M5.csv --point 0.01
   # Optimisation + vérification sur des données jamais vues
   python backtest/syntx_backtest.py SFX_Vol_20_M15.csv --point 0.01 --optimize
   ```

   Le préréglage est choisi d'après le nom du fichier. Si le nom ne
   contient pas l'indice, ajoutez `--symbol "FX Vol 40"`. Un avertissement
   s'affiche si l'UT des données ne correspond pas à celle du préréglage.

   `--point` correspond à la taille du point du symbole (affichée par
   `ExportBars`). Il sert à convertir le spread réel en prix.

3. **Compte démo pendant au moins 1 à 3 mois.** Passez au réel seulement si
   les résultats en démo confirment le backtest.

### 3. Lire les résultats

| Indicateur | Ce qu'il faut viser |
|---|---|
| `E` (espérance en R) | > 0 **hors échantillon** (`OUT`), pas seulement en `IN` |
| `t` | > 2 (sinon le résultat peut être dû au hasard) |
| `maxDD` | Un niveau que vous supporteriez psychologiquement **et** financièrement |
| `gagnants` | **Ne veut rien dire seul.** Une stratégie à 89 % de trades gagnants peut perdre de l'argent. |

## Ce que les tests ont montré (important)

Le backtester contient un **simulateur équitable** (`--simulate gainx`), qui
imite un indice à pics sans aucun avantage exploitable. Il sert de contrôle :

```
python backtest/syntx_backtest.py --simulate gainx --spread 0.3
```

- **Sur données équitables, la stratégie DRIFT perd** (E ≈ -0,04 R), alors
  qu'elle gagne **75 % de ses trades** : les petits gains fréquents sont
  effacés par les pics rares. C'est le piège classique des bots
  « spike » vendus sur internet.
- **Avec un glissement optimiste** (stop exécuté pile au prix du stop, soit
  `--spike-slippage 0`), le même backtest affiche **un faux profit**. Beaucoup
  de backtests sur barres surestiment donc ces stratégies. En réalité, un pic
  saute par-dessus votre stop.
- **Quand on injecte un vrai biais** (`--edge 0.3`), l'outil le détecte bien
  (E > 0, t > 10). Le backtester n'est donc pas pessimiste par construction :
  il trouvera un avantage s'il existe dans les données de Weltrade.
- **Les pics simulés sont sans mémoire.** « Attendre que le pic soit dû »
  n'apporte rien. Le rapport `Analyse des pics` vérifie cette propriété sur
  les données réelles.

**Conclusion honnête.** La rentabilité dépend entièrement de l'existence
d'un biais dans l'algorithme de Weltrade, ce que personne ne peut affirmer
sans le mesurer. Ce projet vous donne les moyens de le mesurer et protège
votre capital si l'avantage n'existe pas.
