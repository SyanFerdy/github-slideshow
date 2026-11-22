//+------------------------------------------------------------------+
//|                                              SyntX_Guardian.mq5  |
//|  Expert Advisor pour les indices synthetiques Weltrade (MT5)     |
//|                                                                  |
//|  Indices autorises (les autres sont refuses, trop volatils) :    |
//|   - FX Vol 20 / 40 / 60  et  SFX Vol 20 / 40 / 60                |
//|       -> strategie au choix par indice : croisement d'EMA,       |
//|          cassure de canal, ou retour a la moyenne                |
//|   - GainX 400/600/800/999/1200 -> strategie DRIFT (anti-pic)     |
//|                                                                  |
//|  Reglages par indice, par ordre de priorite :                    |
//|   1. fichier de calibration Common\Files\SyntX_Guardian_presets.csv|
//|      (produit par backtest/calibrate.py a partir de vos donnees) |
//|   2. entrees "Unite de temps / Strategie par indice"              |
//|   3. presets integres (LoadPreset)                               |
//|  Un indice desactive par la calibration ou par son interrupteur  |
//|  ne trade pas.                                                   |
//|                                                                  |
//|  Gestion du risque (partagee entre tous les graphiques du meme   |
//|  compte et du meme numero magique, conservee au redemarrage) :   |
//|   - % du capital par trade, plafond de risque total ouvert       |
//|   - limite de perte journaliere, coupe-circuit sur drawdown      |
//|     (depots et retraits pris en compte)                          |
//|   - filtres de spread, controles de marge et de distances min.   |
//|   - AUCUNE martingale, AUCUNE grille                             |
//|                                                                  |
//|  Journal : Common\Files\SyntX_Guardian_trades.csv                |
//|                                                                  |
//|  Aucun resultat n'est garanti. Testez sur compte demo.          |
//+------------------------------------------------------------------+
#property copyright "SyntX Guardian"
#property version   "2.10"

#include <Trade\Trade.mqh>

//--- Strategies internes
enum ENUM_STRATEGY
  {
   STRAT_EMA_CROSS = 0, // Croisement d'EMA (suivi de tendance)
   STRAT_BREAKOUT  = 1, // Cassure de canal (Donchian)
   STRAT_MEANREV   = 2, // Retour a la moyenne (Bollinger + RSI)
   STRAT_DRIFT     = 3  // Drift anti-pic (GainX)
  };

//--- Strategies proposees pour FX Vol / SFX Vol
enum ENUM_VOL_STRATEGY
  {
   VS_EMA_CROSS = 0, // Croisement d'EMA (suivi de tendance)
   VS_BREAKOUT  = 1, // Cassure de canal (Donchian)
   VS_MEANREV   = 2  // Retour a la moyenne (Bollinger + RSI)
  };

enum ENUM_FAMILY
  {
   FAMILY_NONE  = 0,
   FAMILY_FXVOL = 1,
   FAMILY_SFX   = 2,
   FAMILY_GAINX = 3
  };

//=== General
input group "=== General ==="
input bool   InpUsePresets        = true;      // Utiliser le preset de l'indice (recommande)
input bool   InpUseCalibration    = true;      // Lire le fichier de calibration (si present)
input bool   InpAllowOtherSymbols = false;     // Autoriser les indices hors liste (deconseille)
input long   InpMagic             = 26112201;  // Numero magique (le MEME sur tous les graphiques)
input bool   InpLogTrades         = true;      // Ecrire le journal des trades (CSV)

//=== Activation par indice
input group "=== Activation par indice ==="
input bool InpEnable_FXVol20  = true;  // FX Vol 20
input bool InpEnable_FXVol40  = true;  // FX Vol 40
input bool InpEnable_FXVol60  = true;  // FX Vol 60
input bool InpEnable_SFXVol20 = true;  // SFX Vol 20
input bool InpEnable_SFXVol40 = true;  // SFX Vol 40
input bool InpEnable_SFXVol60 = true;  // SFX Vol 60
input bool InpEnable_GainX    = true;  // GainX (tous niveaux)

//=== Risque
input group "=== Gestion du risque ==="
input double InpRiskPercent         = 0.5;   // Risque de base par trade (% equity), module par le preset
input double InpMaxTotalRiskPercent = 2.0;   // Risque total max, toutes positions du bot (%)
input double InpDailyLossPercent    = 3.0;   // Perte max journaliere (%) -> stop jusqu'a demain
input double InpMaxDDPercent        = 15.0;  // Drawdown max depuis le pic (%) -> arret total
input int    InpMaxTradesPerDay     = 20;    // Nombre max de trades par jour et par indice
input int    InpMaxSpreadPts        = 0;     // Spread max en points (0 = pas de filtre)
input double InpMaxSpreadSLRatio    = 0.10;  // Spread max en fraction du stop (0 = off)
input double InpMaxMarginUse        = 0.50;  // Part max de la marge libre utilisee par un trade
input bool   InpResetHalt           = false; // Rearmer le coupe-circuit (remettre a false ensuite)

//=== Unite de temps par indice
input group "=== Unite de temps par indice ==="
input ENUM_TIMEFRAMES InpTF_FXVol20  = PERIOD_H1;   // FX Vol 20
input ENUM_TIMEFRAMES InpTF_FXVol40  = PERIOD_M15;  // FX Vol 40
input ENUM_TIMEFRAMES InpTF_FXVol60  = PERIOD_M15;  // FX Vol 60
input ENUM_TIMEFRAMES InpTF_SFXVol20 = PERIOD_H1;   // SFX Vol 20
input ENUM_TIMEFRAMES InpTF_SFXVol40 = PERIOD_M15;  // SFX Vol 40
input ENUM_TIMEFRAMES InpTF_SFXVol60 = PERIOD_M15;  // SFX Vol 60
input ENUM_TIMEFRAMES InpTF_GainX    = PERIOD_M1;   // GainX (M1 fortement conseille)

//=== Strategie par indice
input group "=== Strategie par indice (FX Vol / SFX Vol) ==="
input ENUM_VOL_STRATEGY InpS_FXVol20  = VS_EMA_CROSS; // FX Vol 20
input ENUM_VOL_STRATEGY InpS_FXVol40  = VS_EMA_CROSS; // FX Vol 40
input ENUM_VOL_STRATEGY InpS_FXVol60  = VS_EMA_CROSS; // FX Vol 60
input ENUM_VOL_STRATEGY InpS_SFXVol20 = VS_EMA_CROSS; // SFX Vol 20
input ENUM_VOL_STRATEGY InpS_SFXVol40 = VS_EMA_CROSS; // SFX Vol 40
input ENUM_VOL_STRATEGY InpS_SFXVol60 = VS_EMA_CROSS; // SFX Vol 60

//=== Parametres manuels (utilises seulement si InpUsePresets = false)
input group "=== Manuel : General ==="
input ENUM_STRATEGY   InpStrategy  = STRAT_EMA_CROSS; // Strategie
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;      // Unite de temps des signaux

input group "=== Manuel : DRIFT ==="
input int    InpSpikeLookback = 3000;  // Barres analysees pour les statistiques de pics
input double InpSpikeMult     = 6.0;   // Pic = corps > X fois le corps median
input int    InpMinSpikes     = 5;     // Nb min de pics observes pour trader
input int    InpDriftEMA      = 50;    // EMA de confirmation de la derive
input int    InpCooldownBars  = 3;     // Barres a attendre apres un pic
input double InpDriftSLSpike  = 1.2;   // Stop = X fois la taille moyenne d'un pic
input double InpDriftTPSpike  = 0.6;   // Objectif = X fois la taille moyenne d'un pic
input int    InpDriftMaxBars  = 120;   // Sortie forcee apres N barres (0 = off)

input group "=== Manuel : EMA / Cassure / Retour a la moyenne ==="
input int    InpFastEMA    = 20;    // EMA rapide
input int    InpSlowEMA    = 100;   // EMA lente
input int    InpADXPeriod  = 14;    // Periode ADX (Wilder)
input double InpADXMin     = 22.0;  // ADX minimum (croisement d'EMA)
input int    InpATRPeriod  = 14;    // Periode ATR
input double InpSL_ATR     = 2.0;   // Stop = X * ATR
input double InpTP_ATR     = 4.0;   // Objectif = X * ATR (0 = pas d'objectif)
input double InpTrail_ATR  = 2.5;   // Trailing stop = X * ATR (0 = off)
input int    InpBrkPeriod  = 20;    // Cassure : periode du canal
input int    InpBBPeriod   = 20;    // Retour moyenne : periode Bollinger
input double InpBBDev      = 2.0;   // Retour moyenne : ecart-type Bollinger
input int    InpRSIPeriod  = 14;    // Retour moyenne : periode RSI
input double InpRSILow     = 30.0;  // Retour moyenne : RSI survente (surachat = 100 - X)
input double InpADXMaxMR   = 25.0;  // Retour moyenne : ADX max (marche sans tendance)
input double InpMRSL_ATR   = 2.0;   // Retour moyenne : stop = X * ATR
input int    InpMRMaxBars  = 40;    // Retour moyenne : sortie forcee apres N barres

//--- Jeu de parametres effectivement utilise
struct SParams
  {
   string          name;
   ENUM_STRATEGY   strat;
   ENUM_TIMEFRAMES tf;
   double          riskMult;
   int             expectedDrift;
   // drift
   int             lookback;
   double          spikeMult;
   int             minSpikes;
   int             driftEMA;
   int             cooldown;
   double          slSpike;
   double          tpSpike;
   int             maxBars;     // sortie temporelle (drift et retour a la moyenne)
   // ema / cassure
   int             fast;
   int             slow;
   int             adxPeriod;
   double          adxMin;
   int             atrPeriod;
   double          slATR;
   double          tpATR;
   double          trailATR;
   int             brkPeriod;
   // retour a la moyenne
   int             bbPeriod;
   double          bbDev;
   int             rsiPeriod;
   double          rsiLow;
   double          adxMaxMR;
   double          mrSlATR;
  };

SParams     P;
ENUM_FAMILY g_family = FAMILY_NONE;

//--- Etat
CTrade   trade;
int      hDriftEMA = INVALID_HANDLE, hFast = INVALID_HANDLE, hSlow = INVALID_HANDLE;
int      hADX = INVALID_HANDLE, hATR = INVALID_HANDLE, hBB = INVALID_HANDLE, hRSI = INVALID_HANDLE;
datetime g_lastBar      = 0;
ulong    g_pendingClose = 0;   // position a fermer (nouvel essai a chaque tick)

//--- Statistiques de pics (DRIFT)
int    g_driftDir = 0, g_spikeCount = 0, g_barsSinceSpike = 0;
double g_avgSpike = 0.0, g_spikeThresh = 0.0;

const string LOG_FILE    = "SyntX_Guardian_trades.csv";
const string PRESET_FILE = "SyntX_Guardian_presets.csv";

//+------------------------------------------------------------------+
//| Etat persistant (variables globales du terminal)                 |
//| Cle = compte + numero magique : un compte demo et un compte reel |
//| sur le meme terminal ont chacun leur propre etat.                |
//+------------------------------------------------------------------+
string GVKey(const string k)
  {
   return "SXG_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" +
          IntegerToString(InpMagic) + "_" + k;
  }
double GVGet(const string k, double def)  { string n = GVKey(k); return GlobalVariableCheck(n) ? GlobalVariableGet(n) : def; }
void   GVSet(const string k, double v)    { GlobalVariableSet(GVKey(k), v); }
void   GVDel(const string k)              { GlobalVariableDel(GVKey(k)); }

int TodayId()
  {
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return t.year * 10000 + t.mon * 100 + t.day;
  }

//+------------------------------------------------------------------+
//| Identification de l'indice                                       |
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

string SymKey() { return NormalizeSymbol(_Symbol); }

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

string StratName(ENUM_STRATEGY s)
  {
   switch(s)
     {
      case STRAT_EMA_CROSS: return "EMA";
      case STRAT_BREAKOUT:  return "CASSURE";
      case STRAT_MEANREV:   return "RETOUR_MOY";
      case STRAT_DRIFT:     return "DRIFT";
     }
   return "?";
  }

bool IndexEnabledByInput(ENUM_FAMILY fam, int level)
  {
   if(fam == FAMILY_GAINX) return InpEnable_GainX;
   if(fam == FAMILY_FXVOL)
      return level == 20 ? InpEnable_FXVol20 : (level == 40 ? InpEnable_FXVol40 : (level == 60 ? InpEnable_FXVol60 : true));
   if(fam == FAMILY_SFX)
      return level == 20 ? InpEnable_SFXVol20 : (level == 40 ? InpEnable_SFXVol40 : (level == 60 ? InpEnable_SFXVol60 : true));
   return true;
  }

//+------------------------------------------------------------------+
//| Presets integres (identiques a PRESETS dans syntx_backtest.py)   |
//+------------------------------------------------------------------+
void SetVol(string name, ENUM_TIMEFRAMES tf, ENUM_VOL_STRATEGY vs, double riskMult,
            int fast, int slow, double adxMin, double slATR, double tpATR, double trailATR,
            int brkPeriod, double bbDev, double rsiLow, double adxMaxMR, double mrSlATR)
  {
   P.name = name; P.tf = tf; P.riskMult = riskMult; P.expectedDrift = 0;
   P.strat = vs == VS_BREAKOUT ? STRAT_BREAKOUT : (vs == VS_MEANREV ? STRAT_MEANREV : STRAT_EMA_CROSS);
   P.fast = fast; P.slow = slow; P.adxPeriod = 14; P.adxMin = adxMin; P.atrPeriod = 14;
   P.slATR = slATR; P.tpATR = tpATR; P.trailATR = trailATR; P.brkPeriod = brkPeriod;
   P.bbPeriod = 20; P.bbDev = bbDev; P.rsiPeriod = 14; P.rsiLow = rsiLow;
   P.adxMaxMR = adxMaxMR; P.mrSlATR = mrSlATR;
   P.maxBars = P.strat == STRAT_MEANREV ? 40 : 0;
  }

void SetDrift(string name, double riskMult, int lookback, int ema, int cooldown,
              double slSpike, double tpSpike, int maxBars)
  {
   P.name = name; P.strat = STRAT_DRIFT; P.tf = InpTF_GainX; P.riskMult = riskMult;
   P.expectedDrift = 1;   // GainX : derive haussiere, pics baissiers
   P.lookback = lookback; P.spikeMult = 6.0; P.minSpikes = 5; P.driftEMA = ema;
   P.cooldown = cooldown; P.slSpike = slSpike; P.tpSpike = tpSpike; P.maxBars = maxBars;
  }

bool LoadPreset(ENUM_FAMILY fam, int level)
  {
   //                                      UT              strategie       risque fast slow ADX  SL   TP   trail canal BBdev RSIbas ADXmaxMR SL_MR
   if(fam == FAMILY_FXVOL)
     {
      if(level == 20) { SetVol("FX Vol 20",  InpTF_FXVol20,  InpS_FXVol20,  1.0, 20, 100, 20, 2.0, 4.0, 2.5, 20, 2.0, 30, 25, 2.0); return true; }
      if(level == 40) { SetVol("FX Vol 40",  InpTF_FXVol40,  InpS_FXVol40,  1.0, 20, 100, 22, 2.2, 4.0, 2.5, 30, 2.0, 30, 25, 2.2); return true; }
      if(level == 60) { SetVol("FX Vol 60",  InpTF_FXVol60,  InpS_FXVol60,  0.8, 30, 150, 25, 2.5, 4.5, 3.0, 40, 2.2, 28, 25, 2.5); return true; }
      return false;
     }
   if(fam == FAMILY_SFX)
     {
      if(level == 20) { SetVol("SFX Vol 20", InpTF_SFXVol20, InpS_SFXVol20, 1.0, 20, 120, 22, 2.2, 4.0, 2.8, 25, 2.0, 30, 25, 2.2); return true; }
      if(level == 40) { SetVol("SFX Vol 40", InpTF_SFXVol40, InpS_SFXVol40, 0.8, 25, 150, 25, 2.5, 4.5, 3.0, 35, 2.2, 28, 25, 2.5); return true; }
      if(level == 60) { SetVol("SFX Vol 60", InpTF_SFXVol60, InpS_SFXVol60, 0.6, 30, 200, 28, 3.0, 5.0, 3.5, 45, 2.2, 28, 25, 3.0); return true; }
      return false;
     }
   if(fam == FAMILY_GAINX)
     {
      // Niveau inconnu -> preset du niveau le plus proche
      int levels[] = {400, 600, 800, 999, 1200};
      int best = 999, bestDiff = INT_MAX;
      for(int i = 0; i < ArraySize(levels); i++)
        {
         int d = MathAbs(levels[i] - (level > 0 ? level : 999));
         if(d < bestDiff) { bestDiff = d; best = levels[i]; }
        }
      //                           nom           risque lookback EMA attente SL   TP   barres max
      if(best == 400)  SetDrift("GainX 400",  0.7, 2000, 30, 2, 1.3, 0.5,  30);
      if(best == 600)  SetDrift("GainX 600",  0.8, 2500, 40, 3, 1.2, 0.6,  45);
      if(best == 800)  SetDrift("GainX 800",  0.9, 3000, 50, 3, 1.2, 0.6,  60);
      if(best == 999)  SetDrift("GainX 999",  1.0, 3500, 50, 4, 1.2, 0.6,  80);
      if(best == 1200) SetDrift("GainX 1200", 1.0, 4000, 60, 4, 1.1, 0.7, 100);
      return true;
     }
   return false;
  }

void LoadManual()
  {
   P.name = "Manuel"; P.strat = InpStrategy; P.tf = InpTimeframe; P.riskMult = 1.0; P.expectedDrift = 0;
   P.lookback = InpSpikeLookback; P.spikeMult = InpSpikeMult; P.minSpikes = InpMinSpikes;
   P.driftEMA = InpDriftEMA; P.cooldown = InpCooldownBars; P.slSpike = InpDriftSLSpike; P.tpSpike = InpDriftTPSpike;
   P.fast = InpFastEMA; P.slow = InpSlowEMA; P.adxPeriod = InpADXPeriod; P.adxMin = InpADXMin;
   P.atrPeriod = InpATRPeriod; P.slATR = InpSL_ATR; P.tpATR = InpTP_ATR; P.trailATR = InpTrail_ATR;
   P.brkPeriod = InpBrkPeriod; P.bbPeriod = InpBBPeriod; P.bbDev = InpBBDev; P.rsiPeriod = InpRSIPeriod;
   P.rsiLow = InpRSILow; P.adxMaxMR = InpADXMaxMR; P.mrSlATR = InpMRSL_ATR;
   P.maxBars = P.strat == STRAT_DRIFT ? InpDriftMaxBars : (P.strat == STRAT_MEANREV ? InpMRMaxBars : 0);
  }

//+------------------------------------------------------------------+
//| Fichier de calibration (produit par backtest/calibrate.py)       |
//| Format : indice,cle,valeur  -  ex. "FX Vol 40,sl_atr,2.5"        |
//+------------------------------------------------------------------+
bool TFFromString(string s, ENUM_TIMEFRAMES &tf)
  {
   StringToUpper(s);
   if(s == "M1")  { tf = PERIOD_M1;  return true; }
   if(s == "M5")  { tf = PERIOD_M5;  return true; }
   if(s == "M15") { tf = PERIOD_M15; return true; }
   if(s == "M30") { tf = PERIOD_M30; return true; }
   if(s == "H1")  { tf = PERIOD_H1;  return true; }
   if(s == "H4")  { tf = PERIOD_H4;  return true; }
   return false;
  }

bool SetCalibratedValue(const string key, const string val)
  {
   double d = StringToDouble(val);
   int    n = (int)StringToInteger(val);
   if(key == "tf")
     {
      ENUM_TIMEFRAMES tf;
      if(!TFFromString(val, tf)) return false;
      P.tf = tf;
      return true;
     }
   if(key == "strategy")
     {
      ENUM_STRATEGY s;
      if(val == "ema_cross")     s = STRAT_EMA_CROSS;
      else if(val == "breakout") s = STRAT_BREAKOUT;
      else if(val == "meanrev")  s = STRAT_MEANREV;
      else if(val == "drift")    s = STRAT_DRIFT;
      else return false;
      // Coherence : DRIFT reserve a GainX, et GainX reserve a DRIFT
      if((s == STRAT_DRIFT) != (g_family == FAMILY_GAINX)) return false;
      P.strat = s;
      if(s == STRAT_MEANREV && P.maxBars == 0) P.maxBars = 40;
      if(s == STRAT_EMA_CROSS || s == STRAT_BREAKOUT) P.maxBars = 0;
      return true;
     }
   if(key == "risk_mult")   { P.riskMult = MathMin(MathMax(d, 0.0), 2.0); return true; }
   if(key == "fast")        { P.fast = n;        return n > 0; }
   if(key == "slow")        { P.slow = n;        return n > 0; }
   if(key == "adx_min")     { P.adxMin = d;      return true; }
   if(key == "sl_atr")      { P.slATR = d;       return d > 0; }
   if(key == "tp_atr")      { P.tpATR = d;       return d >= 0; }
   if(key == "trail_atr")   { P.trailATR = d;    return d >= 0; }
   if(key == "brk_period")  { P.brkPeriod = n;   return n > 1; }
   if(key == "bb_dev")      { P.bbDev = d;       return d > 0; }
   if(key == "rsi_low")     { P.rsiLow = d;      return d > 0 && d < 50; }
   if(key == "adx_max_mr")  { P.adxMaxMR = d;    return true; }
   if(key == "mr_sl_atr")   { P.mrSlATR = d;     return d > 0; }
   if(key == "max_bars")    { P.maxBars = n;     return n >= 0; }
   if(key == "lookback")    { P.lookback = n;    return n >= 200; }
   if(key == "drift_ema")   { P.driftEMA = n;    return n > 0; }
   if(key == "cooldown")    { P.cooldown = n;    return n >= 0; }
   if(key == "sl_spike")    { P.slSpike = d;     return d > 0; }
   if(key == "tp_spike")    { P.tpSpike = d;     return d >= 0; }
   if(key == "spike_mult")  { P.spikeMult = d;   return d > 1; }
   if(key == "min_spikes")  { P.minSpikes = n;   return n > 0; }
   return false;
  }

//--- Retourne false si la calibration desactive cet indice
bool ApplyCalibration()
  {
   if(!InpUseCalibration) return true;
   int fh = FileOpen(PRESET_FILE, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ, ',');
   if(fh == INVALID_HANDLE)
     {
      Print("Pas de fichier de calibration : presets integres utilises.");
      return true;
     }
   bool enabled = true, found = false;
   int applied = 0, rejected = 0;
   while(!FileIsEnding(fh))
     {
      string name = FileReadString(fh);
      if(FileIsLineEnding(fh)) continue;
      string key  = FileReadString(fh);
      if(FileIsLineEnding(fh)) continue;
      string val  = FileReadString(fh);
      StringTrimLeft(name); StringTrimRight(name);
      StringTrimLeft(key);  StringTrimRight(key);
      StringTrimLeft(val);  StringTrimRight(val);
      if(StringCompare(name, P.name, false) != 0) continue;
      found = true;
      if(key == "enabled") { enabled = StringToInteger(val) != 0; continue; }
      if(SetCalibratedValue(key, val)) applied++;
      else { rejected++; PrintFormat("Calibration : valeur refusee %s = %s", key, val); }
     }
   FileClose(fh);
   if(found)
      PrintFormat("Calibration appliquee a %s : %d valeurs%s%s", P.name, applied,
                  rejected > 0 ? StringFormat(", %d refusees", rejected) : "",
                  enabled ? "" : " - INDICE DESACTIVE");
   else
      PrintFormat("%s absent du fichier de calibration : presets integres utilises.", P.name);
   return enabled;
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFillingBySymbol(_Symbol);

   int level;
   g_family = DetectIndex(_Symbol, level);
   bool allowed = (g_family == FAMILY_GAINX) ||
                  ((g_family == FAMILY_FXVOL || g_family == FAMILY_SFX) && (level == 20 || level == 40 || level == 60));
   if(!allowed && !InpAllowOtherSymbols)
     {
      PrintFormat("%s n'est pas dans la liste autorisee (FX Vol / SFX Vol 20-40-60, GainX). "
                  "Le bot refuse de trader cet indice.", _Symbol);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(allowed && !IndexEnabledByInput(g_family, level))
     {
      PrintFormat("%s est desactive dans les entrees (groupe Activation par indice).", _Symbol);
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpUsePresets && allowed) LoadPreset(g_family, level);
   else                         LoadManual();

   if(InpUsePresets && allowed && !ApplyCalibration())
     {
      PrintFormat("%s est desactive par la calibration (pas d'avantage valide sur ses donnees).", P.name);
      return INIT_PARAMETERS_INCORRECT;
     }

   if(!ValidateParams()) return INIT_PARAMETERS_INCORRECT;

   if(P.strat == STRAT_DRIFT && PeriodSeconds(P.tf) > PeriodSeconds(PERIOD_M5))
      PrintFormat("ATTENTION : DRIFT en %s. Les pics durent quelques secondes : au-dela de M5 "
                  "ils sont noyes dans la barre. M1 conseille.", EnumToString(P.tf));

   if(!CreateIndicators())
     {
      Print("Impossible de creer les indicateurs.");
      return INIT_FAILED;
     }

   if(InpResetHalt)
     {
      GVDel("HALT");
      GVSet("PEAK", AccountInfoDouble(ACCOUNT_EQUITY));
      Print("Coupe-circuit rearme. Remettez InpResetHalt a false.");
     }
   if(GVGet("HALT", 0) > 0)
      Print("Coupe-circuit ACTIF (drawdown max atteint precedemment) : le bot ne tradera pas. "
            "Analysez les resultats avant de le rearmer avec InpResetHalt = true.");

   PrintFormat("SyntX Guardian v2.1 sur %s : preset %s, strategie %s, UT %s, risque %.2f%%, "
               "distance min. %d pts, gel %d pts",
               _Symbol, P.name, StratName(P.strat), EnumToString(P.tf), InpRiskPercent * P.riskMult,
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
               (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL));
   return INIT_SUCCEEDED;
  }

bool ValidateParams()
  {
   string err = "";
   if(P.strat == STRAT_EMA_CROSS && (P.fast <= 0 || P.slow <= P.fast)) err = "EMA rapide/lente incoherentes";
   if((P.strat == STRAT_EMA_CROSS || P.strat == STRAT_BREAKOUT) && P.slATR <= 0) err = "stop nul";
   if(P.strat == STRAT_MEANREV && P.mrSlATR <= 0)                      err = "stop nul";
   if(P.strat == STRAT_BREAKOUT && P.brkPeriod < 2)                    err = "canal trop court";
   if(P.strat == STRAT_DRIFT && P.slSpike <= 0)                        err = "stop DRIFT nul";
   if(InpRiskPercent <= 0 || InpRiskPercent > 5)                       err = "risque par trade hors [0 ; 5] %";
   if(err != "")
     {
      Print("Parametres invalides : ", err);
      return false;
     }
   return true;
  }

bool CreateIndicators()
  {
   if(P.strat == STRAT_DRIFT)
     {
      hDriftEMA = iMA(_Symbol, P.tf, P.driftEMA, 0, MODE_EMA, PRICE_CLOSE);
      return hDriftEMA != INVALID_HANDLE;
     }
   hATR = iATR(_Symbol, P.tf, P.atrPeriod);
   hADX = iADXWilder(_Symbol, P.tf, P.adxPeriod);   // meme lissage que le backtester
   if(hATR == INVALID_HANDLE || hADX == INVALID_HANDLE) return false;
   if(P.strat == STRAT_EMA_CROSS)
     {
      hFast = iMA(_Symbol, P.tf, P.fast, 0, MODE_EMA, PRICE_CLOSE);
      hSlow = iMA(_Symbol, P.tf, P.slow, 0, MODE_EMA, PRICE_CLOSE);
      return hFast != INVALID_HANDLE && hSlow != INVALID_HANDLE;
     }
   if(P.strat == STRAT_MEANREV)
     {
      hBB  = iBands(_Symbol, P.tf, P.bbPeriod, 0, P.bbDev, PRICE_CLOSE);
      hRSI = iRSI(_Symbol, P.tf, P.rsiPeriod, PRICE_CLOSE);
      return hBB != INVALID_HANDLE && hRSI != INVALID_HANDLE;
     }
   return true;
  }

void OnDeinit(const int reason)
  {
   if(hDriftEMA != INVALID_HANDLE) IndicatorRelease(hDriftEMA);
   if(hFast != INVALID_HANDLE)     IndicatorRelease(hFast);
   if(hSlow != INVALID_HANDLE)     IndicatorRelease(hSlow);
   if(hADX != INVALID_HANDLE)      IndicatorRelease(hADX);
   if(hATR != INVALID_HANDLE)      IndicatorRelease(hATR);
   if(hBB != INVALID_HANDLE)       IndicatorRelease(hBB);
   if(hRSI != INVALID_HANDLE)      IndicatorRelease(hRSI);
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateRiskState();

   // Une fermeture qui a echoue est retentee a chaque tick
   if(g_pendingClose > 0)
     {
      if(!PositionSelectByTicket(g_pendingClose)) g_pendingClose = 0;
      else ClosePosition(g_pendingClose);
     }

   datetime barTime = iTime(_Symbol, P.tf, 0);
   if(barTime == 0 || barTime == g_lastBar) return;

   // La barre n'est "consommee" que si les donnees etaient pretes :
   // sinon on reessaie au tick suivant au lieu de rater le signal.
   if(OnNewBar()) g_lastBar = barTime;
  }

bool OnNewBar()
  {
   if(!DataReady()) return false;

   if(P.strat == STRAT_DRIFT && !UpdateSpikeStats()) return false;
   if(!ManageExits()) return false;
   ManageTrailing();
   ShowStatus();

   if(!TradingAllowed() || HasPosition()) return true;

   switch(P.strat)
     {
      case STRAT_DRIFT:     return CheckDriftEntry();
      case STRAT_EMA_CROSS: return CheckEmaEntry();
      case STRAT_BREAKOUT:  return CheckBreakoutEntry();
      case STRAT_MEANREV:   return CheckMeanRevEntry();
     }
   return true;
  }

bool DataReady()
  {
   int need = P.strat == STRAT_DRIFT ? 200 : 3;
   if(Bars(_Symbol, P.tf) < need) return false;
   int handles[7];
   handles[0] = hDriftEMA; handles[1] = hFast; handles[2] = hSlow; handles[3] = hADX;
   handles[4] = hATR; handles[5] = hBB; handles[6] = hRSI;
   for(int i = 0; i < 7; i++)
      if(handles[i] != INVALID_HANDLE && BarsCalculated(handles[i]) <= 0) return false;
   return true;
  }

//+------------------------------------------------------------------+
//| Risque global (partage et persistant)                            |
//+------------------------------------------------------------------+
void UpdateRiskState()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   double peak = GVGet("PEAK", 0);
   if(eq > peak) { peak = eq; GVSet("PEAK", peak); }

   int today = TodayId();
   if((int)GVGet("DAY", 0) != today)
     {
      GVSet("DAY", today);
      GVSet("DAYEQ", eq);
     }
   string sk = SymKey();
   if((int)GVGet(sk + "_TDAY", 0) != today)
     {
      GVSet(sk + "_TDAY", today);
      GVSet(sk + "_TRADES", 0);
     }

   if(GVGet("HALT", 0) <= 0 && peak > 0 && (peak - eq) / peak * 100.0 >= InpMaxDDPercent)
     {
      GVSet("HALT", 1);
      PrintFormat("COUPE-CIRCUIT : drawdown >= %.1f%% depuis le pic. Tous les graphiques s'arretent.",
                  InpMaxDDPercent);
     }
   if(GVGet("HALT", 0) > 0 && SelectMyPosition())
      ClosePosition((ulong)PositionGetInteger(POSITION_TICKET));
  }

//--- Depot ou retrait : on decale le pic et l'equity de debut de journee
//--- du meme montant, pour qu'un retrait ne declenche pas le coupe-circuit.
void HandleBalanceDeal(ulong deal)
  {
   double amount = HistoryDealGetDouble(deal, DEAL_PROFIT);
   if(amount == 0) return;
   string key = GVKey("LASTBAL");
   if(!GlobalVariableCheck(key)) GlobalVariableSet(key, 0);
   double last = GlobalVariableGet(key);
   if((double)deal <= last) return;
   // Mise a jour atomique : un seul graphique traite chaque operation
   if(!GlobalVariableSetOnCondition(key, (double)deal, last)) return;
   if(GVGet("PEAK", 0) > 0)  GVSet("PEAK", MathMax(GVGet("PEAK", 0) + amount, 0.0));
   if(GVGet("DAYEQ", 0) > 0) GVSet("DAYEQ", MathMax(GVGet("DAYEQ", 0) + amount, 0.0));
   PrintFormat("Operation de solde %.2f prise en compte (pic et debut de journee ajustes).", amount);
  }

double DailyLossPct()
  {
   double dayEq = GVGet("DAYEQ", 0);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return dayEq > 0 ? (dayEq - eq) / dayEq * 100.0 : 0.0;
  }

double DrawdownPct()
  {
   double peak = GVGet("PEAK", 0);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   return peak > 0 ? (peak - eq) / peak * 100.0 : 0.0;
  }

bool TradingAllowed()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return false;
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY) return false;
   if(GVGet("HALT", 0) > 0) return false;
   if(DailyLossPct() >= InpDailyLossPercent) return false;
   if((int)GVGet(SymKey() + "_TRADES", 0) >= InpMaxTradesPerDay) return false;
   if(InpMaxSpreadPts > 0 && SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPts) return false;
   return true;
  }

bool DirectionAllowed(int dir)
  {
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_LONGONLY)  return dir > 0;
   if(mode == SYMBOL_TRADE_MODE_SHORTONLY) return dir < 0;
   return true;
  }

//--- Perte (en devise du compte) pour 1 lot sur une distance de prix donnee
double LossPerLot(const string sym, double dist)
  {
   double tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tv <= 0) tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0) return 0.0;
   return dist / ts * tv;
  }

//--- Risque ouvert de toutes les positions du bot (tous indices)
double OpenRiskMoney()
  {
   double total = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      string sym  = PositionGetString(POSITION_SYMBOL);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0)
        {
         long id = PositionGetInteger(POSITION_IDENTIFIER);
         total += GVGet("R_" + IntegerToString(id),
                        AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0);
         continue;
        }
      double dist = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? open - sl : sl - open;
      if(dist > 0) total += LossPerLot(sym, dist) * vol;   // stop deja en gain = 0 risque
     }
   return total;
  }

//+------------------------------------------------------------------+
//| Positions et ordres                                              |
//+------------------------------------------------------------------+
bool SelectMyPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         return true;   // position selectionnee
     }
   return false;
  }

bool HasPosition() { return SelectMyPosition(); }

bool ClosePosition(ulong ticket)
  {
   if(trade.PositionClose(ticket))
     {
      uint rc = trade.ResultRetcode();
      if(rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED)
        {
         if(g_pendingClose == ticket) g_pendingClose = 0;
         return true;
        }
     }
   PrintFormat("Fermeture echouee (%d %s) : nouvel essai au prochain tick.",
               trade.ResultRetcode(), trade.ResultRetcodeDescription());
   g_pendingClose = ticket;
   return false;
  }

//--- Distance minimale imposee par le broker pour un stop ou un objectif
double MinStopDistance()
  {
   long   lvl    = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double spread = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (lvl + 1) * _Point + spread;
  }

bool OpenPosition(int dir, double slDist, double tpDist)
  {
   if(slDist <= 0 || !DirectionAllowed(dir)) return false;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0 || bid <= 0) return false;
   if(InpMaxSpreadSLRatio > 0 && (ask - bid) > InpMaxSpreadSLRatio * slDist)
     {
      Print("Spread trop eleve par rapport au stop : trade ignore.");
      return false;
     }

   // Distances minimales du broker : le stop est elargi si besoin
   // (la taille du lot s'adapte, le risque en argent reste le meme).
   double minDist = MinStopDistance();
   if(slDist < minDist) slDist = minDist;
   if(tpDist > 0 && tpDist < minDist) tpDist = minDist;

   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPerLot = LossPerLot(_Symbol, slDist);
   double step       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vlimit     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(lossPerLot <= 0 || step <= 0) return false;

   double riskMoney = equity * InpRiskPercent * P.riskMult / 100.0;
   double lots = MathFloor(riskMoney / lossPerLot / step + 1e-9) * step;
   if(lots < vmin)
     {
      PrintFormat("Lot minimum (%.2f) trop gros pour risquer %.2f%% : trade ignore.",
                  vmin, InpRiskPercent * P.riskMult);
      return false;
     }
   lots = MathMin(lots, vmax);
   if(vlimit > 0) lots = MathMin(lots, vlimit);
   lots = NormalizeDouble(lots, (int)MathMax(0, MathCeil(-MathLog10(step))));
   double actualRisk = lots * lossPerLot;

   // Plafond de risque total, toutes positions du bot confondues
   if(InpMaxTotalRiskPercent > 0 &&
      (OpenRiskMoney() + actualRisk) / equity * 100.0 > InpMaxTotalRiskPercent)
     {
      Print("Plafond de risque total atteint : trade ignore.");
      return false;
     }

   // Marge disponible
   double price = dir > 0 ? ask : bid;
   double margin = 0.0;
   if(!OrderCalcMargin(dir > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, lots, price, margin) ||
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * InpMaxMarginUse)
     {
      PrintFormat("Marge insuffisante (%.2f requis) : trade ignore.", margin);
      return false;
     }

   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double sl = NormalizeDouble(price - dir * slDist, digits);
   double tp = tpDist > 0 ? NormalizeDouble(price + dir * tpDist, digits) : 0.0;
   string tag = "SXG " + StratName(P.strat);

   bool sent = dir > 0 ? trade.Buy(lots, _Symbol, 0.0, sl, tp, tag)
                       : trade.Sell(lots, _Symbol, 0.0, sl, tp, tag);
   uint rc = trade.ResultRetcode();
   if(!sent || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_DONE_PARTIAL && rc != TRADE_RETCODE_PLACED))
     {
      PrintFormat("Echec ordre : %d %s", rc, trade.ResultRetcodeDescription());
      return false;
     }

   string sk = SymKey();
   GVSet(sk + "_TRADES", GVGet(sk + "_TRADES", 0) + 1);

   // Memorise le risque initial de la position (calcul en R du journal)
   long posId = 0;
   ulong deal = trade.ResultDeal();
   if(deal > 0 && HistoryDealSelect(deal)) posId = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   if(posId == 0 && SelectMyPosition())    posId = PositionGetInteger(POSITION_IDENTIFIER);
   if(posId > 0) GVSet("R_" + IntegerToString(posId), actualRisk);
   return true;
  }

//+------------------------------------------------------------------+
//| Lecture d'indicateurs                                            |
//+------------------------------------------------------------------+
bool Buf(int handle, int buffer, int shift, int count, double &out[])
  {
   ArraySetAsSeries(out, true);
   return CopyBuffer(handle, buffer, shift, count, out) == count;
  }

double ChannelHigh(int startShift, int n)
  {
   int idx = iHighest(_Symbol, P.tf, MODE_HIGH, n, startShift);
   return idx < 0 ? 0.0 : iHigh(_Symbol, P.tf, idx);
  }

double ChannelLow(int startShift, int n)
  {
   int idx = iLowest(_Symbol, P.tf, MODE_LOW, n, startShift);
   return idx < 0 ? 0.0 : iLow(_Symbol, P.tf, idx);
  }

//+------------------------------------------------------------------+
//| Sorties (a chaque nouvelle barre). false = donnees indisponibles |
//+------------------------------------------------------------------+
bool ManageExits()
  {
   if(!SelectMyPosition()) return true;
   ulong    ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   int      dir    = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);

   // Sortie temporelle (DRIFT, retour a la moyenne)
   if(P.maxBars > 0 && TimeCurrent() - opened >= (long)P.maxBars * PeriodSeconds(P.tf))
     {
      ClosePosition(ticket);
      return true;
     }

   double close1 = iClose(_Symbol, P.tf, 1);
   if(close1 <= 0) return false;
   bool exitNow = false;

   if(P.strat == STRAT_EMA_CROSS)
     {
      // La tendance est terminee quand les EMA se croisent en sens inverse
      double f[], s[];
      if(!Buf(hFast, 0, 1, 1, f) || !Buf(hSlow, 0, 1, 1, s)) return false;
      exitNow = dir > 0 ? f[0] < s[0] : f[0] > s[0];
     }
   else if(P.strat == STRAT_BREAKOUT)
     {
      // Sortie sur cassure inverse d'un canal deux fois plus court
      int n = MathMax(P.brkPeriod / 2, 2);
      exitNow = dir > 0 ? close1 < ChannelLow(2, n) : close1 > ChannelHigh(2, n);
     }
   else if(P.strat == STRAT_MEANREV)
     {
      // Objectif = retour a la moyenne mobile de Bollinger
      double mid[];
      if(!Buf(hBB, 0, 1, 1, mid)) return false;
      exitNow = dir > 0 ? close1 >= mid[0] : close1 <= mid[0];
     }

   if(exitNow) ClosePosition(ticket);
   return true;
  }

//--- Trailing stop UNE FOIS PAR BARRE, a partir de la cloture de la barre
//--- precedente (comme le backtester, et sans saturer le serveur d'ordres).
void ManageTrailing()
  {
   if(P.trailATR <= 0 || (P.strat != STRAT_EMA_CROSS && P.strat != STRAT_BREAKOUT)) return;
   if(!SelectMyPosition()) return;
   double atr[];
   if(!Buf(hATR, 0, 1, 1, atr) || atr[0] <= 0) return;
   double close1 = iClose(_Symbol, P.tf, 1);
   if(close1 <= 0) return;

   ulong  ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double dist   = atr[0] * P.trailATR;
   double sl     = PositionGetDouble(POSITION_SL);
   double tp     = PositionGetDouble(POSITION_TP);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double stops  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
     {
      double newSL = NormalizeDouble(MathMin(close1 - dist, bid - stops - _Point), digits);
      if(newSL > sl + _Point && bid - sl > freeze)
         if(!trade.PositionModify(ticket, newSL, tp))
            PrintFormat("Trailing refuse : %d", trade.ResultRetcode());
     }
   else
     {
      double newSL = NormalizeDouble(MathMax(close1 + dist, ask + stops + _Point), digits);
      if((sl == 0 || newSL < sl - _Point) && (sl == 0 || sl - ask > freeze))
         if(!trade.PositionModify(ticket, newSL, tp))
            PrintFormat("Trailing refuse : %d", trade.ResultRetcode());
     }
  }

//+------------------------------------------------------------------+
//| DRIFT (GainX)                                                    |
//+------------------------------------------------------------------+
bool UpdateSpikeStats()
  {
   MqlRates r[];
   ArraySetAsSeries(r, true);
   int n = CopyRates(_Symbol, P.tf, 1, P.lookback, r);
   if(n < 200) { g_driftDir = 0; return false; }

   double bodies[];
   ArrayResize(bodies, n);
   for(int i = 0; i < n; i++) bodies[i] = MathAbs(r[i].close - r[i].open);
   ArraySort(bodies);
   double median = bodies[n / 2];
   if(median <= 0) { g_driftDir = 0; return true; }

   g_spikeThresh = median * P.spikeMult;
   double sumSigned = 0.0, sumAbs = 0.0;
   int cnt = 0;
   g_barsSinceSpike = n;
   for(int i = 0; i < n; i++)   // i = 0 : derniere barre cloturee
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
   g_driftDir   = cnt >= P.minSpikes ? (sumSigned > 0 ? -1 : 1) : 0;   // derive opposee aux pics

   // Securite : l'indice ne se comporte pas comme prevu -> on ne trade pas
   if(P.expectedDrift != 0 && g_driftDir != 0 && g_driftDir != P.expectedDrift)
      g_driftDir = 0;
   return true;
  }

bool CheckDriftEntry()
  {
   if(g_driftDir == 0 || g_avgSpike <= 0 || g_barsSinceSpike < P.cooldown) return true;
   double ema[];
   if(!Buf(hDriftEMA, 0, 1, 2, ema)) return false;
   double close1 = iClose(_Symbol, P.tf, 1);
   bool confirm = g_driftDir > 0 ? (close1 > ema[0] && ema[0] > ema[1])
                                 : (close1 < ema[0] && ema[0] < ema[1]);
   if(confirm) OpenPosition(g_driftDir, g_avgSpike * P.slSpike, g_avgSpike * P.tpSpike);
   return true;
  }

//+------------------------------------------------------------------+
//| Croisement d'EMA                                                 |
//+------------------------------------------------------------------+
bool CheckEmaEntry()
  {
   double f[], s[], adx[], atr[];
   if(!Buf(hFast, 0, 1, 2, f) || !Buf(hSlow, 0, 1, 2, s)) return false;
   if(!Buf(hADX, 0, 1, 1, adx) || !Buf(hATR, 0, 1, 1, atr)) return false;
   if(adx[0] < P.adxMin || atr[0] <= 0) return true;

   int dir = 0;
   if(f[1] <= s[1] && f[0] > s[0]) dir = 1;
   if(f[1] >= s[1] && f[0] < s[0]) dir = -1;
   if(dir != 0) OpenPosition(dir, atr[0] * P.slATR, atr[0] * P.tpATR);
   return true;
  }

//+------------------------------------------------------------------+
//| Cassure de canal (Donchian)                                      |
//+------------------------------------------------------------------+
bool CheckBreakoutEntry()
  {
   double atr[];
   if(!Buf(hATR, 0, 1, 1, atr)) return false;
   if(atr[0] <= 0) return true;
   int n = P.brkPeriod;
   double c1 = iClose(_Symbol, P.tf, 1), c2 = iClose(_Symbol, P.tf, 2);
   if(c1 <= 0 || c2 <= 0) return false;
   // Cassure "fraiche" : la barre 1 casse, la barre 2 ne cassait pas encore
   int dir = 0;
   if(c1 > ChannelHigh(2, n) && c2 <= ChannelHigh(3, n)) dir = 1;
   if(c1 < ChannelLow(2, n)  && c2 >= ChannelLow(3, n))  dir = -1;
   if(dir != 0) OpenPosition(dir, atr[0] * P.slATR, atr[0] * P.tpATR);
   return true;
  }

//+------------------------------------------------------------------+
//| Retour a la moyenne (Bollinger + RSI, seulement sans tendance)   |
//+------------------------------------------------------------------+
bool CheckMeanRevEntry()
  {
   double up[], lo[], rsi[], adx[], atr[];
   if(!Buf(hBB, 1, 1, 1, up) || !Buf(hBB, 2, 1, 1, lo)) return false;
   if(!Buf(hRSI, 0, 1, 1, rsi) || !Buf(hADX, 0, 1, 1, adx) || !Buf(hATR, 0, 1, 1, atr)) return false;
   if(adx[0] > P.adxMaxMR || atr[0] <= 0) return true;

   double c1 = iClose(_Symbol, P.tf, 1);
   int dir = 0;
   if(c1 < lo[0] && rsi[0] < P.rsiLow)          dir = 1;
   if(c1 > up[0] && rsi[0] > 100.0 - P.rsiLow)  dir = -1;
   if(dir != 0) OpenPosition(dir, atr[0] * P.mrSlATR, 0.0);   // sortie sur la moyenne
   return true;
  }

//+------------------------------------------------------------------+
//| Transactions : depots/retraits et journal des trades clos        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;

   if(HistoryDealGetInteger(trans.deal, DEAL_TYPE) == DEAL_TYPE_BALANCE)
     {
      HandleBalanceDeal(trans.deal);
      return;
     }

   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   long     posId    = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   datetime exitTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   double   exitPx   = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double   volume   = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
   double   swap     = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
   double   pnl      = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + swap
                       + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   long     reason   = HistoryDealGetInteger(trans.deal, DEAL_REASON);

   // Retrouve l'entree pour verifier le numero magique et lire le prix d'entree
   if(!HistorySelectByPosition(posId)) return;
   long     magic = -1, dirDeal = -1;
   double   entryPx = 0.0;
   datetime entryTime = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      magic     = HistoryDealGetInteger(d, DEAL_MAGIC);
      dirDeal   = HistoryDealGetInteger(d, DEAL_TYPE);
      entryPx   = HistoryDealGetDouble(d, DEAL_PRICE);
      entryTime = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      pnl      += HistoryDealGetDouble(d, DEAL_COMMISSION);
      break;
     }
   if(magic != InpMagic) return;

   string rKey = "R_" + IntegerToString(posId);
   double risk = GVGet(rKey, 0);
   double r    = risk > 0 ? pnl / risk : 0.0;
   if(!PositionSelectByTicket((ulong)posId)) GVDel(rKey);   // position entierement close

   if(!InpLogTrades) return;
   string why = reason == DEAL_REASON_SL ? "SL" : (reason == DEAL_REASON_TP ? "TP" :
                (reason == DEAL_REASON_SO ? "STOP_OUT" : "SIGNAL"));

   int fh = FileOpen(LOG_FILE, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON |
                     FILE_SHARE_READ | FILE_SHARE_WRITE, ',');
   if(fh == INVALID_HANDLE) return;
   if(FileSize(fh) == 0)
      FileWrite(fh, "exit_time", "symbol", "preset", "strategy", "timeframe", "direction", "volume",
                "entry_time", "entry_price", "exit_price", "profit", "swap", "risk", "r", "exit_reason");
   FileSeek(fh, 0, SEEK_END);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   FileWrite(fh, TimeToString(exitTime, TIME_DATE | TIME_SECONDS), _Symbol, P.name, StratName(P.strat),
             EnumToString(P.tf), dirDeal == DEAL_TYPE_BUY ? "BUY" : "SELL", DoubleToString(volume, 2),
             TimeToString(entryTime, TIME_DATE | TIME_SECONDS), DoubleToString(entryPx, digits),
             DoubleToString(exitPx, digits), DoubleToString(pnl, 2), DoubleToString(swap, 2),
             DoubleToString(risk, 2), DoubleToString(r, 3), why);
   FileClose(fh);
  }

//+------------------------------------------------------------------+
void ShowStatus()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   string s = StringFormat("SyntX Guardian v2.1 | %s | %s | %s %s | risque %.2f%%/trade\n",
                           _Symbol, P.name, StratName(P.strat), EnumToString(P.tf),
                           InpRiskPercent * P.riskMult);
   s += StringFormat("Equity %.2f | DD %.2f%% / %.1f%% | perte jour %.2f%% / %.1f%% | risque ouvert %.2f%% / %.1f%%\n",
                     eq, DrawdownPct(), InpMaxDDPercent, MathMax(DailyLossPct(), 0.0), InpDailyLossPercent,
                     eq > 0 ? OpenRiskMoney() / eq * 100.0 : 0.0, InpMaxTotalRiskPercent);
   s += StringFormat("Trades aujourd'hui (cet indice) %d / %d%s",
                     (int)GVGet(SymKey() + "_TRADES", 0), InpMaxTradesPerDay,
                     GVGet("HALT", 0) > 0 ? " | ARRETE (coupe-circuit)" : "");
   if(P.strat == STRAT_DRIFT)
      s += StringFormat("\nPics: %d | taille moy. %.2f | derive %s | barres depuis pic %d",
                        g_spikeCount, g_avgSpike,
                        g_driftDir > 0 ? "HAUSSE" : (g_driftDir < 0 ? "BAISSE" : "? (pas de trade)"),
                        g_barsSinceSpike);
   Comment(s);
  }
//+------------------------------------------------------------------+
