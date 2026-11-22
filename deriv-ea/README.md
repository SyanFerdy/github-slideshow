# SyntheticTrendGuard — EA MT5 pour les indices synthétiques Deriv

EA MetaTrader 5 pour les indices synthétiques Deriv (Volatility 10/25/50/75/100, versions (1s), Step Index, Jump, Range Break…).
Il s'adapte au symbole sur lequel on l'attache : taille de lot, stops minimum et mode de remplissage sont lus depuis le symbole, pas codés en dur.

> ⚠️ **À lire avant tout.** Les indices synthétiques sont générés par un algorithme aléatoire. Aucune stratégie n'y a d'avantage garanti, et cet EA ne promet aucun profit.
> Sa « solidité » vient de la **gestion du risque** : perte bornée par trade, par jour, et un arrêt automatique en cas de drawdown.
> Il n'a **pas été compilé ni backtesté** dans l'environnement où il a été écrit. Compilez-le, testez-le dans le Strategy Tester, puis sur un compte **démo** pendant plusieurs semaines avant tout argent réel.

## Stratégie

1. **Filtre de tendance (TF supérieur, H1 par défaut)** : EMA 50 au-dessus de l'EMA 200 et montante, donc tendance haussière (et l'inverse pour une tendance baissière). Le calcul se fait sur des barres clôturées.
2. **Entrée sur pullback (TF du graphique, M15 conseillé)** : la barre précédente touche l'EMA 21, puis la dernière barre clôture du bon côté de l'EMA avec un corps dans le sens de la tendance.
3. **Confirmation** : RSI 14 au-dessus de 50 et en hausse pour un achat (en dessous de 50 et en baisse pour une vente).
4. **Sorties** :
   - SL = 2 × ATR ;
   - TP = 2R ;
   - breakeven à +1R ;
   - trailing stop de 1,5 × ATR à partir de +1R.

Une seule position à la fois par symbole et par magic number, et uniquement à l'ouverture d'une nouvelle barre. Pas de martingale, pas de grid, pas de moyenne à la baisse.

## Gestion du risque

| Protection | Défaut | Détail |
|---|---|---|
| Risque par trade | 1 % de l'equity | Lot calculé avec `OrderCalcProfit` sur la distance du SL. Si le lot minimum du symbole dépasse ce risque, le trade est **ignoré**, jamais arrondi au-dessus. |
| Perte journalière max | 3 % | Le « jour » est le jour calendaire de l'heure serveur (GMT chez Deriv). Une fois la limite atteinte, les positions sont fermées et plus aucune entrée n'est prise jusqu'au lendemain. |
| Drawdown max (kill switch) | 15 % depuis le pic | Ferme tout et arrête l'EA. L'état est mémorisé (variable globale `STG_KILL_<symbole>_<magic>`). Supprimez-la (F3 dans MT5) pour réarmer l'EA. |
| Filtre de spread | désactivé | `InpMaxSpreadPoints` |
| Cooldown | 3 barres | Délai après chaque clôture de position. |

**Limite importante :** sur les indices **Boom/Crash/Jump**, les spikes peuvent sauter par-dessus le stop. La perte réelle peut alors dépasser le risque prévu. Sur ces indices, baissez le risque (0,25 à 0,5 %) ou désactivez le sens exposé aux spikes (`InpAllowBuy` / `InpAllowSell`).

## Installation

1. Dans MT5 (connecté à votre compte Deriv) : **Fichier → Ouvrir le dossier des données → MQL5/Experts**, puis copiez-y `SyntheticTrendGuard.mq5`.
2. Ouvrez le fichier dans MetaEditor et compilez-le (F7). Il doit afficher 0 erreur.
3. Ouvrez un graphique, par exemple **Volatility 75 Index en M15**, faites glisser l'EA dessus, puis activez **Algo Trading**.

## Tester

- **Strategy Tester (Ctrl+R)** : choisissez le mode « Every tick based on real ticks » et une période d'au moins 6 à 12 mois.
- Testez **plusieurs symboles** et **plusieurs périodes**. Si un réglage ne marche que sur un seul cas, c'est probablement du sur-ajustement (overfitting).
- Optimisez peu de paramètres (`InpSL_ATR`, `InpTP_RR`, `InpEntryEMA`), puis validez sur une période **non utilisée** pendant l'optimisation (forward test).
- Enfin, laissez-le tourner sur un compte **démo** pendant plusieurs semaines.

## Paramètres principaux

| Paramètre | Rôle |
|---|---|
| `InpTrendTF`, `InpTrendFastEMA`, `InpTrendSlowEMA` | Filtre de tendance |
| `InpEntryEMA`, `InpRSIPeriod`, `InpRSIBuyMin`, `InpRSISellMax` | Signal d'entrée |
| `InpATRPeriod`, `InpMinATRPoints` | Volatilité, et filtre de marché trop calme |
| `InpSL_ATR`, `InpTP_RR`, `InpBE_TriggerR`, `InpTrail_ATR`, `InpTrailStartR` | Sorties |
| `InpRiskPercent`, `InpDailyLossPct`, `InpMaxDrawdownPct` | Risque |
| `InpMagic` | Utilisez un magic différent par graphique si vous lancez plusieurs instances. |
