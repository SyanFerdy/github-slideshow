//+------------------------------------------------------------------+
//|                                              SyntX_Guardian.mq5  |
//|  Expert Advisor pour les indices synthetiques Weltrade (MT5)     |
//|                                                                  |
//|  Deux moteurs :                                                  |
//|   - DRIFT  : GainX / PainX. Trade dans le sens de la derive lente |
//|              (a l'oppose des pics), direction detectee           |
//|              automatiquement a partir des donnees.               |
//|   - TREND  : FX Vol, SFX Vol, TrendX, etc. Croisement d'EMA +     |
//|              filtre ADX, stop/objectif en ATR, trailing stop.    |
//|                                                                  |
//|  Gestion du risque : % du capital par trade, limite de perte     |
//|  journaliere, coupe-circuit sur drawdown, filtre de spread,      |
//|  une seule position a la fois. AUCUNE martingale, AUCUNE grille. |
//|                                                                  |
//|  Aucun resultat n'est garanti. Testez sur compte demo.          |
//+------------------------------------------------------------------+
#property copyright "SyntX Guardian"
#property version   "1.00"

#include <Trade\Trade.mqh>

enum ENUM_ENGINE
  {
   ENGINE_AUTO  = 0, // Auto (GainX/PainX -> Drift, sinon Trend)
   ENGINE_DRIFT = 1, // Drift (anti-pic)
   ENGINE_TREND = 2  // Trend (suivi de tendance)
  };

//--- General
input group "=== General ==="
input ENUM_ENGINE     InpEngine        = ENGINE_AUTO;   // Moteur de strategie
input ENUM_TIMEFRAMES InpTimeframe     = PERIOD_M1;     // Unite de temps des signaux
input long            InpMagic         = 26112201;      // Numero magique
input int             InpMaxSpreadPts  = 0;             // Spread max en points (0 = pas de filtre)

//--- Risque
input group "=== Gestion du risque ==="
input double InpRiskPercent      = 0.5;   // Risque par trade (% de l'equity)
input double InpDailyLossPercent = 3.0;   // Perte max journaliere (%) -> stop jusqu'a demain
input double InpMaxDDPercent     = 15.0;  // Drawdown max depuis le pic (%) -> arret total
input int    InpMaxTradesPerDay  = 20;    // Nombre max de trades par jour

//--- Drift (GainX / PainX)
input group "=== Moteur DRIFT (GainX / PainX) ==="
input int    InpSpikeLookback  = 3000;  // Barres analysees pour les statistiques de pics
input double InpSpikeMult      = 6.0;   // Pic = corps > X fois le corps median
input int    InpMinSpikes      = 5;     // Nb min de pics observes pour trader
input int    InpDriftEMA       = 50;    // EMA de confirmation de la derive
input int    InpCooldownBars   = 3;     // Barres a attendre apres un pic
input double InpDriftSLSpike   = 1.2;   // Stop = X fois la taille moyenne d'un pic
input double InpDriftTPSpike   = 0.6;   // Objectif = X fois la taille moyenne d'un pic
input int    InpDriftMaxBars   = 120;   // Sortie forcee apres N barres (0 = off)

//--- Trend
input group "=== Moteur TREND (FX Vol, SFX Vol, ...) ==="
input int    InpFastEMA      = 20;    // EMA rapide
input int    InpSlowEMA      = 100;   // EMA lente
input int    InpADXPeriod    = 14;    // Periode ADX
input double InpADXMin       = 22.0;  // ADX minimum pour entrer
input int    InpATRPeriod    = 14;    // Periode ATR
input double InpSL_ATR       = 2.0;   // Stop = X * ATR
input double InpTP_ATR       = 4.0;   // Objectif = X * ATR (0 = pas d'objectif)
input double InpTrail_ATR    = 2.5;   // Trailing stop = X * ATR (0 = off)

//--- Etat global
CTrade      trade;
ENUM_ENGINE g_engine;
int         hDriftEMA = INVALID_HANDLE;
int         hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE;
int         hADX  = INVALID_HANDLE, hATR  = INVALID_HANDLE;
datetime    g_lastBar      = 0;
double      g_peakEquity   = 0.0;
double      g_dayStartEq   = 0.0;
int         g_dayOfYear    = -1;
int         g_tradesToday  = 0;
bool        g_haltedForever = false;

//--- Statistiques de pics (moteur DRIFT)
int    g_driftDir      = 0;    // +1 = derive haussiere, -1 = baissiere, 0 = inconnu
int    g_spikeCount    = 0;
double g_avgSpike      = 0.0;  // taille moyenne d'un pic (en prix)
int    g_barsSinceSpike = 0;
double g_spikeThresh   = 0.0;

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_engine = InpEngine;
   if(g_engine == ENGINE_AUTO)
     {
      string s = _Symbol;
      StringToUpper(s);
      g_engine = (StringFind(s, "GAINX") >= 0 || StringFind(s, "PAINX") >= 0)
                 ? ENGINE_DRIFT : ENGINE_TREND;
     }

   if(g_engine == ENGINE_DRIFT)
     {
      hDriftEMA = iMA(_Symbol, InpTimeframe, InpDriftEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(hDriftEMA == INVALID_HANDLE) return INIT_FAILED;
     }
   else
     {
      hFast = iMA(_Symbol, InpTimeframe, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
      hSlow = iMA(_Symbol, InpTimeframe, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
      hADX  = iADX(_Symbol, InpTimeframe, InpADXPeriod);
      hATR  = iATR(_Symbol, InpTimeframe, InpATRPeriod);
      if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE ||
         hADX == INVALID_HANDLE  || hATR == INVALID_HANDLE)
         return INIT_FAILED;
     }

   g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEq = g_peakEquity;
   PrintFormat("SyntX Guardian demarre sur %s, moteur = %s",
               _Symbol, g_engine == ENGINE_DRIFT ? "DRIFT" : "TREND");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hDriftEMA != INVALID_HANDLE) IndicatorRelease(hDriftEMA);
   if(hFast != INVALID_HANDLE)     IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE)     IndicatorRelease(hSlow);
   if(hADX != INVALID_HANDLE)      IndicatorRelease(hADX);
   if(hATR != INVALID_HANDLE)      IndicatorRelease(hATR);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateRiskState();

   // Le trailing tourne a chaque tick, le reste a chaque nouvelle barre
   if(g_engine == ENGINE_TREND) ManageTrailing();

   datetime barTime = iTime(_Symbol, InpTimeframe, 0);
   if(barTime == g_lastBar) return;
   g_lastBar = barTime;

   if(g_engine == ENGINE_DRIFT)
     {
      UpdateSpikeStats();
      ManageDriftExit();
     }

   ShowStatus();

   if(!TradingAllowed()) return;
   if(HasPosition()) return;

   if(g_engine == ENGINE_DRIFT) CheckDriftEntry();
   else                         CheckTrendEntry();
  }

//+------------------------------------------------------------------+
//| Risque : pic d'equity, limite journaliere, coupe-circuit          |
//+------------------------------------------------------------------+
void UpdateRiskState()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEquity) g_peakEquity = eq;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(t.day_of_year != g_dayOfYear)
     {
      g_dayOfYear   = t.day_of_year;
      g_dayStartEq  = eq;
      g_tradesToday = 0;
     }

   if(!g_haltedForever && g_peakEquity > 0 &&
      (g_peakEquity - eq) / g_peakEquity * 100.0 >= InpMaxDDPercent)
     {
      g_haltedForever = true;
      CloseAll();
      PrintFormat("COUPE-CIRCUIT : drawdown >= %.1f%%. Le bot s'arrete.", InpMaxDDPercent);
     }
  }

bool TradingAllowed()
  {
   if(g_haltedForever) return false;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartEq > 0 && (g_dayStartEq - eq) / g_dayStartEq * 100.0 >= InpDailyLossPercent)
      return false;
   if(g_tradesToday >= InpMaxTradesPerDay) return false;

   if(InpMaxSpreadPts > 0)
     {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpreadPts) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Taille de position a partir du risque et de la distance du stop  |
//+------------------------------------------------------------------+
double LotsForRisk(double slDistance)
  {
   if(slDistance <= 0) return 0.0;

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0) tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(tickValue <= 0 || tickSize <= 0 || step <= 0) return 0.0;

   double lossPerLot = slDistance / tickSize * tickValue;
   double lots = MathFloor(riskMoney / lossPerLot / step) * step;

   // Si meme le lot minimum depasse le risque autorise, on ne trade pas.
   if(lots < vmin) return 0.0;
   return MathMin(lots, vmax);
  }

//+------------------------------------------------------------------+
bool HasPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;
     }
   return false;
  }

void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         trade.PositionClose(ticket);
     }
  }

bool OpenPosition(int dir, double slDist, double tpDist, string tag)
  {
   double lots = LotsForRisk(slDist);
   if(lots <= 0)
     {
      Print("Lot calcule trop petit pour le risque choisi : trade ignore.");
      return false;
     }

   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double price  = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                           : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = NormalizeDouble(price - dir * slDist, digits);
   double tp = tpDist > 0 ? NormalizeDouble(price + dir * tpDist, digits) : 0.0;

   bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0.0, sl, tp, tag)
                     : trade.Sell(lots, _Symbol, 0.0, sl, tp, tag);
   if(ok) g_tradesToday++;
   else   PrintFormat("Echec ordre : %d %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return ok;
  }

//+------------------------------------------------------------------+
//| MOTEUR DRIFT                                                     |
//+------------------------------------------------------------------+
void UpdateSpikeStats()
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, InpTimeframe, 1, InpSpikeLookback, r);
   if(n < 200) { g_driftDir = 0; return; }

   double bodies[];
   ArrayResize(bodies, n);
   for(int i = 0; i < n; i++) bodies[i] = MathAbs(r[i].close - r[i].open);
   ArraySort(bodies);
   double median = bodies[n / 2];
   if(median <= 0) { g_driftDir = 0; return; }

   g_spikeThresh = median * InpSpikeMult;
   double sumSigned = 0.0, sumAbs = 0.0;
   int cnt = 0;
   g_barsSinceSpike = n;
   for(int i = 0; i < n; i++)   // i = 0 est la derniere barre cloturee
     {
      double body = r[i].close - r[i].open;
      if(MathAbs(body) >= g_spikeThresh)
        {
         if(cnt == 0) g_barsSinceSpike = i;
         sumSigned += body;
         sumAbs    += MathAbs(body);
         cnt++;
        }
     }
   g_spikeCount = cnt;
   g_avgSpike   = cnt > 0 ? sumAbs / cnt : 0.0;
   // La derive va dans le sens oppose aux pics
   g_driftDir   = cnt >= InpMinSpikes ? (sumSigned > 0 ? -1 : 1) : 0;
  }

void CheckDriftEntry()
  {
   if(g_driftDir == 0 || g_avgSpike <= 0) return;
   if(g_barsSinceSpike < InpCooldownBars) return;

   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(hDriftEMA, 0, 1, 2, ema) < 2) return;
   double close1 = iClose(_Symbol, InpTimeframe, 1);

   // Confirmation : prix du bon cote de l'EMA et EMA orientee dans le sens de la derive
   bool confirm = g_driftDir > 0 ? (close1 > ema[0] && ema[0] > ema[1])
                                 : (close1 < ema[0] && ema[0] < ema[1]);
   if(!confirm) return;

   OpenPosition(g_driftDir, g_avgSpike * InpDriftSLSpike,
                g_avgSpike * InpDriftTPSpike, "SyntX DRIFT");
  }

void ManageDriftExit()
  {
   if(InpDriftMaxBars <= 0) return;
   int maxSeconds = InpDriftMaxBars * PeriodSeconds(InpTimeframe);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(TimeCurrent() - opened >= maxSeconds) trade.PositionClose(ticket);
     }
  }

//+------------------------------------------------------------------+
//| MOTEUR TREND                                                     |
//+------------------------------------------------------------------+
void CheckTrendEntry()
  {
   double fast[], slow[], adx[], atr[];
   ArraySetAsSeries(fast, true); ArraySetAsSeries(slow, true);
   ArraySetAsSeries(adx, true);  ArraySetAsSeries(atr, true);
   if(CopyBuffer(hFast, 0, 1, 2, fast) < 2) return;
   if(CopyBuffer(hSlow, 0, 1, 2, slow) < 2) return;
   if(CopyBuffer(hADX, 0, 1, 1, adx) < 1)   return;
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1)   return;
   if(adx[0] < InpADXMin || atr[0] <= 0)   return;

   int dir = 0;
   if(fast[1] <= slow[1] && fast[0] > slow[0]) dir = 1;   // croisement haussier
   if(fast[1] >= slow[1] && fast[0] < slow[0]) dir = -1;  // croisement baissier
   if(dir == 0) return;

   OpenPosition(dir, atr[0] * InpSL_ATR, atr[0] * InpTP_ATR, "SyntX TREND");
  }

void ManageTrailing()
  {
   if(InpTrail_ATR <= 0) return;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1 || atr[0] <= 0) return;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double dist   = atr[0] * InpTrail_ATR;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      if(type == POSITION_TYPE_BUY)
        {
         double newSL = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID) - dist, digits);
         if(newSL > sl + _Point) trade.PositionModify(ticket, newSL, tp);
        }
      else
        {
         double newSL = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK) + dist, digits);
         if(sl == 0 || newSL < sl - _Point) trade.PositionModify(ticket, newSL, tp);
        }
     }
  }

//+------------------------------------------------------------------+
void ShowStatus()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = g_peakEquity > 0 ? (g_peakEquity - eq) / g_peakEquity * 100.0 : 0.0;
   string s = StringFormat("SyntX Guardian | %s | moteur %s\n", _Symbol,
                           g_engine == ENGINE_DRIFT ? "DRIFT" : "TREND");
   s += StringFormat("Equity %.2f | DD %.2f%% | trades aujourd'hui %d%s\n",
                     eq, dd, g_tradesToday, g_haltedForever ? " | ARRETE (coupe-circuit)" : "");
   if(g_engine == ENGINE_DRIFT)
      s += StringFormat("Pics: %d | taille moy. %.2f | derive %s | barres depuis pic %d",
                        g_spikeCount, g_avgSpike,
                        g_driftDir > 0 ? "HAUSSE" : (g_driftDir < 0 ? "BAISSE" : "?"),
                        g_barsSinceSpike);
   Comment(s);
  }
//+------------------------------------------------------------------+
