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

## Les deux moteurs

**DRIFT (GainX / PainX).** Ces indices dérivent lentement dans un sens et font
des pics brutaux dans l'autre, en moyenne tous les N ticks (400, 600, 800,
999, 1200). Le bot :

- détecte lui-même le sens des pics à partir des données, sans le coder en dur ;
- trade dans le sens de la dérive, confirmé par une EMA ;
- place son stop et son objectif en multiples de la taille moyenne d'un pic ;
- ferme la position après un nombre maximal de barres.

**TREND (FX Vol, SFX Vol, TrendX…).** Le bot entre sur un croisement d'EMA
rapide/lente filtré par l'ADX. Le stop et l'objectif sont en ATR, avec un
trailing stop.

Le mode `Auto` choisit DRIFT si le symbole contient « GainX » ou « PainX »,
et TREND sinon.

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
   - Ouvrez un graphique M1 (par exemple GainX 999) et faites défiler l'historique.
   - Lancez le script `ExportBars` : le CSV est écrit dans `MQL5/Files/`.
   - Puis :

   ```bash
   pip install pandas numpy
   # Analyse des pics + backtest avec les paramètres par défaut
   python backtest/syntx_backtest.py GainX_999_M1.csv --engine drift --point 0.01
   # Optimisation + vérification sur des données jamais vues
   python backtest/syntx_backtest.py GainX_999_M1.csv --engine drift --point 0.01 --optimize
   ```

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
