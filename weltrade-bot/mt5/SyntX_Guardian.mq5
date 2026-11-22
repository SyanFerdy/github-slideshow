//+------------------------------------------------------------------+
//|                                              SyntX_Guardian.mq5  |
//|  Expert Advisor pour les indices synthetiques Weltrade (MT5)     |
//|                                                                  |
//|  Indices autorises (les autres sont refuses, trop volatils) :    |
//|   - FX Vol 20 / 40 / 60    -> moteur TREND                       |
//|   - SFX Vol 20 / 40 / 60   -> moteur TREND                       |
//|   - GainX 400/600/800/999/1200 -> moteur DRIFT                   |
//|                                                                  |
//|  Chaque indice a son propre jeu de parametres (preset) :         |
//|  unite de temps, periodes, filtres, stops et risque adaptes a    |
//|  sa volatilite. L'unite de temps de chaque indice est reglable   |
//|  dans le groupe "Unite de temps par indice".                     |
//|  Les presets sont des POINTS DE DEPART a valider                 |
//|  avec le backtester (--optimize), pas des reglages garantis.     |
//|                                                                  |
//|  Gestion du risque : % du capital par trade, limite de perte     |
//|  journaliere, coupe-circuit sur drawdown, filtre de spread,      |
//|  une seule position a la fois. AUCUNE martingale, AUCUNE grille. |
//|                                                                  |
//|  Aucun resultat n'est garanti. Testez sur compte demo.          |
//+------------------------------------------------------------------+
#property copyright "SyntX Guardian"
#property version   "1.20"

#include <Trade\Trade.mqh>

enum ENUM_ENGINE
  {
   ENGINE_DRIFT = 1, // Drift (anti-pic, GainX)
   ENGINE_TREND = 2  // Trend (suivi de tendance, FX Vol / SFX Vol)
  };

enum ENUM_FAMILY
  {
   FAMILY_NONE  = 0,
   FAMILY_FXVOL = 1,
   FAMILY_SFX   = 2,
   FAMILY_GAINX = 3
  };

//--- General
input group "=== General ==="
input bool   InpUsePresets       = true;      // Utiliser le preset de l'indice (recommande)
input bool   InpAllowOtherSymbols = false;    // Autoriser les indices hors liste (deconseille)
input long   InpMagic            = 26112201;  // Numero magique
input int    InpMaxSpreadPts     = 0;         // Spread max en points (0 = pas de filtre)

//--- Risque
input group "=== Gestion du risque ==="
input double InpRiskPercent      = 0.5;   // Risque de base par trade (% equity), module par le preset
input double InpDailyLossPercent = 3.0;   // Perte max journaliere (%) -> stop jusqu'a demain
input double InpMaxDDPercent     = 15.0;  // Drawdown max depuis le pic (%) -> arret total
input int    InpMaxTradesPerDay  = 20;    // Nombre max de trades par jour

//--- Unite de temps par indice (utilisee avec les presets)
input group "=== Unite de temps par indice ==="
input ENUM_TIMEFRAMES InpTF_FXVol20  = PERIOD_H1;   // FX Vol 20
input ENUM_TIMEFRAMES InpTF_FXVol40  = PERIOD_M15;  // FX Vol 40
input ENUM_TIMEFRAMES InpTF_FXVol60  = PERIOD_M15;  // FX Vol 60
input ENUM_TIMEFRAMES InpTF_SFXVol20 = PERIOD_H1;   // SFX Vol 20
input ENUM_TIMEFRAMES InpTF_SFXVol40 = PERIOD_M15;  // SFX Vol 40
input ENUM_TIMEFRAMES InpTF_SFXVol60 = PERIOD_M15;  // SFX Vol 60
input ENUM_TIMEFRAMES InpTF_GainX    = PERIOD_M1;   // GainX (M1 fortement conseille)

//--- Parametres manuels (utilises seulement si InpUsePresets = false)
input group "=== Manuel : General ==="
input ENUM_ENGINE     InpEngine    = ENGINE_TREND;  // Moteur
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;     // Unite de temps des signaux

input group "=== Manuel : moteur DRIFT ==="
input int    InpSpikeLookback  = 3000;  // Barres analysees pour les statistiques de pics
input double InpSpikeMult      = 6.0;   // Pic = corps > X fois le corps median
input int    InpMinSpikes      = 5;     // Nb min de pics observes pour trader
input int    InpDriftEMA       = 50;    // EMA de confirmation de la derive
input int    InpCooldownBars   = 3;     // Barres a attendre apres un pic
input double InpDriftSLSpike   = 1.2;   // Stop = X fois la taille moyenne d'un pic
input double InpDriftTPSpike   = 0.6;   // Objectif = X fois la taille moyenne d'un pic
input int    InpDriftMaxBars   = 120;   // Sortie forcee apres N barres (0 = off)

input group "=== Manuel : moteur TREND ==="
input int    InpFastEMA      = 20;    // EMA rapide
input int    InpSlowEMA      = 100;   // EMA lente
input int    InpADXPeriod    = 14;    // Periode ADX
input double InpADXMin       = 22.0;  // ADX minimum pour entrer
input int    InpATRPeriod    = 14;    // Periode ATR
input double InpSL_ATR       = 2.0;   // Stop = X * ATR
input double InpTP_ATR       = 4.0;   // Objectif = X * ATR (0 = pas d'objectif)
input double InpTrail_ATR    = 2.5;   // Trailing stop = X * ATR (0 = off)

//--- Jeu de parametres effectivement utilise
struct SParams
  {
   string          name;
   ENUM_ENGINE     engine;
   ENUM_TIMEFRAMES tf;
   double          riskMult;     // multiplicateur du risque de base
   int             expectedDrift; // +1 / -1 attendu (0 = pas de controle)
   // drift
   int             lookback;
   double          spikeMult;
   int             minSpikes;
   int             driftEMA;
   int             cooldown;
   double          slSpike;
   double          tpSpike;
   int             maxBars;
   // trend
   int             fast;
   int             slow;
   int             adxPeriod;
   double          adxMin;
   int             atrPeriod;
   double          slATR;
   double          tpATR;
   double          trailATR;
  };

SParams P;

//--- Etat global
CTrade      trade;
int         hDriftEMA = INVALID_HANDLE;
int         hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE;
int         hADX  = INVALID_HANDLE, hATR  = INVALID_HANDLE;
datetime    g_lastBar       = 0;
double      g_peakEquity    = 0.0;
double      g_dayStartEq    = 0.0;
int         g_dayOfYear     = -1;
int         g_tradesToday   = 0;
bool        g_haltedForever = false;

//--- Statistiques de pics (moteur DRIFT)
int    g_driftDir       = 0;    // +1 = derive haussiere, -1 = baissiere, 0 = inconnu
int    g_spikeCount     = 0;
double g_avgSpike       = 0.0;  // taille moyenne d'un pic (en prix)
int    g_barsSinceSpike = 0;
double g_spikeThresh    = 0.0;

//+------------------------------------------------------------------+
//| Identification de l'indice a partir du nom du symbole            |
//+------------------------------------------------------------------+
string NormalizeSymbol(string s)
  {
   StringToUpper(s);
   StringReplace(s, " ", "");
   StringReplace(s, ".", "");
   StringReplace(s, "_", "");
   StringReplace(s, "-", "");
   return s;
  }

int NumberAfter(const string s, const string key)
  {
   int pos = StringFind(s, key);
   if(pos < 0) return -1;
   int i = pos + StringLen(key);
   string digits = "";
   while(i < StringLen(s))
     {
      ushort ch = StringGetCharacter(s, i);
      if(ch < '0' || ch > '9') break;
      digits += ShortToString(ch);
      i++;
     }
   return digits == "" ? -1 : (int)StringToInteger(digits);
  }

ENUM_FAMILY DetectIndex(const string symbol, int &level)
  {
   string s = NormalizeSymbol(symbol);
   level = -1;
   // SFX doit etre teste avant FX (SFXVOL contient FXVOL)
   if(StringFind(s, "SFXVOL") >= 0) { level = NumberAfter(s, "SFXVOL"); return FAMILY_SFX; }
   if(StringFind(s, "FXVOL") >= 0)  { level = NumberAfter(s, "FXVOL");  return FAMILY_FXVOL; }
   if(StringFind(s, "GAINX") >= 0)  { level = NumberAfter(s, "GAINX");  return FAMILY_GAINX; }
   return FAMILY_NONE;
  }

//+------------------------------------------------------------------+
//| Presets par indice                                               |
//+------------------------------------------------------------------+
void SetTrend(string name, ENUM_TIMEFRAMES tf, double riskMult, int fast, int slow,
              double adxMin, double slATR, double tpATR, double trailATR)
  {
   P.name = name; P.engine = ENGINE_TREND; P.tf = tf; P.riskMult = riskMult;
   P.expectedDrift = 0;
   P.fast = fast; P.slow = slow; P.adxPeriod = 14; P.adxMin = adxMin;
   P.atrPeriod = 14; P.slATR = slATR; P.tpATR = tpATR; P.trailATR = trailATR;
  }

void SetDrift(string name, double riskMult, int lookback, int ema, int cooldown,
              double slSpike, double tpSpike, int maxBars)
  {
   P.name = name; P.engine = ENGINE_DRIFT; P.tf = InpTF_GainX; P.riskMult = riskMult;
   P.expectedDrift = 1;   // GainX : derive haussiere, pics baissiers
   P.lookback = lookback; P.spikeMult = 6.0; P.minSpikes = 5; P.driftEMA = ema;
   P.cooldown = cooldown; P.slSpike = slSpike; P.tpSpike = tpSpike; P.maxBars = maxBars;
  }

bool LoadPreset(ENUM_FAMILY fam, int level)
  {
   switch(fam)
     {
      //                  nom          UT (input)      risque fast slow ADX  SL   TP   trail
      case FAMILY_FXVOL:
         if(level == 20) { SetTrend("FX Vol 20",  InpTF_FXVol20,  1.0, 20, 100, 20, 2.0, 4.0, 2.5); return true; }
         if(level == 40) { SetTrend("FX Vol 40",  InpTF_FXVol40,  1.0, 20, 100, 22, 2.2, 4.0, 2.5); return true; }
         if(level == 60) { SetTrend("FX Vol 60",  InpTF_FXVol60,  0.8, 30, 150, 25, 2.5, 4.5, 3.0); return true; }
         return false;
      case FAMILY_SFX:
         if(level == 20) { SetTrend("SFX Vol 20", InpTF_SFXVol20, 1.0, 20, 120, 22, 2.2, 4.0, 2.8); return true; }
         if(level == 40) { SetTrend("SFX Vol 40", InpTF_SFXVol40, 0.8, 25, 150, 25, 2.5, 4.5, 3.0); return true; }
         if(level == 60) { SetTrend("SFX Vol 60", InpTF_SFXVol60, 0.6, 30, 200, 28, 3.0, 5.0, 3.5); return true; }
         return false;
      case FAMILY_GAINX:
        {
         // Niveau inconnu -> preset du niveau le plus proche
         int levels[] = {400, 600, 800, 999, 1200};
         int best = 999, bestDiff = INT_MAX;
         for(int i = 0; i < ArraySize(levels); i++)
           {
            int d = MathAbs(levels[i] - (level > 0 ? level : 999));
            if(d < bestDiff) { bestDiff = d; best = levels[i]; }
           }
         //                         nom             risque lookback EMA cooldown SL   TP   maxBars
         if(best == 400)  SetDrift("GainX 400",  0.7, 2000, 30, 2, 1.3, 0.5,  30);
         if(best == 600)  SetDrift("GainX 600",  0.8, 2500, 40, 3, 1.2, 0.6,  45);
         if(best == 800)  SetDrift("GainX 800",  0.9, 3000, 50, 3, 1.2, 0.6,  60);
         if(best == 999)  SetDrift("GainX 999",  1.0, 3500, 50, 4, 1.2, 0.6,  80);
         if(best == 1200) SetDrift("GainX 1200", 1.0, 4000, 60, 4, 1.1, 0.7, 100);
         return true;
        }
      default:
         return false;
     }
  }

void LoadManual()
  {
   P.name = "Manuel"; P.engine = InpEngine; P.tf = InpTimeframe; P.riskMult = 1.0;
   P.expectedDrift = 0;
   P.lookback = InpSpikeLookback; P.spikeMult = InpSpikeMult; P.minSpikes = InpMinSpikes;
   P.driftEMA = InpDriftEMA; P.cooldown = InpCooldownBars; P.slSpike = InpDriftSLSpike;
   P.tpSpike = InpDriftTPSpike; P.maxBars = InpDriftMaxBars;
   P.fast = InpFastEMA; P.slow = InpSlowEMA; P.adxPeriod = InpADXPeriod; P.adxMin = InpADXMin;
   P.atrPeriod = InpATRPeriod; P.slATR = InpSL_ATR; P.tpATR = InpTP_ATR; P.trailATR = InpTrail_ATR;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   int level;
   ENUM_FAMILY fam = DetectIndex(_Symbol, level);
   bool allowed = (fam == FAMILY_GAINX) ||
                  ((fam == FAMILY_FXVOL || fam == FAMILY_SFX) && (level == 20 || level == 40 || level == 60));

   if(!allowed && !InpAllowOtherSymbols)
     {
      PrintFormat("%s n'est pas dans la liste autorisee (FX Vol / SFX Vol 20-40-60, GainX). "
                  "Le bot refuse de trader cet indice.", _Symbol);
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUsePresets && allowed) LoadPreset(fam, level);
   else                         LoadManual();

   if(P.engine == ENGINE_DRIFT && PeriodSeconds(P.tf) > PeriodSeconds(PERIOD_M5))
      PrintFormat("ATTENTION : GainX en %s. Les pics durent quelques secondes : "
                  "au-dela de M5 ils sont noyes dans la barre. M1 conseille.", EnumToString(P.tf));

   if(P.engine == ENGINE_DRIFT)
     {
      hDriftEMA = iMA(_Symbol, P.tf, P.driftEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(hDriftEMA == INVALID_HANDLE) return INIT_FAILED;
     }
   else
     {
      hFast = iMA(_Symbol, P.tf, P.fast, 0, MODE_EMA, PRICE_CLOSE);
      hSlow = iMA(_Symbol, P.tf, P.slow, 0, MODE_EMA, PRICE_CLOSE);
      hADX  = iADX(_Symbol, P.tf, P.adxPeriod);
      hATR  = iATR(_Symbol, P.tf, P.atrPeriod);
      if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE ||
         hADX == INVALID_HANDLE  || hATR == INVALID_HANDLE)
         return INIT_FAILED;
     }

   g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEq = g_peakEquity;
   PrintFormat("SyntX Guardian sur %s : preset %s, moteur %s, UT %s, risque %.2f%%",
               _Symbol, P.name, P.engine == ENGINE_DRIFT ? "DRIFT" : "TREND",
               EnumToString(P.tf), InpRiskPercent * P.riskMult);
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
   if(P.engine == ENGINE_TREND) ManageTrailing();

   datetime barTime = iTime(_Symbol, P.tf, 0);
   if(barTime == g_lastBar) return;
   g_lastBar = barTime;

   if(P.engine == ENGINE_DRIFT)
     {
      UpdateSpikeStats();
      ManageDriftExit();
     }

   ShowStatus();

   if(!TradingAllowed()) return;
   if(HasPosition()) return;

   if(P.engine == ENGINE_DRIFT) CheckDriftEntry();
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

   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent * P.riskMult / 100.0;
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
//| MOTEUR DRIFT (GainX)                                             |
//+------------------------------------------------------------------+
void UpdateSpikeStats()
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, P.tf, 1, P.lookback, r);
   if(n < 200) { g_driftDir = 0; return; }

   double bodies[];
   ArrayResize(bodies, n);
   for(int i = 0; i < n; i++) bodies[i] = MathAbs(r[i].close - r[i].open);
   ArraySort(bodies);
   double median = bodies[n / 2];
   if(median <= 0) { g_driftDir = 0; return; }

   g_spikeThresh = median * P.spikeMult;
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
   g_driftDir   = cnt >= P.minSpikes ? (sumSigned > 0 ? -1 : 1) : 0;

   // Securite : si les donnees contredisent le comportement attendu de
   // l'indice (GainX = pics baissiers), on ne trade pas.
   if(P.expectedDrift != 0 && g_driftDir != 0 && g_driftDir != P.expectedDrift)
      g_driftDir = 0;
  }

void CheckDriftEntry()
  {
   if(g_driftDir == 0 || g_avgSpike <= 0) return;
   if(g_barsSinceSpike < P.cooldown) return;

   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyBuffer(hDriftEMA, 0, 1, 2, ema) < 2) return;
   double close1 = iClose(_Symbol, P.tf, 1);

   // Confirmation : prix du bon cote de l'EMA et EMA orientee dans le sens de la derive
   bool confirm = g_driftDir > 0 ? (close1 > ema[0] && ema[0] > ema[1])
                                 : (close1 < ema[0] && ema[0] < ema[1]);
   if(!confirm) return;

   OpenPosition(g_driftDir, g_avgSpike * P.slSpike, g_avgSpike * P.tpSpike, "SyntX " + P.name);
  }

void ManageDriftExit()
  {
   if(P.maxBars <= 0) return;
   int maxSeconds = P.maxBars * PeriodSeconds(P.tf);
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
//| MOTEUR TREND (FX Vol / SFX Vol)                                  |
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
   if(adx[0] < P.adxMin || atr[0] <= 0)     return;

   int dir = 0;
   if(fast[1] <= slow[1] && fast[0] > slow[0]) dir = 1;   // croisement haussier
   if(fast[1] >= slow[1] && fast[0] < slow[0]) dir = -1;  // croisement baissier
   if(dir == 0) return;

   OpenPosition(dir, atr[0] * P.slATR, atr[0] * P.tpATR, "SyntX " + P.name);
  }

void ManageTrailing()
  {
   if(P.trailATR <= 0) return;
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hATR, 0, 1, 1, atr) < 1 || atr[0] <= 0) return;
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double dist   = atr[0] * P.trailATR;

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
   string s = StringFormat("SyntX Guardian | %s | preset %s | %s %s | risque %.2f%%\n",
                           _Symbol, P.name, P.engine == ENGINE_DRIFT ? "DRIFT" : "TREND",
                           EnumToString(P.tf), InpRiskPercent * P.riskMult);
   s += StringFormat("Equity %.2f | DD %.2f%% | trades aujourd'hui %d%s\n",
                     eq, dd, g_tradesToday, g_haltedForever ? " | ARRETE (coupe-circuit)" : "");
   if(P.engine == ENGINE_DRIFT)
      s += StringFormat("Pics: %d | taille moy. %.2f | derive %s | barres depuis pic %d",
                        g_spikeCount, g_avgSpike,
                        g_driftDir > 0 ? "HAUSSE" : (g_driftDir < 0 ? "BAISSE" : "?"),
                        g_barsSinceSpike);
   Comment(s);
  }
//+------------------------------------------------------------------+
