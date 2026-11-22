//+------------------------------------------------------------------+
//|                                          SyntheticTrendGuard.mq5 |
//|  EA MT5 pour indices synthétiques Deriv (Volatility, Step, etc.) |
//|  Stratégie : tendance multi-timeframe + pullback + gestion ATR   |
//|  Priorité : contrôle du risque (pas de martingale / grid).       |
//+------------------------------------------------------------------+
#property copyright "SyntheticTrendGuard"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Entrées : stratégie
input group "=== Stratégie ==="
input ENUM_TIMEFRAMES InpTrendTF      = PERIOD_H1;   // Timeframe de tendance
input int             InpTrendFastEMA = 50;          // EMA rapide (tendance)
input int             InpTrendSlowEMA = 200;         // EMA lente (tendance)
input int             InpEntryEMA     = 21;          // EMA de pullback (TF du graphique)
input int             InpRSIPeriod    = 14;          // Période RSI (TF du graphique)
input double          InpRSIBuyMin    = 50.0;        // RSI min pour acheter
input double          InpRSISellMax   = 50.0;        // RSI max pour vendre
input int             InpATRPeriod    = 14;          // Période ATR
input double          InpMinATRPoints = 0.0;         // ATR minimum en points (0 = désactivé)

input group "=== Sorties ==="
input double InpSL_ATR        = 2.0;   // Stop loss = ATR x
input double InpTP_RR         = 2.0;   // Take profit = SL x (ratio R:R)
input double InpBE_TriggerR   = 1.0;   // Breakeven quand profit >= x R (0 = off)
input double InpTrail_ATR     = 1.5;   // Trailing stop = ATR x (0 = off)
input double InpTrailStartR   = 1.0;   // Trailing démarre à x R

input group "=== Gestion du risque ==="
input double InpRiskPercent     = 1.0;   // Risque par trade (% de l'equity)
input double InpDailyLossPct    = 3.0;   // Perte journalière max (% equity début de jour)
input double InpMaxDrawdownPct  = 15.0;  // Drawdown max depuis le pic (kill switch)
input int    InpMaxSpreadPoints = 0;     // Spread max en points (0 = désactivé)
input int    InpCooldownBars    = 3;     // Barres d'attente après une clôture
input bool   InpAllowBuy        = true;  // Autoriser les achats
input bool   InpAllowSell       = true;  // Autoriser les ventes

input group "=== Divers ==="
input ulong  InpMagic      = 20261122;   // Magic number
input int    InpSlippage   = 50;         // Slippage max (points)
input string InpComment    = "STG";      // Commentaire des ordres

//--- Globales
CTrade   trade;
int      hTrendFast = INVALID_HANDLE;
int      hTrendSlow = INVALID_HANDLE;
int      hEntryEMA  = INVALID_HANDLE;
int      hRSI       = INVALID_HANDLE;
int      hATR       = INVALID_HANDLE;

datetime lastBarTime     = 0;
datetime dayStart        = 0;
double   dayStartEquity  = 0.0;
double   peakEquity      = 0.0;
bool     killSwitch      = false;
datetime lastCloseTime   = 0;

string   gvPeak;   // variable globale terminal pour persister le pic d'equity
string   gvKill;

//+------------------------------------------------------------------+
int OnInit()
{
   if(InpTrendFastEMA >= InpTrendSlowEMA || InpRiskPercent <= 0.0 || InpSL_ATR <= 0.0 || InpTP_RR <= 0.0)
   {
      Print("Paramètres invalides.");
      return INIT_PARAMETERS_INCORRECT;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   hTrendFast = iMA(_Symbol, InpTrendTF, InpTrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrendSlow = iMA(_Symbol, InpTrendTF, InpTrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEntryEMA  = iMA(_Symbol, _Period,    InpEntryEMA,     0, MODE_EMA, PRICE_CLOSE);
   hRSI       = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   hATR       = iATR(_Symbol, _Period, InpATRPeriod);

   if(hTrendFast == INVALID_HANDLE || hTrendSlow == INVALID_HANDLE || hEntryEMA == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hATR == INVALID_HANDLE)
   {
      Print("Erreur création indicateurs : ", GetLastError());
      return INIT_FAILED;
   }

   gvPeak = "STG_PEAK_" + _Symbol + "_" + (string)InpMagic;
   gvKill = "STG_KILL_" + _Symbol + "_" + (string)InpMagic;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   peakEquity = eq;
   if(!MQLInfoInteger(MQL_TESTER))
   {
      if(GlobalVariableCheck(gvPeak)) peakEquity = MathMax(eq, GlobalVariableGet(gvPeak));
      if(GlobalVariableCheck(gvKill)) killSwitch = (GlobalVariableGet(gvKill) > 0.5);
   }

   ResetDay();
   if(killSwitch) Print("Kill switch actif (drawdown max atteint précédemment). Supprimez la variable globale ", gvKill, " pour réarmer.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hTrendFast != INVALID_HANDLE) IndicatorRelease(hTrendFast);
   if(hTrendSlow != INVALID_HANDLE) IndicatorRelease(hTrendSlow);
   if(hEntryEMA  != INVALID_HANDLE) IndicatorRelease(hEntryEMA);
   if(hRSI       != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hATR       != INVALID_HANDLE) IndicatorRelease(hATR);
   Comment("");
}

//+------------------------------------------------------------------+
//| Journée = jour calendaire de l'heure serveur (Deriv : GMT)       |
//+------------------------------------------------------------------+
datetime DayOf(datetime t) { long s = (long)t; return (datetime)(s - (s % 86400)); }

void ResetDay()
{
   dayStart       = DayOf(TimeCurrent());
   dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
}

//+------------------------------------------------------------------+
bool GetBuf(int handle, int shift, int count, double &buf[])
{
   ArraySetAsSeries(buf, true);
   int copied = CopyBuffer(handle, 0, shift, count, buf);
   return (copied == count);
}

//+------------------------------------------------------------------+
int CountMyPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
         n++;
   }
   return n;
}

//+------------------------------------------------------------------+
//| Ferme toutes les positions de l'EA sur ce symbole                |
//+------------------------------------------------------------------+
void CloseAllMine()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagic)
      {
         if(!trade.PositionClose(ticket))
            Print("Echec fermeture #", ticket, " : ", trade.ResultRetcodeDescription());
      }
   }
}

//+------------------------------------------------------------------+
//| Contrôles de risque au niveau compte. Retourne true si on peut   |
//| ouvrir de nouveaux trades.                                       |
//+------------------------------------------------------------------+
bool RiskGate(string &status)
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(DayOf(TimeCurrent()) != dayStart) ResetDay();

   if(eq > peakEquity)
   {
      peakEquity = eq;
      if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(gvPeak, peakEquity);
   }

   // Kill switch drawdown max
   if(!killSwitch && InpMaxDrawdownPct > 0.0 && peakEquity > 0.0)
   {
      double dd = (peakEquity - eq) / peakEquity * 100.0;
      if(dd >= InpMaxDrawdownPct)
      {
         killSwitch = true;
         if(!MQLInfoInteger(MQL_TESTER)) GlobalVariableSet(gvKill, 1.0);
         Print("KILL SWITCH : drawdown ", DoubleToString(dd, 2), "% >= ", InpMaxDrawdownPct, "%. Fermeture et arrêt.");
         CloseAllMine();
      }
   }
   if(killSwitch) { status = "KILL SWITCH (DD max)"; return false; }

   // Limite de perte journalière
   if(InpDailyLossPct > 0.0 && dayStartEquity > 0.0)
   {
      double dayLoss = (dayStartEquity - eq) / dayStartEquity * 100.0;
      if(dayLoss >= InpDailyLossPct)
      {
         if(CountMyPositions() > 0)
         {
            Print("Limite journalière atteinte (", DoubleToString(dayLoss, 2), "%). Fermeture des positions.");
            CloseAllMine();
         }
         status = "Limite journalière atteinte";
         return false;
      }
   }

   status = "OK";
   return true;
}

//+------------------------------------------------------------------+
//| Taille de lot basée sur le risque (OrderCalcProfit)              |
//+------------------------------------------------------------------+
double CalcLots(ENUM_ORDER_TYPE type, double entry, double sl)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minLot <= 0.0 || stepLot <= 0.0) return 0.0;

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;

   double pnl = 0.0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, entry, sl, pnl))
   {
      Print("OrderCalcProfit a échoué : ", GetLastError());
      return 0.0;
   }
   double lossPerLot = MathAbs(pnl);
   if(lossPerLot <= 0.0) return 0.0;

   double lots = riskMoney / lossPerLot;
   lots = MathFloor(lots / stepLot) * stepLot;
   if(maxLot > 0.0) lots = MathMin(lots, maxLot);

   if(lots < minLot)
   {
      PrintFormat("Trade ignoré : lot min %.4f > lot autorisé par le risque %.4f (risque %.2f, perte/lot %.2f).",
                  minLot, lots, riskMoney, lossPerLot);
      return 0.0;
   }

   // Vérification de marge
   double margin = 0.0;
   if(OrderCalcMargin(type, _Symbol, lots, entry, margin))
   {
      if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      {
         Print("Trade ignoré : marge insuffisante.");
         return 0.0;
      }
   }

   int volDigits = (int)MathMax(0.0, MathCeil(-MathLog10(stepLot)));
   return NormalizeDouble(lots, volDigits);
}

//+------------------------------------------------------------------+
//| Distance minimale des stops (stops level + freeze level)         |
//+------------------------------------------------------------------+
double MinStopDistance()
{
   long stopsLvl  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(stopsLvl, freezeLvl) * _Point;
}

//+------------------------------------------------------------------+
//| Gestion des positions ouvertes : breakeven + trailing ATR        |
//+------------------------------------------------------------------+
void ManagePositions(double atr)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minDist = MinStopDistance();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   ptype = PositionGetInteger(POSITION_TYPE);
      double open  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);

      // R initial = distance SL initiale ; on l'estime via le TP (TP = R * RR)
      double initR = (tp > 0.0) ? MathAbs(tp - open) / InpTP_RR : InpSL_ATR * atr;
      if(initR <= 0.0) continue;

      double newSL = sl;

      if(ptype == POSITION_TYPE_BUY)
      {
         double profitDist = bid - open;
         if(InpBE_TriggerR > 0.0 && profitDist >= InpBE_TriggerR * initR && (sl < open || sl == 0.0))
            newSL = open + 2 * _Point;
         if(InpTrail_ATR > 0.0 && profitDist >= InpTrailStartR * initR)
         {
            double trail = bid - InpTrail_ATR * atr;
            if(trail > newSL) newSL = trail;
         }
         newSL = NormalizeDouble(newSL, _Digits);
         if(newSL > sl + _Point && newSL < bid - minDist)
         {
            if(!trade.PositionModify(ticket, newSL, tp))
               Print("Echec modification BUY #", ticket, " : ", trade.ResultRetcodeDescription());
         }
      }
      else if(ptype == POSITION_TYPE_SELL)
      {
         double profitDist = open - ask;
         if(InpBE_TriggerR > 0.0 && profitDist >= InpBE_TriggerR * initR && (sl > open || sl == 0.0))
            newSL = open - 2 * _Point;
         if(InpTrail_ATR > 0.0 && profitDist >= InpTrailStartR * initR)
         {
            double trail = ask + InpTrail_ATR * atr;
            if(newSL == 0.0 || trail < newSL) newSL = trail;
         }
         newSL = NormalizeDouble(newSL, _Digits);
         if((sl == 0.0 || newSL < sl - _Point) && newSL > ask + minDist)
         {
            if(!trade.PositionModify(ticket, newSL, tp))
               Print("Echec modification SELL #", ticket, " : ", trade.ResultRetcodeDescription());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Signal : 1 = achat, -1 = vente, 0 = rien (barres clôturées)      |
//+------------------------------------------------------------------+
int GetSignal(double &atrOut)
{
   double tf[], ts[], ema[], rsi[], atr[];
   // Tendance sur barre HTF clôturée (shift 1)
   if(!GetBuf(hTrendFast, 1, 2, tf)) return 0;
   if(!GetBuf(hTrendSlow, 1, 2, ts)) return 0;
   // Entrée sur barres clôturées du TF du graphique (shift 1 et 2)
   if(!GetBuf(hEntryEMA, 1, 2, ema)) return 0;
   if(!GetBuf(hRSI,      1, 2, rsi)) return 0;
   if(!GetBuf(hATR,      1, 1, atr)) return 0;

   atrOut = atr[0];
   if(atrOut <= 0.0) return 0;
   if(InpMinATRPoints > 0.0 && atrOut < InpMinATRPoints * _Point) return 0;

   MqlRates r[];
   ArraySetAsSeries(r, true);
   if(CopyRates(_Symbol, _Period, 1, 2, r) != 2) return 0;
   // r[0] = dernière barre clôturée, r[1] = celle d'avant

   bool upTrend   = tf[0] > ts[0] && tf[0] > tf[1];   // EMA rapide au-dessus et montante
   bool downTrend = tf[0] < ts[0] && tf[0] < tf[1];

   // Pullback : la barre précédente a touché/traversé l'EMA d'entrée,
   // la dernière barre clôture du bon côté avec un corps dans le sens de la tendance.
   bool buyPullback  = (r[1].low  <= ema[1]) && (r[0].close > ema[0]) && (r[0].close > r[0].open);
   bool sellPullback = (r[1].high >= ema[1]) && (r[0].close < ema[0]) && (r[0].close < r[0].open);

   bool buyMomentum  = rsi[0] > InpRSIBuyMin  && rsi[0] > rsi[1];
   bool sellMomentum = rsi[0] < InpRSISellMax && rsi[0] < rsi[1];

   if(InpAllowBuy  && upTrend   && buyPullback  && buyMomentum)  return  1;
   if(InpAllowSell && downTrend && sellPullback && sellMomentum) return -1;
   return 0;
}

//+------------------------------------------------------------------+
void OpenTrade(int dir, double atr)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;

   double slDist  = InpSL_ATR * atr;
   double minDist = MinStopDistance();
   if(slDist < minDist + (ask - bid)) slDist = minDist + (ask - bid);
   double tpDist  = slDist * InpTP_RR;

   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double entry = (dir > 0) ? ask : bid;
   double sl    = NormalizeDouble((dir > 0) ? entry - slDist : entry + slDist, _Digits);
   double tp    = NormalizeDouble((dir > 0) ? entry + tpDist : entry - tpDist, _Digits);

   double lots = CalcLots(type, entry, sl);
   if(lots <= 0.0) return;

   bool ok = (dir > 0) ? trade.Buy(lots, _Symbol, 0.0, sl, tp, InpComment)
                       : trade.Sell(lots, _Symbol, 0.0, sl, tp, InpComment);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
      Print("Echec ouverture : ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   else
      PrintFormat("%s %.4f lots @ %s SL=%s TP=%s", (dir > 0 ? "BUY" : "SELL"), lots,
                  DoubleToString(entry, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits));
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic) return;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      lastCloseTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
}

//+------------------------------------------------------------------+
void OnTick()
{
   string status;
   bool canTrade = RiskGate(status);

   // ATR courant pour la gestion des positions (barre clôturée)
   double atrBuf[];
   double atrNow = 0.0;
   if(GetBuf(hATR, 1, 1, atrBuf)) atrNow = atrBuf[0];
   if(atrNow > 0.0 && CountMyPositions() > 0) ManagePositions(atrNow);

   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE))
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      Comment(StringFormat("SyntheticTrendGuard | %s\nEquity: %.2f | Début jour: %.2f | Pic: %.2f\nPositions: %d",
              status, eq, dayStartEquity, peakEquity, CountMyPositions()));
   }

   // Entrées : uniquement à l'ouverture d'une nouvelle barre
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == 0 || barTime == lastBarTime) return;
   lastBarTime = barTime;

   if(!canTrade) return;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) return;
   if(CountMyPositions() > 0) return;

   if(InpCooldownBars > 0 && lastCloseTime > 0 &&
      barTime - lastCloseTime < (datetime)(InpCooldownBars * PeriodSeconds(_Period)))
      return;

   if(InpMaxSpreadPoints > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPoints) return;
   }

   double atr = 0.0;
   int sig = GetSignal(atr);
   if(sig != 0) OpenTrade(sig, atr);
}
//+------------------------------------------------------------------+
