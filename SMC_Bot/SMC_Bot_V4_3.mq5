﻿//+------------------------------------------------------------------+
//|                                                SMC_Bot_V4_3.mq5  |
//|   Bot SMC multi-symboles - OB 5 étoiles                          |
//|   Sweep de liquidité + déplacement + BOS + FVG + OB vierge        |
//|   Discount/Premium HTF, entrée à profondeur d'OB, confirmation    |
//|   LTF, SL structurel, gestion R-Based, profils par classe d'actif |
//+------------------------------------------------------------------+
#property copyright "SMC Bot V4.3"
#property version   "4.30"
#property description "OB 5 étoiles : sweep de liquidité, déplacement, BOS, FVG, OB vierge, discount/premium HTF."
#property description "Confirmation CHoCH/engulfing LTF, SL au-delà de l'extrême, place jusqu'à la liquidité opposée."
#property description "Exécution robuste : retries, vérification SL/TP après exécution, netting, cotations figées."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| ÉNUMÉRATIONS                                                     |
//+------------------------------------------------------------------+
enum ENUM_ASSET_CLASS
{
   ASSET_FOREX  = 0,
   ASSET_GOLD   = 1,
   ASSET_INDEX  = 2,
   ASSET_CRYPTO = 3
};

enum ENUM_SETUP_STATE
{
   SETUP_IDLE     = 0,   // Aucun OB armé
   SETUP_WATCHING = 1,   // OB armé, on attend que le prix atteigne le niveau d'entrée
   SETUP_IN_ZONE  = 2,   // Prix dans l'OB, on attend la confirmation LTF
   SETUP_IN_TRADE = 3    // Position ouverte
};

//+------------------------------------------------------------------+
//| PARAMÈTRES D'ENTRÉE                                              |
//+------------------------------------------------------------------+
input group "=== Gestion du Risque Global ==="
input double   InpRiskPercent      = 1.0;      // Risque par trade (% du capital)
input double   InpMaxTotalRisk     = 3.0;      // Risque total ouvert maximum (%)
input double   InpMaxDrawdown      = 10.0;     // Drawdown max depuis le plus haut d'equity (%)
input int      InpMaxOpenTrades    = 3;        // Nombre max de trades simultanés
input double   InpMaxDailyLoss     = 3.0;      // Perte journalière max (%) - 0 = désactivé
input bool     InpResetPeakEquity  = false;    // Réinitialiser le plus haut d'equity au démarrage

input group "=== Timeframes (MTF) ==="
input ENUM_TIMEFRAMES InpHTF       = PERIOD_H4;  // Timeframe supérieur (Biais)
input ENUM_TIMEFRAMES InpMTF       = PERIOD_H1;  // Timeframe intermédiaire (OB/FVG)
input ENUM_TIMEFRAMES InpLTF       = PERIOD_M15; // Timeframe inférieur (Confirmation)

input group "=== Structure HTF (Biais + Range) ==="
input int      InpSwingStrength    = 3;          // Force des swings HTF (bougies de chaque côté)
input int      InpHTFLookback      = 200;        // Bougies HTF analysées

input group "=== Filtres OB 5 Étoiles ==="
input int      InpMaxOBAgeBars     = 50;         // Âge maximum de l'OB (bougies MTF)
input int      InpStructureBars    = 10;         // Le déplacement doit casser l'extrême des N bougies avant l'OB (BOS)
input int      InpDisplacementBars = 3;          // Nombre max de bougies pour le déplacement
input double   InpDisplacementATR  = 1.0;        // Corps min. d'une bougie du déplacement (x ATR)
input bool     InpRequireFVG       = true;       // ★ Exiger un FVG dans le déplacement
input bool     InpRequireSweep     = true;       // ★ Exiger une prise de liquidité par l'OB
input int      InpSweepLookback    = 10;         // Bougies avant l'OB dont l'extrême doit être balayé
input bool     InpUsePremiumDiscount = true;     // ★ Acheter en discount / vendre en premium (range HTF)
input double   InpPDLevel          = 0.5;        // Limite discount/premium (0.5 = équilibre)
input bool     InpOBSessionFilter  = false;      // OB formé pendant la session (hors crypto)
input double   InpTouchDepth       = 0.5;        // Profondeur d'entrée dans l'OB (0 = bord, 0.5 = moitié)
input int      InpATRPeriod        = 14;         // Période ATR (MTF)

input group "=== Confirmation LTF ==="
input bool     InpAllowEngulfing   = true;       // Accepter un engulfing dans la zone
input int      InpLTFSwingStrength = 2;          // Force des swings LTF (CHoCH)
input int      InpConfirmMaxBars   = 12;         // Bougies LTF max pour confirmer après le toucher

input group "=== Objectif ==="
input bool     InpUseRoomFilter    = true;       // Exiger de la place jusqu'à la liquidité HTF opposée
input double   InpMinRoomR         = 1.5;        // Place minimale (en R)

input group "=== Symboles à Trader ==="
input bool     InpTradeEURUSD      = true;       // Trader EURUSD
input string   InpNameEURUSD       = "EURUSD";   // Nom broker EURUSD (suffixe éventuel)
input bool     InpTradeXAUUSD      = true;       // Trader XAUUSD
input string   InpNameXAUUSD       = "XAUUSD";   // Nom broker XAUUSD
input bool     InpTradeUS30        = true;       // Trader US30
input string   InpNameUS30         = "US30";     // Nom broker US30
input bool     InpTradeBTCUSD      = true;       // Trader BTCUSD
input string   InpNameBTCUSD       = "BTCUSD";   // Nom broker BTCUSD
input bool     InpTradeGBPUSD      = false;      // Trader GBPUSD
input string   InpNameGBPUSD       = "GBPUSD";   // Nom broker GBPUSD
input bool     InpTradeUSDJPY      = false;      // Trader USDJPY
input string   InpNameUSDJPY       = "USDJPY";   // Nom broker USDJPY
input bool     InpTradeAUDUSD      = false;      // Trader AUDUSD
input string   InpNameAUDUSD       = "AUDUSD";   // Nom broker AUDUSD

input group "=== Profil FOREX ==="
input double   InpFX_RR            = 2.0;        // Ratio R:R
input double   InpFX_SLBufferATR   = 0.25;       // Marge du SL au-delà de l'OB (x ATR)
input double   InpFX_MaxSLATR      = 2.0;        // SL maximum (x ATR) sinon trade refusé
input double   InpFX_MaxSpreadPct  = 10.0;       // Spread max (% de la distance du SL)

input group "=== Profil OR (XAU) ==="
input double   InpGOLD_RR          = 3.0;        // Ratio R:R
input double   InpGOLD_SLBufferATR = 0.35;       // Marge du SL au-delà de l'OB (x ATR)
input double   InpGOLD_MaxSLATR    = 2.5;        // SL maximum (x ATR)
input double   InpGOLD_MaxSpreadPct= 12.0;       // Spread max (% du SL)

input group "=== Profil INDICES (US30, US100...) ==="
input double   InpIDX_RR           = 2.5;        // Ratio R:R
input double   InpIDX_SLBufferATR  = 0.35;       // Marge du SL au-delà de l'OB (x ATR)
input double   InpIDX_MaxSLATR     = 2.5;        // SL maximum (x ATR)
input double   InpIDX_MaxSpreadPct = 12.0;       // Spread max (% du SL)

input group "=== Profil CRYPTO (BTC, ETH) ==="
input double   InpCRY_RR           = 2.0;        // Ratio R:R
input double   InpCRY_SLBufferATR  = 0.40;       // Marge du SL au-delà de l'OB (x ATR)
input double   InpCRY_MaxSLATR     = 3.0;        // SL maximum (x ATR)
input double   InpCRY_MaxSpreadPct = 15.0;       // Spread max (% du SL)
input bool     InpCRY_UseSession   = false;      // Appliquer le filtre de session à la crypto

input group "=== SL minimum (tous profils) ==="
input double   InpMinSLATR         = 0.5;        // SL minimum (x ATR) - évite les SL dans le bruit

input group "=== Notifications ==="
input bool     InpSendPush         = true;       // Envoyer notifications push
input bool     InpVerbose          = true;       // Journal détaillé

input group "=== Gestion R-Based (Trade) ==="
input bool     InpUseBreakEven     = true;       // Break-Even
input double   InpBETriggerR       = 1.0;        // Déclenchement du Break-Even (en R)
input double   InpBEOffsetR        = 0.05;       // SL placé à Entrée + X R (couvre spread/commission)
input bool     InpUseRLock         = true;       // Verrouiller des gains
input double   InpRLockThreshold   = 1.5;        // Seuil de verrouillage (en R)
input double   InpRLockLevelR      = 1.0;        // Gain verrouillé (en R)
input bool     InpUseDynamicTrail  = true;       // Trailing dynamique après le seuil de lock
input double   InpTrailDistanceR   = 0.8;        // Distance du trailing (en R)
input double   InpTrailStepR       = 0.1;        // Pas minimum de déplacement (en R)

input group "=== Filtres de Sécurité ==="
input bool     InpUseSessionFilter = true;       // Activer le filtre de session
input int      InpSessionStartHour = 8;          // Heure début (serveur)
input int      InpSessionEndHour   = 20;         // Heure fin (serveur)
input int      InpFridayLastEntryHour = 18;      // Vendredi : pas d'entrée après cette heure (-1 = désactivé, hors crypto)
input bool     InpUseCorrelationFilter = true;   // Activer filtre de corrélation
input double   InpCorrelationThreshold = 0.7;    // Seuil de corrélation (rendements H1)
input bool     InpUseNewsFilter    = true;       // Activer filtre de news (live uniquement)
input int      InpNewsMinutesBefore= 15;         // Minutes avant la news
input int      InpNewsMinutesAfter = 15;         // Minutes après la news

input group "=== Configuration Technique ==="
input int      InpMagicNumber      = 20241006;   // Magic Number
input int      InpSlippage         = 30;         // Slippage max (points)
input int      InpOrderRetries     = 3;          // Tentatives d'envoi d'ordre (requote, prix changé...)
input int      InpMaxQuoteAgeSec   = 120;        // Cotation plus vieille = marché fermé, pas d'entrée
input int      InpTesterMinTrades  = 100;        // Trades min pour le critère d'optimisation

//+------------------------------------------------------------------+
//| OUTILS                                                           |
//+------------------------------------------------------------------+
void Log(const string msg)
{
   if(InpVerbose) Print("[SMC4.3] ", msg);
}

void Notify(const string msg)
{
   Print("[SMC4.3] ", msg);
   if(InpSendPush && !MQLInfoInteger(MQL_TESTER)) SendNotification("SMC4.3 " + msg);
}

double NormalizePrice(const string sym, double price)
{
   double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   int digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(tick > 0) price = MathRound(price / tick) * tick;
   return NormalizeDouble(price, digits);
}

string PriceStr(const string sym, double price)
{
   return DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
}

int VolumeDigits(double step)
{
   int d = 0;
   double s = step;
   while(d < 8 && MathAbs(s - MathRound(s)) > 1e-9) { s *= 10.0; d++; }
   return d;
}

// Distance minimale imposée par le broker pour SL/TP (stops level / freeze level)
double MinStopDistance(const string sym)
{
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   return MathMax((double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL),
                  (double)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL)) * point;
}

// Vrai une seule fois par nouvelle bougie. 'last' mémorise l'heure de la dernière bougie vue.
bool IsNewBar(const string sym, ENUM_TIMEFRAMES tf, datetime &last)
{
   datetime t = iTime(sym, tf, 0);
   if(t == 0) return false;
   if(t != last) { last = t; return true; }
   return false;
}

bool HourInSession(int hour)
{
   if(InpSessionStartHour <= InpSessionEndHour) return (hour >= InpSessionStartHour && hour < InpSessionEndHour);
   return (hour >= InpSessionStartHour || hour < InpSessionEndHour);
}

//+------------------------------------------------------------------+
//| STRUCTURES                                                       |
//+------------------------------------------------------------------+
struct SSymbolProfile
{
   ENUM_ASSET_CLASS assetClass;
   double           rewardRatio;
   double           slBufferATR;
   double           minSLATR;
   double           maxSLATR;
   double           maxSpreadPct;
   bool             useSession;
};

struct SOrderBlock
{
   bool     valid;
   int      direction;   // 1 = haussier (demande), -1 = baissier (offre)
   double   high;        // zone de l'OB
   double   low;
   double   extreme;     // extrême à protéger (OB ou mèche du sweep) -> base du SL et invalidation
   double   touchLevel;  // niveau d'entrée (profondeur dans l'OB)
   datetime time;        // heure d'ouverture de la bougie OB
   double   fvgHigh;
   double   fvgLow;
   bool     swept;       // l'OB a pris de la liquidité

   void Reset()
   {
      valid = false; direction = 0; high = 0; low = 0; extreme = 0; touchLevel = 0;
      time = 0; fvgHigh = 0; fvgLow = 0; swept = false;
   }
};

//+------------------------------------------------------------------+
//| CLASSE : GESTIONNAIRE DE PROFILS                                 |
//+------------------------------------------------------------------+
class CProfileManager
{
public:
   static ENUM_ASSET_CLASS Classify(const string symbol)
   {
      string s = symbol;
      StringToUpper(s);
      if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return ASSET_GOLD;
      if(StringFind(s, "BTC") >= 0 || StringFind(s, "ETH") >= 0)  return ASSET_CRYPTO;
      // Forex : devise de base ET devise de cotation fiat (évite que USDJPY soit pris pour un indice "DJ")
      if(IsFiat(SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE)) && IsFiat(SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT)) &&
         SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE) != SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT))
         return ASSET_FOREX;
      if(StringFind(s, "US30") >= 0 || StringFind(s, "US100") >= 0 || StringFind(s, "US500") >= 0 ||
         StringFind(s, "NAS") >= 0  || StringFind(s, "SPX") >= 0   || StringFind(s, "DJ30") >= 0  ||
         StringFind(s, "DJI") >= 0  || StringFind(s, "WS30") >= 0  || StringFind(s, "GER") >= 0   ||
         StringFind(s, "DE40") >= 0 || StringFind(s, "DAX") >= 0)
         return ASSET_INDEX;
      ENUM_SYMBOL_CALC_MODE cm = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_CALC_MODE);
      if(cm == SYMBOL_CALC_MODE_FOREX || cm == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) return ASSET_FOREX;
      return ASSET_INDEX;   // CFD inconnu : profil indice (plus prudent que forex)
   }

   static bool IsFiat(const string cur)
   {
      string list = "USD,EUR,GBP,JPY,CHF,AUD,NZD,CAD,SEK,NOK,DKK,SGD,HKD,ZAR,MXN,PLN,TRY,CNH,CZK,HUF";
      return (StringLen(cur) == 3 && StringFind(list, cur) >= 0);
   }

   static void Get(const string symbol, SSymbolProfile &p)
   {
      p.assetClass = Classify(symbol);
      p.minSLATR   = InpMinSLATR;
      p.useSession = true;
      switch(p.assetClass)
      {
         case ASSET_GOLD:
            p.rewardRatio = InpGOLD_RR; p.slBufferATR = InpGOLD_SLBufferATR;
            p.maxSLATR = InpGOLD_MaxSLATR; p.maxSpreadPct = InpGOLD_MaxSpreadPct;
            break;
         case ASSET_INDEX:
            p.rewardRatio = InpIDX_RR; p.slBufferATR = InpIDX_SLBufferATR;
            p.maxSLATR = InpIDX_MaxSLATR; p.maxSpreadPct = InpIDX_MaxSpreadPct;
            break;
         case ASSET_CRYPTO:
            p.rewardRatio = InpCRY_RR; p.slBufferATR = InpCRY_SLBufferATR;
            p.maxSLATR = InpCRY_MaxSLATR; p.maxSpreadPct = InpCRY_MaxSpreadPct;
            p.useSession = InpCRY_UseSession;
            break;
         default:
            p.rewardRatio = InpFX_RR; p.slBufferATR = InpFX_SLBufferATR;
            p.maxSLATR = InpFX_MaxSLATR; p.maxSpreadPct = InpFX_MaxSpreadPct;
            break;
      }
   }

   static string ClassName(ENUM_ASSET_CLASS c)
   {
      switch(c)
      {
         case ASSET_GOLD:   return "OR";
         case ASSET_INDEX:  return "INDICE";
         case ASSET_CRYPTO: return "CRYPTO";
      }
      return "FOREX";
   }
};

//+------------------------------------------------------------------+
//| CLASSE : CONTEXTE PAR SYMBOLE (état + handles)                   |
//+------------------------------------------------------------------+
class CSymbolContext
{
public:
   string           symbol;
   SSymbolProfile   profile;
   int              atrHandle;
   bool             ready;

   int              state;
   int              bias;
   double           htfHigh;          // range HTF courant (dealing range)
   double           htfLow;
   SOrderBlock      ob;
   datetime         touchTime;

   datetime         lastHTFBar;
   datetime         lastMTFBar;
   datetime         lastLTFBar;
   datetime         lastUsedOBTime;   // OB déjà consommé (tradé, invalidé ou expiré)

   datetime         newsCheckTime;
   bool             newsBlocked;

   CSymbolContext()
   {
      symbol = ""; atrHandle = INVALID_HANDLE; ready = false;
      bias = 0; htfHigh = 0; htfLow = 0;
      lastHTFBar = 0; lastMTFBar = 0; lastLTFBar = 0; lastUsedOBTime = 0;
      newsCheckTime = 0; newsBlocked = false;
      ResetSetup();
   }

   void ResetSetup()
   {
      state = SETUP_IDLE;
      ob.Reset();
      touchTime = 0;
   }
};

//+------------------------------------------------------------------+
//| CLASSE : GESTION DU RISQUE                                       |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   long     m_magic;
   double   m_peakEquity;
   double   m_dayStartEquity;
   int      m_dayOfYear;
   string   m_gvPeak;
   string   m_gvDayEq;
   string   m_gvDayId;
   bool     m_persist;      // faux dans le testeur : chaque passe d'optimisation repart de zéro

   long DayId() { return (long)(TimeCurrent() / 86400); }

public:
   void Init(long magic)
   {
      m_magic   = magic;
      m_persist = !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION);
      m_gvPeak  = "SMC42_" + IntegerToString(magic) + "_PEAK";
      m_gvDayEq = "SMC42_" + IntegerToString(magic) + "_DAYEQ";
      m_gvDayId = "SMC42_" + IntegerToString(magic) + "_DAYID";
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);

      m_peakEquity = eq;
      double stored = 0;
      if(m_persist && !InpResetPeakEquity && GlobalVariableGet(m_gvPeak, stored) && stored > eq) m_peakEquity = stored;
      if(m_persist) GlobalVariableSet(m_gvPeak, m_peakEquity);

      // Equity de début de journée : conservée si l'EA redémarre dans la même journée
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      m_dayOfYear      = dt.day_of_year;
      m_dayStartEquity = eq;
      double dayId = 0, dayEq = 0;
      if(m_persist && GlobalVariableGet(m_gvDayId, dayId) && (long)dayId == DayId() &&
         GlobalVariableGet(m_gvDayEq, dayEq) && dayEq > 0)
         m_dayStartEquity = dayEq;
      SaveDay();
   }

   void SaveDay()
   {
      if(!m_persist) return;
      GlobalVariableSet(m_gvDayId, (double)DayId());
      GlobalVariableSet(m_gvDayEq, m_dayStartEquity);
   }

   void Update()
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq <= 0) return;
      if(eq > m_peakEquity) { m_peakEquity = eq; if(m_persist) GlobalVariableSet(m_gvPeak, eq); }
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_year != m_dayOfYear) { m_dayOfYear = dt.day_of_year; m_dayStartEquity = eq; SaveDay(); }
   }

   double DrawdownPct()
   {
      if(m_peakEquity <= 0) return 0;
      return MathMax(0.0, (m_peakEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / m_peakEquity * 100.0);
   }

   double DailyLossPct()
   {
      if(m_dayStartEquity <= 0) return 0;
      return MathMax(0.0, (m_dayStartEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / m_dayStartEquity * 100.0);
   }

   double AdjustedRiskPercent()
   {
      double dd = DrawdownPct();
      if(dd > InpMaxDrawdown)         return InpRiskPercent * 0.25;
      if(dd > InpMaxDrawdown * 0.75)  return InpRiskPercent * 0.50;
      if(dd > InpMaxDrawdown * 0.50)  return InpRiskPercent * 0.75;
      return InpRiskPercent;
   }

   int CountOpenTrades()
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == m_magic) count++;
      }
      return count;
   }

   // Argent réellement en risque : seulement la partie SL du côté perdant.
   double OpenRiskMoney()
   {
      double total   = 0;
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
         string sym  = PositionGetString(POSITION_SYMBOL);
         double vol  = PositionGetDouble(POSITION_VOLUME);
         double open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl   = PositionGetDouble(POSITION_SL);
         if(sl <= 0) { total += balance * InpRiskPercent / 100.0; continue; }
         ENUM_ORDER_TYPE ot = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double pnl = 0;
         if(OrderCalcProfit(ot, sym, vol, open, sl, pnl) && pnl < 0) total += -pnl;
      }
      return total;
   }

   bool CanOpenNewTrade(string &why)
   {
      if(CountOpenTrades() >= InpMaxOpenTrades) { why = "nombre max de trades atteint"; return false; }
      if(InpMaxDailyLoss > 0 && DailyLossPct() >= InpMaxDailyLoss)
      { why = StringFormat("perte journalière %.2f%% >= %.2f%%", DailyLossPct(), InpMaxDailyLoss); return false; }
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(OpenRiskMoney() >= balance * InpMaxTotalRisk / 100.0) { why = "risque total max atteint"; return false; }
      return true;
   }

   double CalculateLots(const string sym, int dir, double entry, double sl, string &why)
   {
      why = "";
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance <= 0) { why = "balance nulle"; return 0; }

      double riskMoney = balance * AdjustedRiskPercent() / 100.0;
      double remaining = balance * InpMaxTotalRisk / 100.0 - OpenRiskMoney();
      if(remaining <= 0) { why = "risque total max atteint"; return 0; }
      riskMoney = MathMin(riskMoney, remaining);

      ENUM_ORDER_TYPE ot = (dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double pnl = 0;
      if(!OrderCalcProfit(ot, sym, 1.0, entry, sl, pnl) || pnl >= 0) { why = "OrderCalcProfit a échoué"; return 0; }
      double lossPerLot = -pnl;

      double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double step   = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      double limit  = SymbolInfoDouble(sym, SYMBOL_VOLUME_LIMIT);   // 0 = pas de limite
      if(step <= 0) step = minLot;
      if(step <= 0 || minLot <= 0) { why = "paramètres de volume invalides"; return 0; }

      double lots = MathFloor(riskMoney / lossPerLot / step + 1e-9) * step;
      if(lots < minLot - 1e-9)
      {
         why = StringFormat("lot calculé %.4f < lot min %.4f (capital trop faible pour ce SL)", lots, minLot);
         return 0;
      }
      if(maxLot > 0) lots = MathMin(lots, maxLot);
      if(limit > 0)  lots = MathMin(lots, limit);
      lots = NormalizeDouble(lots, VolumeDigits(step));

      double margin = 0;
      if(!OrderCalcMargin(ot, sym, lots, entry, margin)) { why = "OrderCalcMargin a échoué"; return 0; }
      if(margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9) { why = "marge libre insuffisante"; return 0; }
      return lots;
   }
};

//+------------------------------------------------------------------+
//| CLASSE : DÉTECTION SMC                                           |
//+------------------------------------------------------------------+
class CSignalEngine
{
public:
   double GetATR(CSymbolContext &c)
   {
      if(c.atrHandle == INVALID_HANDLE) return 0;
      if(BarsCalculated(c.atrHandle) < InpATRPeriod + 2) return 0;
      double buf[];
      if(CopyBuffer(c.atrHandle, 0, 1, 1, buf) != 1) return 0;
      return buf[0];
   }

   // Biais HTF = sens du dernier BOS. Range HTF = du dernier swing opposé à l'extrême atteint depuis.
   // Retourne false si les données ne sont pas prêtes.
   bool HTFBias(const string sym, int &bias, double &rangeHigh, double &rangeLow)
   {
      bias = 0; rangeHigh = 0; rangeLow = 0;
      int s = MathMax(1, InpSwingStrength);
      // CopyRates déclenche lui-même le chargement de l'historique ; on juge sur le nombre reçu
      MqlRates r[];
      ArraySetAsSeries(r, false);                       // r[0] = plus ancienne
      int n = CopyRates(sym, InpHTF, 1, InpHTFLookback, r);
      if(n < 4 * s + 10) return false;

      double lastSH = 0, lastSL = 0;
      int    shIdx = -1, slIdx = -1;
      bool   shBroken = true, slBroken = true;
      for(int i = 2 * s; i < n; i++)
      {
         int k = i - s;                                 // swing confirmé à la bougie i
         bool isSH = true, isSL = true;
         for(int j = 1; j <= s; j++)
         {
            if(r[k].high <= r[k - j].high || r[k].high < r[k + j].high) isSH = false;
            if(r[k].low  >= r[k - j].low  || r[k].low  > r[k + j].low)  isSL = false;
         }
         if(isSH) { lastSH = r[k].high; shIdx = k; shBroken = false; }
         if(isSL) { lastSL = r[k].low;  slIdx = k; slBroken = false; }

         if(!shBroken && r[i].close > lastSH) { bias =  1; shBroken = true; }
         if(!slBroken && r[i].close < lastSL) { bias = -1; slBroken = true; }
      }

      if(bias == 1 && slIdx >= 0)
      {
         rangeLow = lastSL; rangeHigh = lastSL;
         for(int i = slIdx; i < n; i++) rangeHigh = MathMax(rangeHigh, r[i].high);
      }
      else if(bias == -1 && shIdx >= 0)
      {
         rangeHigh = lastSH; rangeLow = lastSH;
         for(int i = shIdx; i < n; i++) rangeLow = MathMin(rangeLow, r[i].low);
      }
      return true;
   }

   // Cherche l'OB 5 étoiles le plus récent dans le sens du biais.
   // Retour : 1 = trouvé, 0 = aucun, -1 = données indisponibles
   int FindFreshOB(CSymbolContext &c, SOrderBlock &out)
   {
      out.Reset();
      int bias = c.bias;
      if(bias == 0) return 0;

      int sweepLB = MathMax(2, InpSweepLookback);
      int need    = InpMaxOBAgeBars + MathMax(InpStructureBars, sweepLB + 1) + InpDisplacementBars + 5;
      double atr = GetATR(c);
      if(atr <= 0) return -1;

      MqlRates r[];
      ArraySetAsSeries(r, false);                       // r[0] = plus ancienne, r[n-1] = dernière clôturée
      int n = CopyRates(c.symbol, InpMTF, 1, need, r);
      if(n < need / 2) return -1;

      double bid  = SymbolInfoDouble(c.symbol, SYMBOL_BID);
      if(bid <= 0) return -1;
      int    last = n - 1;
      int    kMin = MathMax(MathMax(InpStructureBars, sweepLB + 1), 1);
      bool   rangeOk = (c.htfHigh > c.htfLow);
      double eq = rangeOk ? c.htfLow + InpPDLevel * (c.htfHigh - c.htfLow) : 0;
      if(bias == -1 && rangeOk) eq = c.htfHigh - InpPDLevel * (c.htfHigh - c.htfLow);
      bool   sessionCheck = InpOBSessionFilter && c.profile.useSession;

      for(int k = last - 1; k >= kMin; k--)
      {
         int age = last - k + 1;                        // bougies MTF écoulées depuis l'OB
         if(age > InpMaxOBAgeBars) break;
         if(r[k].time == c.lastUsedOBTime) continue;

         if(sessionCheck)
         {
            MqlDateTime dt; TimeToStruct(r[k].time, dt);
            if(!HourInSession(dt.hour)) continue;
         }

         int    dispEnd = -1, fvgEnd = -1;
         double maxBody = 0, fH = 0, fL = 0;
         bool   fvg = false;
         int    dLimit = MathMin(k + InpDisplacementBars, last);

         if(bias == 1)
         {
            // ★ OB haussier = dernière bougie baissière avant l'impulsion
            if(r[k].close >= r[k].open)         continue;
            if(r[k + 1].close <= r[k + 1].open) continue;

            // ★ Sweep : l'OB (ou la bougie précédente) a balayé le plus bas des N bougies d'avant
            double sweepLow = MathMin(r[k].low, r[k - 1].low);
            double preMin   = DBL_MAX;
            for(int p = k - 1 - sweepLB; p <= k - 2; p++) preMin = MathMin(preMin, r[p].low);
            bool swept = (sweepLow < preMin);
            if(InpRequireSweep && !swept) continue;

            // ★ Déplacement + BOS
            double structHigh = r[k].high;
            for(int s = k - InpStructureBars; s < k; s++) structHigh = MathMax(structHigh, r[s].high);
            for(int j = k + 1; j <= dLimit; j++)
            {
               maxBody = MathMax(maxBody, r[j].close - r[j].open);
               if(r[j].close > structHigh) { dispEnd = j; break; }
            }
            if(dispEnd < 0 || maxBody < InpDisplacementATR * atr) continue;

            // ★ FVG de même sens créé par le déplacement
            for(int m = k + 1; m <= MathMin(dispEnd + 1, last - 1); m++)
               if(r[m + 1].low > r[m - 1].high) { fvg = true; fL = r[m - 1].high; fH = r[m + 1].low; fvgEnd = m + 1; break; }
            if(InpRequireFVG && !fvg) continue;

            double zH = r[k].high, zL = r[k].low;
            double touch   = zH - InpTouchDepth * (zH - zL);
            double extreme = swept ? MathMin(zL, sweepLow) : zL;

            // ★ OB vierge : aucune bougie clôturée après le déplacement n'a atteint le niveau d'entrée
            int startCheck = MathMax(dispEnd, fvgEnd) + 1;
            bool fresh = true;
            for(int t = startCheck; t <= last; t++)
               if(r[t].low <= touch) { fresh = false; break; }
            if(!fresh) continue;
            if(bid < extreme) continue;                         // invalidé

            // ★ Discount : le niveau d'entrée doit être sous l'équilibre du range HTF
            if(InpUsePremiumDiscount && rangeOk && touch > eq) continue;

            out.valid = true; out.direction = 1; out.high = zH; out.low = zL;
            out.extreme = extreme; out.touchLevel = touch; out.time = r[k].time;
            out.fvgHigh = fH; out.fvgLow = fL; out.swept = swept;
            return 1;
         }
         else
         {
            // ★ OB baissier = dernière bougie haussière avant l'impulsion
            if(r[k].close <= r[k].open)         continue;
            if(r[k + 1].close >= r[k + 1].open) continue;

            double sweepHigh = MathMax(r[k].high, r[k - 1].high);
            double preMax    = -DBL_MAX;
            for(int p = k - 1 - sweepLB; p <= k - 2; p++) preMax = MathMax(preMax, r[p].high);
            bool swept = (sweepHigh > preMax);
            if(InpRequireSweep && !swept) continue;

            double structLow = r[k].low;
            for(int s = k - InpStructureBars; s < k; s++) structLow = MathMin(structLow, r[s].low);
            for(int j = k + 1; j <= dLimit; j++)
            {
               maxBody = MathMax(maxBody, r[j].open - r[j].close);
               if(r[j].close < structLow) { dispEnd = j; break; }
            }
            if(dispEnd < 0 || maxBody < InpDisplacementATR * atr) continue;

            for(int m = k + 1; m <= MathMin(dispEnd + 1, last - 1); m++)
               if(r[m + 1].high < r[m - 1].low) { fvg = true; fH = r[m - 1].low; fL = r[m + 1].high; fvgEnd = m + 1; break; }
            if(InpRequireFVG && !fvg) continue;

            double zH = r[k].high, zL = r[k].low;
            double touch   = zL + InpTouchDepth * (zH - zL);
            double extreme = swept ? MathMax(zH, sweepHigh) : zH;

            int startCheck = MathMax(dispEnd, fvgEnd) + 1;
            bool fresh = true;
            for(int t = startCheck; t <= last; t++)
               if(r[t].high >= touch) { fresh = false; break; }
            if(!fresh) continue;
            if(bid > extreme) continue;

            // ★ Premium : le niveau d'entrée doit être au-dessus de l'équilibre du range HTF
            if(InpUsePremiumDiscount && rangeOk && touch < eq) continue;

            out.valid = true; out.direction = -1; out.high = zH; out.low = zL;
            out.extreme = extreme; out.touchLevel = touch; out.time = r[k].time;
            out.fvgHigh = fH; out.fvgLow = fL; out.swept = swept;
            return 1;
         }
      }
      return 0;
   }

   // Confirmation sur bougies LTF CLÔTURÉES. Retour : 1 = confirmé, 0 = non, -1 = données indisponibles
   int ConfirmLTF(CSymbolContext &c)
   {
      int s    = MathMax(1, InpLTFSwingStrength);
      int need = InpConfirmMaxBars + 2 * s + 30;
      MqlRates r[];
      ArraySetAsSeries(r, true);                        // r[0] = dernière bougie clôturée
      int n = CopyRates(c.symbol, InpLTF, 1, need, r);
      if(n < 2 * s + 5) return -1;

      int    dir = c.ob.direction;
      double zH  = c.ob.high, zL = c.ob.low;

      // 1) Engulfing au contact de la zone, clôture qui reste du bon côté de l'extrême
      if(InpAllowEngulfing)
      {
         if(dir == 1 && r[0].close > r[0].open && r[1].close < r[1].open &&
            r[0].close > r[1].open && r[0].open <= r[1].close &&
            MathMin(r[0].low, r[1].low) <= zH && r[0].close > c.ob.extreme)
            return 1;
         if(dir == -1 && r[0].close < r[0].open && r[1].close > r[1].open &&
            r[0].close < r[1].open && r[0].open >= r[1].close &&
            MathMax(r[0].high, r[1].high) >= zL && r[0].close < c.ob.extreme)
            return 1;
      }

      // 2) CHoCH : première clôture au-delà du dernier swing LTF formé pendant le retour vers l'OB
      datetime minTime = (datetime)((long)c.touchTime - (long)PeriodSeconds(InpLTF) * 20);
      for(int i = s + 1; i < n - s; i++)
      {
         if(r[i].time < minTime) break;
         bool isSwing = true;
         for(int j = 1; j <= s; j++)
         {
            if(dir == 1) { if(r[i].high < r[i - j].high || r[i].high <= r[i + j].high) { isSwing = false; break; } }
            else         { if(r[i].low  > r[i - j].low  || r[i].low  >= r[i + j].low)  { isSwing = false; break; } }
         }
         if(!isSwing) continue;

         double level = (dir == 1) ? r[i].high : r[i].low;
         bool broken  = (dir == 1) ? (r[0].close > level) : (r[0].close < level);
         if(!broken) return 0;
         for(int q = 1; q < i; q++)
         {
            if(dir == 1  && r[q].close > level) return 0;
            if(dir == -1 && r[q].close < level) return 0;
         }
         return 1;
      }
      return 0;
   }
};

//+------------------------------------------------------------------+
//| CLASSE : BOT                                                     |
//+------------------------------------------------------------------+
class CSmcBot
{
private:
   CTrade          m_trade;
   CRiskManager    m_risk;
   CSignalEngine   m_engine;
   CSymbolContext  m_ctx[];
   int             m_count;
   string          m_gvPrefix;
   datetime        m_lastCleanup;
   ulong           m_failTicket[];     // anti-spam des modifications refusées
   datetime        m_failTime[];

public:
   CSmcBot() { m_count = 0; m_lastCleanup = 0; m_gvPrefix = ""; }

   bool Init()
   {
      m_count = 0;
      if(!ValidateInputs()) return false;

      m_trade.SetExpertMagicNumber(InpMagicNumber);
      m_trade.SetDeviationInPoints(InpSlippage);
      m_trade.SetAsyncMode(false);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
      m_risk.Init(InpMagicNumber);
      m_gvPrefix    = "SMC42_" + IntegerToString(InpMagicNumber) + "_R_";
      // Testeur : les identifiants de position recommencent à chaque passe, on purge les anciens 1R
      if(MQLInfoInteger(MQL_TESTER)) GlobalVariablesDeleteAll(m_gvPrefix);
      m_lastCleanup = 0;
      ArrayResize(m_failTicket, 0); ArrayResize(m_failTime, 0);

      m_count = 0;
      ArrayResize(m_ctx, 0);
      AddSymbol(InpTradeEURUSD, InpNameEURUSD);
      AddSymbol(InpTradeXAUUSD, InpNameXAUUSD);
      AddSymbol(InpTradeUS30,   InpNameUS30);
      AddSymbol(InpTradeBTCUSD, InpNameBTCUSD);
      AddSymbol(InpTradeGBPUSD, InpNameGBPUSD);
      AddSymbol(InpTradeUSDJPY, InpNameUSDJPY);
      AddSymbol(InpTradeAUDUSD, InpNameAUDUSD);

      if(m_count == 0) { Print("[SMC4.3] Aucun symbole valide : vérifie les noms (suffixes broker)"); return false; }

      ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      Print("[SMC4.3] Compte ", (mm == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "hedging" : "netting"),
            " - ", m_count, " symbole(s) actif(s)");
      return true;
   }

   void Deinit()
   {
      for(int i = 0; i < m_count; i++)
         if(m_ctx[i].atrHandle != INVALID_HANDLE) { IndicatorRelease(m_ctx[i].atrHandle); m_ctx[i].atrHandle = INVALID_HANDLE; }
   }

   void Process()
   {
      m_risk.Update();
      ManagePositions();                         // toujours, même hors session
      for(int i = 0; i < m_count; i++) ProcessSymbol(m_ctx[i]);

      if(TimeCurrent() - m_lastCleanup > 300) { CleanupGlobals(); m_lastCleanup = TimeCurrent(); }
   }

   // Rapport par symbole (PF, winrate) : affiché à l'arrêt de l'EA / fin du backtest
   void PrintReport()
   {
      if(m_count == 0 || !HistorySelect(0, TimeCurrent())) return;
      double gp[], gl[]; int cnt[], wins[];
      ArrayResize(gp, m_count); ArrayResize(gl, m_count); ArrayResize(cnt, m_count); ArrayResize(wins, m_count);
      ArrayInitialize(gp, 0); ArrayInitialize(gl, 0); ArrayInitialize(cnt, 0); ArrayInitialize(wins, 0);

      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0 || HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagicNumber) continue;
         int idx = FindContext(HistoryDealGetString(d, DEAL_SYMBOL));
         if(idx < 0) continue;
         ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
         double comm = HistoryDealGetDouble(d, DEAL_COMMISSION);
         if(e == DEAL_ENTRY_IN) { gl[idx] += MathMax(0.0, -comm); continue; }
         double pnl = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + comm;
         cnt[idx]++;
         if(pnl >= 0) { gp[idx] += pnl; wins[idx]++; } else gl[idx] += -pnl;
      }

      Print("[SMC4.3] ===== Rapport par symbole =====");
      for(int i = 0; i < m_count; i++)
      {
         double pf = (gl[i] > 0) ? gp[i] / gl[i] : (gp[i] > 0 ? 999.0 : 0.0);
         double wr = (cnt[i] > 0) ? 100.0 * wins[i] / cnt[i] : 0.0;
         string verdict = (cnt[i] < 30) ? "échantillon trop petit" : (pf >= 1.5 ? "OK" : "< 1.5");
         Print(StringFormat("[SMC4.3] %-10s trades=%d  winrate=%.1f%%  PF=%.2f  net=%.2f  %s",
               m_ctx[i].symbol, cnt[i], wr, pf, gp[i] - gl[i], verdict));
      }
   }

private:
   bool Fail(const string msg) { Print("[SMC4.3] Paramètre invalide : ", msg); return false; }

   bool ValidateInputs()
   {
      if(PeriodSeconds(InpHTF) <= PeriodSeconds(InpMTF) || PeriodSeconds(InpMTF) <= PeriodSeconds(InpLTF)) return Fail("il faut HTF > MTF > LTF");
      if(InpRiskPercent <= 0 || InpRiskPercent > InpMaxTotalRisk)        return Fail("0 < risque par trade <= risque total");
      if(InpMaxDrawdown <= 0 || InpMaxDailyLoss < 0)                     return Fail("drawdown / perte journalière");
      if(InpMaxOpenTrades <= 0 || InpMaxOBAgeBars <= 0 || InpConfirmMaxBars <= 0) return Fail("compteurs <= 0");
      if(InpStructureBars < 1 || InpDisplacementBars < 1 || InpSweepLookback < 2) return Fail("structure / déplacement / sweep");
      if(InpSwingStrength < 1 || InpLTFSwingStrength < 1 || InpHTFLookback < 50)  return Fail("swings / lookback HTF");
      if(InpATRPeriod < 2 || InpDisplacementATR < 0)                     return Fail("ATR");
      if(InpTouchDepth < 0 || InpTouchDepth > 1)                         return Fail("profondeur d'entrée entre 0 et 1");
      if(InpPDLevel <= 0 || InpPDLevel >= 1)                             return Fail("niveau discount/premium entre 0 et 1");
      if(InpFX_RR <= 0 || InpGOLD_RR <= 0 || InpIDX_RR <= 0 || InpCRY_RR <= 0) return Fail("RR <= 0");
      if(InpMinSLATR <= 0)                                               return Fail("SL minimum");
      if(InpFX_MaxSLATR <= InpMinSLATR || InpGOLD_MaxSLATR <= InpMinSLATR ||
         InpIDX_MaxSLATR <= InpMinSLATR || InpCRY_MaxSLATR <= InpMinSLATR) return Fail("SL max doit être > SL min");
      if(InpSessionStartHour < 0 || InpSessionStartHour > 23 || InpSessionEndHour < 0 || InpSessionEndHour > 24) return Fail("heures de session");
      if(InpUseSessionFilter && InpSessionStartHour == InpSessionEndHour) return Fail("début et fin de session identiques (aucune heure autorisée)");
      if(InpFridayLastEntryHour > 24)                                    return Fail("heure limite du vendredi");
      if(InpCorrelationThreshold <= 0 || InpCorrelationThreshold > 1)    return Fail("seuil de corrélation entre 0 et 1");
      if(InpBETriggerR <= 0 || InpRLockThreshold <= 0 || InpTrailDistanceR <= 0 || InpTrailStepR < 0) return Fail("gestion R");
      if(InpUseRLock && InpRLockLevelR >= InpRLockThreshold)             return Fail("gain verrouillé doit être < seuil de lock");
      if(InpBEOffsetR >= InpBETriggerR)                                  return Fail("offset BE doit être < déclenchement BE");
      if(InpOrderRetries < 1 || InpMaxQuoteAgeSec < 10)                  return Fail("retries / âge de cotation");
      if(InpSlippage < 0 || InpNewsMinutesBefore < 0 || InpNewsMinutesAfter < 0) return Fail("slippage / minutes de news négatifs");
      if(InpMaxTotalRisk > 100 || InpMaxDrawdown > 100 || InpMaxDailyLoss > 100)  return Fail("pourcentage > 100");
      if(InpUseRoomFilter && InpMinRoomR <= 0)                           return Fail("place minimale (R) <= 0");
      if(InpFX_SLBufferATR < 0 || InpGOLD_SLBufferATR < 0 || InpIDX_SLBufferATR < 0 || InpCRY_SLBufferATR < 0) return Fail("marge SL négative");
      if(InpFX_MaxSpreadPct <= 0 || InpGOLD_MaxSpreadPct <= 0 || InpIDX_MaxSpreadPct <= 0 || InpCRY_MaxSpreadPct <= 0) return Fail("spread max <= 0");
      return true;
   }

   void AddSymbol(bool enabled, const string name)
   {
      if(!enabled) return;
      string sym = name;
      StringTrimLeft(sym); StringTrimRight(sym);
      if(sym == "") return;
      if(FindContext(sym) >= 0) { Print("[SMC4.3] ", sym, " déjà ajouté, doublon ignoré"); return; }
      if(!SymbolSelect(sym, true)) { Print("[SMC4.3] Symbole introuvable : ", sym, " (vérifie le nom/suffixe du broker)"); return; }

      int handle = iATR(sym, InpMTF, InpATRPeriod);
      if(handle == INVALID_HANDLE) { Print("[SMC4.3] Impossible de créer l'ATR pour ", sym); return; }

      int idx = m_count;
      ArrayResize(m_ctx, m_count + 1);
      m_count++;
      m_ctx[idx].symbol    = sym;
      m_ctx[idx].atrHandle = handle;
      CProfileManager::Get(sym, m_ctx[idx].profile);
      m_ctx[idx].ready     = true;

      // Préchargement de l'historique (déclenche le téléchargement si nécessaire)
      MqlRates tmp[];
      CopyRates(sym, InpHTF, 0, InpHTFLookback, tmp);
      CopyRates(sym, InpMTF, 0, InpMaxOBAgeBars + 50, tmp);
      CopyRates(sym, InpLTF, 0, 100, tmp);

      Print(StringFormat("[SMC4.3] %s ajouté - profil %s : RR=%.1f, marge SL=%.2f ATR, SL %.1f-%.1f ATR, spread max=%.0f%% du SL, session=%s",
            sym, CProfileManager::ClassName(m_ctx[idx].profile.assetClass), m_ctx[idx].profile.rewardRatio,
            m_ctx[idx].profile.slBufferATR, m_ctx[idx].profile.minSLATR, m_ctx[idx].profile.maxSLATR,
            m_ctx[idx].profile.maxSpreadPct, (m_ctx[idx].profile.useSession ? "oui" : "non")));
   }

   int FindContext(const string sym)
   {
      for(int i = 0; i < m_count; i++) if(m_ctx[i].symbol == sym) return i;
      return -1;
   }

   bool HasOpenPosition(const string sym)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == sym) return true;
      }
      return false;
   }

   //--- Machine à états par symbole -------------------------------------
   void ProcessSymbol(CSymbolContext &c)
   {
      if(!c.ready) return;
      string sym = c.symbol;

      if(HasOpenPosition(sym)) { c.state = SETUP_IN_TRADE; return; }
      if(c.state == SETUP_IN_TRADE) c.ResetSetup();

      // 1) Biais + range HTF, recalculés à chaque nouvelle bougie HTF
      if(IsNewBar(sym, InpHTF, c.lastHTFBar))
      {
         int nb = 0; double rh = 0, rl = 0;
         if(!m_engine.HTFBias(sym, nb, rh, rl)) { c.lastHTFBar = 0; return; }
         if(nb != c.bias)
         {
            Log(StringFormat("%s : biais HTF %d -> %d", sym, c.bias, nb));
            if(c.state != SETUP_IDLE && c.ob.direction != nb) c.ResetSetup();
         }
         c.bias = nb; c.htfHigh = rh; c.htfLow = rl;
         c.lastMTFBar = 0;                                   // nouveau contexte : on rescanne les OB
      }
      if(c.bias == 0) return;

      // 2) Recherche d'OB à chaque nouvelle bougie MTF (sauf si le prix est déjà dans la zone)
      if(IsNewBar(sym, InpMTF, c.lastMTFBar) && c.state != SETUP_IN_ZONE)
      {
         SOrderBlock found;
         int res = m_engine.FindFreshOB(c, found);
         if(res < 0) { c.lastMTFBar = 0; return; }
         if(res == 1)
         {
            if(!c.ob.valid || found.time != c.ob.time)
               Log(StringFormat("%s : OB %s armé [%s - %s] du %s, entrée à %s, invalidation %s%s",
                   sym, found.direction == 1 ? "haussier" : "baissier",
                   PriceStr(sym, found.low), PriceStr(sym, found.high), TimeToString(found.time),
                   PriceStr(sym, found.touchLevel), PriceStr(sym, found.extreme), found.swept ? " (sweep)" : ""));
            c.ob    = found;
            c.state = SETUP_WATCHING;
         }
         else c.ResetSetup();
      }

      // 3) Attente du retour du prix au niveau d'entrée
      if(c.state == SETUP_WATCHING)
      {
         int age = iBarShift(sym, InpMTF, c.ob.time);
         if(age < 0 || age > InpMaxOBAgeBars) { c.ResetSetup(); return; }

         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         if(bid <= 0) return;
         double lLow = iLow(sym, InpLTF, 0), lHigh = iHigh(sym, InpLTF, 0);
         if(lLow  <= 0) lLow  = bid;
         if(lHigh <= 0) lHigh = bid;

         bool touched = (c.ob.direction == 1) ? (MathMin(bid, lLow) <= c.ob.touchLevel)
                                              : (MathMax(bid, lHigh) >= c.ob.touchLevel);
         if(!touched) return;

         c.state      = SETUP_IN_ZONE;
         c.touchTime  = TimeCurrent();
         c.lastLTFBar = iTime(sym, InpLTF, 0);
         Log(StringFormat("%s : niveau d'entrée atteint, attente de confirmation %s", sym, EnumToString(InpLTF)));
      }

      // 4) Confirmation LTF puis entrée
      if(c.state == SETUP_IN_ZONE)
      {
         if(TimeCurrent() - c.touchTime > (long)InpConfirmMaxBars * PeriodSeconds(InpLTF))
         {
            Log(sym + " : pas de confirmation à temps, OB abandonné");
            c.lastUsedOBTime = c.ob.time; c.ResetSetup(); return;
         }
         if(!IsNewBar(sym, InpLTF, c.lastLTFBar)) return;

         double lastClose = iClose(sym, InpLTF, 1);
         if(lastClose > 0 && ((c.ob.direction == 1 && lastClose < c.ob.extreme) || (c.ob.direction == -1 && lastClose > c.ob.extreme)))
         {
            Log(sym + " : clôture LTF au-delà de l'extrême, setup invalidé");
            c.lastUsedOBTime = c.ob.time; c.ResetSetup(); return;
         }

         int conf = m_engine.ConfirmLTF(c);
         if(conf < 0) { c.lastLTFBar = 0; return; }          // données pas prêtes : on réessaiera
         if(conf == 0) return;
         Log(sym + " : confirmation LTF obtenue");

         string why;
         if(!EntryAllowed(c, why)) { Log(sym + " : entrée bloquée - " + why); return; }

         c.lastUsedOBTime = c.ob.time;
         if(TryEnter(c)) c.state = SETUP_IN_TRADE;
         else            c.ResetSetup();
      }
   }

   //--- Filtres -----------------------------------------------------------
   bool EntryAllowed(CSymbolContext &c, string &why)
   {
      string sym = c.symbol;
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) { why = "trading automatique désactivé"; return false; }
      if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) { why = "trading interdit sur ce compte"; return false; }

      ENUM_SYMBOL_TRADE_MODE tm = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
      if(tm == SYMBOL_TRADE_MODE_DISABLED || tm == SYMBOL_TRADE_MODE_CLOSEONLY) { why = "symbole non négociable"; return false; }
      if(c.ob.direction == 1  && tm == SYMBOL_TRADE_MODE_SHORTONLY) { why = "achats interdits"; return false; }
      if(c.ob.direction == -1 && tm == SYMBOL_TRADE_MODE_LONGONLY)  { why = "ventes interdites"; return false; }

      MqlTick tk;
      if(!SymbolInfoTick(sym, tk) || tk.bid <= 0 || tk.ask <= 0 || tk.ask < tk.bid) { why = "cotation invalide"; return false; }
      if(TimeCurrent() - tk.time > InpMaxQuoteAgeSec) { why = "cotation figée (marché fermé ?)"; return false; }

      // Compte netting : une position existante (autre EA / manuelle) fusionnerait avec la nôtre
      ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && PositionSelect(sym)) { why = "compte netting : position déjà ouverte sur ce symbole"; return false; }

      if(!IsSessionOpen(c))                      { why = "hors session"; return false; }
      if(IsFridayCutoff(c))                      { why = "vendredi après l'heure limite"; return false; }
      if(!m_risk.CanOpenNewTrade(why))           return false;
      if(IsNewsTime(c))                          { why = "news à fort impact"; return false; }
      if(IsCorrelated(sym, c.ob.direction))      { why = "corrélé à une position ouverte"; return false; }
      return true;
   }

   bool IsSessionOpen(CSymbolContext &c)
   {
      if(!InpUseSessionFilter || !c.profile.useSession) return true;
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      return HourInSession(dt.hour);
   }

   bool IsFridayCutoff(CSymbolContext &c)
   {
      if(InpFridayLastEntryHour < 0 || c.profile.assetClass == ASSET_CRYPTO) return false;
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      return (dt.day_of_week == 5 && dt.hour >= InpFridayLastEntryHour);
   }

   bool IsNewsTime(CSymbolContext &c)
   {
      if(!InpUseNewsFilter) return false;
      if(MQLInfoInteger(MQL_TESTER)) return false;    // calendrier indisponible dans le testeur

      datetime now = TimeTradeServer();
      if(now - c.newsCheckTime < 60) return c.newsBlocked;
      c.newsCheckTime = now;
      c.newsBlocked   = false;

      string curs[2];
      curs[0] = SymbolInfoString(c.symbol, SYMBOL_CURRENCY_BASE);
      curs[1] = SymbolInfoString(c.symbol, SYMBOL_CURRENCY_PROFIT);
      datetime from = (datetime)((long)now - (long)InpNewsMinutesAfter * 60);
      datetime to   = (datetime)((long)now + (long)InpNewsMinutesBefore * 60);

      for(int k = 0; k < 2; k++)
      {
         if(curs[k] == "" || (k == 1 && curs[1] == curs[0])) continue;
         MqlCalendarValue vals[];
         ResetLastError();
         CalendarValueHistory(vals, from, to, NULL, curs[k]);
         int got = ArraySize(vals);                  // indépendant du type de retour de la fonction
         if(got == 0 && GetLastError() != 0) { Log(StringFormat("%s : calendrier indisponible (erreur %d)", c.symbol, GetLastError())); continue; }
         for(int i = 0; i < got; i++)
         {
            MqlCalendarEvent ev;
            if(CalendarEventById(vals[i].event_id, ev) && ev.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               Log(StringFormat("%s : news %s (%s) à %s", c.symbol, ev.name, curs[k], TimeToString(vals[i].time)));
               c.newsBlocked = true;
               return true;
            }
         }
      }
      return false;
   }

   bool IsCorrelated(const string sym, int dir)
   {
      if(!InpUseCorrelationFilter) return false;

      string syms[]; int dirs[]; int n = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         string ps = PositionGetString(POSITION_SYMBOL);
         if(ps == sym) continue;
         ArrayResize(syms, n + 1); ArrayResize(dirs, n + 1);
         syms[n] = ps;
         dirs[n] = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         n++;
      }

      for(int i = 0; i < n; i++)
      {
         double corr = Correlation(sym, syms[i], PERIOD_H1, 100);
         if((dir == dirs[i] && corr >= InpCorrelationThreshold) || (dir != dirs[i] && corr <= -InpCorrelationThreshold))
         {
            Log(StringFormat("%s : corrélation %.2f avec %s", sym, corr, syms[i]));
            return true;
         }
      }
      return false;
   }

   // Corrélation de Pearson des rendements logarithmiques, bougies alignées par heure
   double Correlation(const string a, const string b, ENUM_TIMEFRAMES tf, int bars)
   {
      MqlRates ra[];
      ArraySetAsSeries(ra, false);
      int got = CopyRates(a, tf, 1, bars + 1, ra);
      if(got < 30) return 0;

      double x[], y[]; int m = 0;
      ArrayResize(x, got); ArrayResize(y, got);
      for(int i = 1; i < got; i++)
      {
         int sb  = iBarShift(b, tf, ra[i].time, true);
         int sbp = iBarShift(b, tf, ra[i - 1].time, true);
         if(sb < 0 || sbp < 0) continue;
         double cb = iClose(b, tf, sb), cbp = iClose(b, tf, sbp);
         if(cb <= 0 || cbp <= 0 || ra[i].close <= 0 || ra[i - 1].close <= 0) continue;
         x[m] = MathLog(ra[i].close / ra[i - 1].close);
         y[m] = MathLog(cb / cbp);
         m++;
      }
      if(m < 30) return 0;

      double mx = 0, my = 0;
      for(int i = 0; i < m; i++) { mx += x[i]; my += y[i]; }
      mx /= m; my /= m;
      double cov = 0, vx = 0, vy = 0;
      for(int i = 0; i < m; i++) { cov += (x[i] - mx) * (y[i] - my); vx += (x[i] - mx) * (x[i] - mx); vy += (y[i] - my) * (y[i] - my); }
      if(vx <= 0 || vy <= 0) return 0;
      return cov / MathSqrt(vx * vy);
   }

   //--- Exécution ---------------------------------------------------------
   // Calcule entrée / SL / TP / lots sur la cotation actuelle. False + raison si le trade n'est pas valable.
   bool ComputeLevels(CSymbolContext &c, double &entry, double &sl, double &tp, double &lots, string &why)
   {
      string sym = c.symbol;
      int    dir = c.ob.direction;
      double atr = m_engine.GetATR(c);
      if(atr <= 0) { why = "ATR indisponible"; return false; }

      MqlTick tk;
      if(!SymbolInfoTick(sym, tk) || tk.bid <= 0 || tk.ask <= 0 || tk.ask < tk.bid) { why = "cotation invalide"; return false; }
      double spread = tk.ask - tk.bid;
      entry = (dir == 1) ? tk.ask : tk.bid;

      // SL au-delà de l'extrême (OB ou mèche du sweep) + marge ATR (+ spread pour les ventes)
      double buffer = c.profile.slBufferATR * atr;
      sl = (dir == 1) ? c.ob.extreme - buffer : c.ob.extreme + buffer + spread;
      double risk = (dir == 1) ? entry - sl : sl - entry;
      if(risk <= 0) { why = "prix déjà au-delà du SL structurel"; return false; }

      double minRisk = c.profile.minSLATR * atr;
      if(risk < minRisk) { risk = minRisk; sl = (dir == 1) ? entry - risk : entry + risk; }
      if(risk > c.profile.maxSLATR * atr)
      { why = StringFormat("SL trop large (%.2f ATR > %.2f)", risk / atr, c.profile.maxSLATR); return false; }
      if(spread > risk * c.profile.maxSpreadPct / 100.0)
      { why = StringFormat("spread trop élevé (%.1f%% du SL)", 100.0 * spread / risk); return false; }
      if(risk <= MinStopDistance(sym) + spread) { why = "SL sous la distance minimale du broker"; return false; }

      // Place jusqu'à la liquidité HTF opposée (haut du range pour un achat, bas pour une vente)
      if(InpUseRoomFilter && c.htfHigh > c.htfLow)
      {
         double room = (dir == 1) ? c.htfHigh - entry : entry - c.htfLow;
         if(room < InpMinRoomR * risk) { why = StringFormat("pas assez de place jusqu'à la liquidité (%.2fR)", room / risk); return false; }
      }

      tp = (dir == 1) ? entry + risk * c.profile.rewardRatio : entry - risk * c.profile.rewardRatio;
      sl = NormalizePrice(sym, sl);
      tp = NormalizePrice(sym, tp);

      lots = m_risk.CalculateLots(sym, dir, entry, sl, why);
      return (lots > 0);
   }

   bool IsRetryable(uint rc)
   {
      return (rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED || rc == TRADE_RETCODE_PRICE_OFF ||
              rc == TRADE_RETCODE_TIMEOUT || rc == TRADE_RETCODE_CONNECTION || rc == TRADE_RETCODE_TOO_MANY_REQUESTS);
   }

   bool TryEnter(CSymbolContext &c)
   {
      string sym = c.symbol;
      int    dir = c.ob.direction;
      m_trade.SetTypeFillingBySymbol(sym);
      string comment = StringFormat("SMC4.3 %s RR%.1f", dir == 1 ? "BUY" : "SELL", c.profile.rewardRatio);

      for(int attempt = 1; attempt <= InpOrderRetries; attempt++)
      {
         double entry = 0, sl = 0, tp = 0, lots = 0;
         string why;
         if(!ComputeLevels(c, entry, sl, tp, lots, why)) { Log(sym + " : trade refusé - " + why); return false; }

         bool ok = (dir == 1) ? m_trade.Buy(lots, sym, 0.0, sl, tp, comment) : m_trade.Sell(lots, sym, 0.0, sl, tp, comment);
         uint rc = m_trade.ResultRetcode();
         if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED))
         {
            EnsureProtection(sym, sl, c.profile.rewardRatio);
            if(!HasOpenPosition(sym)) return false;      // fermée par EnsureProtection
            Notify(StringFormat("%s %s %.2f lots @ %s | SL %s | TP %s | OB %s%s",
                   dir == 1 ? "BUY" : "SELL", sym, lots, PriceStr(sym, m_trade.ResultPrice()),
                   PriceStr(sym, sl), PriceStr(sym, tp),
                   dir == 1 ? "haussier" : "baissier", c.ob.swept ? " + sweep" : ""));
            return true;
         }
         if(!IsRetryable(rc) || attempt == InpOrderRetries)
         {
            Notify(StringFormat("Échec ordre %s %s : %u %s", dir == 1 ? "BUY" : "SELL", sym, rc, m_trade.ResultRetcodeDescription()));
            return false;
         }
         Log(StringFormat("%s : %s, nouvelle tentative %d/%d", sym, m_trade.ResultRetcodeDescription(), attempt + 1, InpOrderRetries));
         if(!MQLInfoInteger(MQL_TESTER)) Sleep(300);
      }
      return false;
   }

   // Après exécution : vérifie que le SL est posé, recale le TP sur le prix réellement obtenu (slippage),
   // mémorise le risque initial. Ferme la position si aucun SL ne peut être posé.
   void EnsureProtection(const string sym, double plannedSL, double rr)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber || PositionGetString(POSITION_SYMBOL) != sym) continue;

         bool   isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double open  = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         double tp    = PositionGetDouble(POSITION_TP);
         long   id    = PositionGetInteger(POSITION_IDENTIFIER);

         double wantSL = (sl > 0) ? sl : plannedSL;
         double risk   = isBuy ? open - wantSL : wantSL - open;
         if(risk <= 0)
         {
            m_trade.PositionClose(t);
            Notify(sym + " : exécution au-delà du SL prévu, position fermée");
            continue;
         }
         double wantTP = NormalizePrice(sym, isBuy ? open + rr * risk : open - rr * risk);
         double tick   = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
         if(tick <= 0) tick = SymbolInfoDouble(sym, SYMBOL_POINT);

         if(sl <= 0 || MathAbs(tp - wantTP) > 2 * tick)
         {
            if(!m_trade.PositionModify(t, wantSL, wantTP) && sl <= 0)
            {
               m_trade.PositionClose(t);
               Notify(StringFormat("%s : impossible de poser le SL (%u), position fermée", sym, m_trade.ResultRetcode()));
               continue;
            }
         }
         GlobalVariableSet(m_gvPrefix + IntegerToString(id), risk);
      }
   }

   //--- Gestion R-Based -----------------------------------------------------
   double GetInitialRisk(const string sym, long id, bool isBuy, double open, double sl, double tp)
   {
      string name = m_gvPrefix + IntegerToString(id);
      double v = 0;
      if(GlobalVariableGet(name, v) && v > 0) return v;

      int idx = FindContext(sym);                       // repli : TP = entrée ± RR x R
      if(tp > 0 && idx >= 0 && m_ctx[idx].profile.rewardRatio > 0)
      { v = MathAbs(tp - open) / m_ctx[idx].profile.rewardRatio; GlobalVariableSet(name, v); return v; }
      if(sl > 0 && ((isBuy && sl < open) || (!isBuy && sl > open)))
      { v = MathAbs(open - sl); GlobalVariableSet(name, v); return v; }
      return 0;
   }

   double MoreProtective(bool isBuy, double current, double candidate)
   {
      if(current <= 0) return candidate;
      return isBuy ? MathMax(current, candidate) : MathMin(current, candidate);
   }

   bool ModifyThrottled(ulong ticket)
   {
      for(int i = 0; i < ArraySize(m_failTicket); i++)
         if(m_failTicket[i] == ticket && TimeCurrent() - m_failTime[i] < 30) return true;
      return false;
   }

   void RecordModifyFail(ulong ticket)
   {
      int n = ArraySize(m_failTicket);
      for(int i = 0; i < n; i++) if(m_failTicket[i] == ticket) { m_failTime[i] = TimeCurrent(); return; }
      if(n >= 50) { ArrayResize(m_failTicket, 0); ArrayResize(m_failTime, 0); n = 0; }
      ArrayResize(m_failTicket, n + 1); ArrayResize(m_failTime, n + 1);
      m_failTicket[n] = ticket; m_failTime[n] = TimeCurrent();
   }

   void ManagePositions()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(ModifyThrottled(ticket)) continue;

         string sym   = PositionGetString(POSITION_SYMBOL);
         bool   isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double open  = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         double tp    = PositionGetDouble(POSITION_TP);
         long   id    = PositionGetInteger(POSITION_IDENTIFIER);

         double R0 = GetInitialRisk(sym, id, isBuy, open, sl, tp);
         if(R0 <= 0) continue;

         MqlTick tk;
         if(!SymbolInfoTick(sym, tk) || tk.bid <= 0 || tk.ask <= 0) continue;
         double price = isBuy ? tk.bid : tk.ask;
         double rNow  = isBuy ? (tk.bid - open) / R0 : (open - tk.ask) / R0;

         double cand = sl;
         if(InpUseBreakEven && rNow >= InpBETriggerR)
            cand = MoreProtective(isBuy, cand, isBuy ? open + InpBEOffsetR * R0 : open - InpBEOffsetR * R0);
         if(InpUseRLock && rNow >= InpRLockThreshold)
            cand = MoreProtective(isBuy, cand, isBuy ? open + InpRLockLevelR * R0 : open - InpRLockLevelR * R0);
         if(InpUseDynamicTrail && rNow >= InpRLockThreshold)
            cand = MoreProtective(isBuy, cand, isBuy ? price - InpTrailDistanceR * R0 : price + InpTrailDistanceR * R0);

         cand = NormalizePrice(sym, cand);
         if(cand <= 0 || cand == sl) continue;
         if(sl > 0)
         {
            double improve = isBuy ? cand - sl : sl - cand;
            if(improve < InpTrailStepR * R0) continue;
         }

         double minDist = MinStopDistance(sym);
         if(isBuy  && tk.bid - cand <= minDist) continue;
         if(!isBuy && cand - tk.ask <= minDist) continue;

         if(m_trade.PositionModify(ticket, cand, tp))
            Log(StringFormat("%s : SL déplacé à %s (%.2fR en cours)", sym, PriceStr(sym, cand), rNow));
         else
         {
            RecordModifyFail(ticket);
            Log(StringFormat("%s : échec modification SL - %u %s", sym, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
         }
      }
   }

   bool PositionExistsById(long id)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t > 0 && PositionGetInteger(POSITION_IDENTIFIER) == id) return true;
      }
      return false;
   }

   void CleanupGlobals()
   {
      for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
      {
         string name = GlobalVariableName(i);
         if(StringFind(name, m_gvPrefix) != 0) continue;
         long id = StringToInteger(StringSubstr(name, StringLen(m_gvPrefix)));
         if(!PositionExistsById(id)) GlobalVariableDel(name);
      }
   }
};

//+------------------------------------------------------------------+
//| INSTANCE GLOBALE & ÉVÉNEMENTS                                    |
//+------------------------------------------------------------------+
CSmcBot g_bot;

int OnInit()
{
   if(!g_bot.Init()) return INIT_PARAMETERS_INCORRECT;
   // Le timer traite aussi les symboles qui ne sont pas celui du graphique
   EventSetTimer(MQLInfoInteger(MQL_TESTER) ? 60 : 1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_bot.PrintReport();
   g_bot.Deinit();
}

void OnTick()  { g_bot.Process(); }
void OnTimer() { g_bot.Process(); }

// Critère d'optimisation ("Custom max") : PF pénalisé par le drawdown, 0 si trop peu de trades
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < InpTesterMinTrades) return 0;
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   return pf * (1.0 - MathMin(dd, 99.0) / 100.0);
}
//+------------------------------------------------------------------+
