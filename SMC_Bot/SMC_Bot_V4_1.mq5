//+------------------------------------------------------------------+
//|                                                SMC_Bot_V4_1.mq5  |
//|   Bot SMC multi-symboles - OB 5 étoiles (vierge + FVG + BOS)      |
//|   Biais HTF par structure, confirmation LTF, SL structurel,       |
//|   gestion R-Based, profils par classe d'actif                     |
//+------------------------------------------------------------------+
#property copyright "SMC Bot V4.1"
#property version   "4.10"
#property description "OB vierge + FVG + cassure de structure sur MTF, biais HTF par BOS,"
#property description "confirmation CHoCH/engulfing sur LTF, SL sous/au-dessus de l'OB,"
#property description "gestion R-Based (BE, lock, trailing), profils Forex/Or/Indices/Crypto."

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
   SETUP_WATCHING = 1,   // OB vierge armé, on attend que le prix y revienne
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

input group "=== Structure HTF (Biais) ==="
input int      InpSwingStrength    = 3;          // Force des swings HTF (bougies de chaque côté)
input int      InpHTFLookback      = 200;        // Bougies HTF analysées

input group "=== Filtres OB 5 Étoiles ==="
input int      InpMaxOBAgeBars     = 50;         // Âge maximum de l'OB (bougies MTF)
input bool     InpRequireFVG       = true;       // Exiger un FVG dans le déplacement
input int      InpStructureBars    = 10;         // Le déplacement doit casser l'extrême des N bougies avant l'OB
input int      InpDisplacementBars = 3;          // Nombre max de bougies pour le déplacement
input double   InpDisplacementATR  = 1.0;        // Corps min. d'une bougie du déplacement (x ATR)
input int      InpATRPeriod        = 14;         // Période ATR (MTF)

input group "=== Confirmation LTF ==="
input bool     InpAllowEngulfing   = true;       // Accepter un engulfing dans la zone
input int      InpLTFSwingStrength = 2;          // Force des swings LTF (CHoCH)
input int      InpConfirmMaxBars   = 12;         // Bougies LTF max pour confirmer après le toucher

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
input bool     InpUseCorrelationFilter = true;   // Activer filtre de corrélation
input double   InpCorrelationThreshold = 0.7;    // Seuil de corrélation (rendements H1)
input bool     InpUseNewsFilter    = true;       // Activer filtre de news (live uniquement)
input int      InpNewsMinutesBefore= 15;         // Minutes avant la news
input int      InpNewsMinutesAfter = 15;         // Minutes après la news

input group "=== Configuration Technique ==="
input int      InpMagicNumber      = 20241006;   // Magic Number
input int      InpSlippage         = 30;         // Slippage max (points)
input int      InpTesterMinTrades  = 100;        // Trades min pour le critère d'optimisation

//+------------------------------------------------------------------+
//| OUTILS                                                           |
//+------------------------------------------------------------------+
void Log(const string msg)
{
   if(InpVerbose) Print("[SMC4.1] ", msg);
}

void Notify(const string msg)
{
   Print("[SMC4.1] ", msg);
   if(InpSendPush && !MQLInfoInteger(MQL_TESTER)) SendNotification("SMC4.1 " + msg);
}

double NormalizePrice(const string sym, double price)
{
   double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   int digits  = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(tick > 0) price = MathRound(price / tick) * tick;
   return NormalizeDouble(price, digits);
}

int VolumeDigits(double step)
{
   int d = 0;
   double s = step;
   while(d < 8 && MathAbs(s - MathRound(s)) > 1e-9) { s *= 10.0; d++; }
   return d;
}

// Vrai une seule fois par nouvelle bougie. 'last' mémorise l'heure de la dernière bougie vue.
bool IsNewBar(const string sym, ENUM_TIMEFRAMES tf, datetime &last)
{
   datetime t = iTime(sym, tf, 0);
   if(t == 0) return false;          // données pas encore chargées
   if(t != last) { last = t; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| STRUCTURES                                                       |
//+------------------------------------------------------------------+
struct SSymbolProfile
{
   ENUM_ASSET_CLASS assetClass;
   double           rewardRatio;     // TP = RR x risque
   double           slBufferATR;     // marge du SL au-delà de l'OB
   double           minSLATR;        // SL minimum
   double           maxSLATR;        // SL maximum
   double           maxSpreadPct;    // spread max en % de la distance du SL
   bool             useSession;      // filtre de session appliqué ?
};

struct SOrderBlock
{
   bool     valid;
   int      direction;   // 1 = haussier (demande), -1 = baissier (offre)
   double   high;
   double   low;
   datetime time;        // heure d'ouverture de la bougie OB
   double   fvgHigh;
   double   fvgLow;

   void Reset() { valid = false; direction = 0; high = 0; low = 0; time = 0; fvgHigh = 0; fvgLow = 0; }
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
      if(StringFind(s, "US30") >= 0 || StringFind(s, "US100") >= 0 || StringFind(s, "US500") >= 0 ||
         StringFind(s, "NAS") >= 0  || StringFind(s, "SPX") >= 0   || StringFind(s, "DJ") >= 0    ||
         StringFind(s, "GER") >= 0  || StringFind(s, "DE40") >= 0)
         return ASSET_INDEX;
      return ASSET_FOREX;
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
      bias = 0; lastHTFBar = 0; lastMTFBar = 0; lastLTFBar = 0; lastUsedOBTime = 0;
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

public:
   void Init(long magic)
   {
      m_magic  = magic;
      m_gvPeak = "SMC41_" + IntegerToString(magic) + "_PEAK";
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      m_peakEquity = eq;
      double stored = 0;
      if(!InpResetPeakEquity && GlobalVariableGet(m_gvPeak, stored) && stored > eq) m_peakEquity = stored;
      GlobalVariableSet(m_gvPeak, m_peakEquity);

      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      m_dayOfYear      = dt.day_of_year;
      m_dayStartEquity = eq;
   }

   void Update()
   {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > m_peakEquity) { m_peakEquity = eq; GlobalVariableSet(m_gvPeak, eq); }
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_year != m_dayOfYear) { m_dayOfYear = dt.day_of_year; m_dayStartEquity = eq; }
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
         ulong ticket = PositionGetTicket(i);           // sélectionne la position
         if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == m_magic) count++;
      }
      return count;
   }

   // Argent réellement en risque : seulement la partie SL du côté perdant.
   // Une position au BE ou avec gains verrouillés compte pour 0.
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
         if(sl <= 0) { total += balance * InpRiskPercent / 100.0; continue; }   // sans SL : risque standard
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
      if(step <= 0) step = minLot;
      if(step <= 0) { why = "pas de lot invalide"; return 0; }

      double lots = MathFloor(riskMoney / lossPerLot / step + 1e-9) * step;
      if(lots < minLot - 1e-9)
      {
         // On refuse plutôt que de forcer le lot minimum (qui dépasserait le risque autorisé)
         why = StringFormat("lot calculé %.4f < lot min %.4f (capital trop faible pour ce SL)", lots, minLot);
         return 0;
      }
      lots = MathMin(lots, maxLot);
      lots = NormalizeDouble(lots, VolumeDigits(step));

      double margin = 0;
      if(OrderCalcMargin(ot, sym, lots, entry, margin) && margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.9)
      { why = "marge libre insuffisante"; return 0; }
      return lots;
   }
};

//+------------------------------------------------------------------+
//| CLASSE : DÉTECTION SMC (biais, OB 5 étoiles, confirmation)       |
//+------------------------------------------------------------------+
class CSignalEngine
{
public:
   // ATR de la dernière bougie MTF clôturée (0 si indisponible)
   double GetATR(CSymbolContext &c)
   {
      if(c.atrHandle == INVALID_HANDLE) return 0;
      double buf[];
      if(CopyBuffer(c.atrHandle, 0, 1, 1, buf) != 1) return 0;
      return buf[0];
   }

   // Biais HTF par structure : direction du dernier BOS (clôture au-delà du dernier swing).
   // Retourne false si les données ne sont pas prêtes.
   bool HTFBias(const string sym, int &bias)
   {
      bias = 0;
      int s = MathMax(1, InpSwingStrength);
      MqlRates r[];
      ArraySetAsSeries(r, false);                       // r[0] = plus ancienne
      int n = CopyRates(sym, InpHTF, 1, InpHTFLookback, r);
      if(n < 4 * s + 10) return false;

      double lastSH = 0, lastSL = 0;
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
         if(isSH) { lastSH = r[k].high; shBroken = false; }
         if(isSL) { lastSL = r[k].low;  slBroken = false; }

         if(!shBroken && r[i].close > lastSH) { bias =  1; shBroken = true; }
         if(!slBroken && r[i].close < lastSL) { bias = -1; slBroken = true; }
      }
      return true;
   }

   // Cherche l'OB vierge le plus récent dans le sens du biais.
   // Retour : 1 = trouvé, 0 = aucun, -1 = données indisponibles
   int FindFreshOB(CSymbolContext &c, int bias, SOrderBlock &out)
   {
      out.Reset();
      double atr = GetATR(c);
      if(atr <= 0) return -1;

      int need = InpMaxOBAgeBars + InpStructureBars + InpDisplacementBars + 5;
      MqlRates r[];
      ArraySetAsSeries(r, false);                       // r[0] = plus ancienne, r[n-1] = dernière clôturée
      int n = CopyRates(c.symbol, InpMTF, 1, need, r);
      if(n < InpStructureBars + InpDisplacementBars + 5) return -1;

      double bid  = SymbolInfoDouble(c.symbol, SYMBOL_BID);
      int    last = n - 1;

      for(int k = last - 1; k >= InpStructureBars; k--)
      {
         int age = last - k + 1;                        // bougies MTF écoulées depuis l'OB
         if(age > InpMaxOBAgeBars) break;
         if(r[k].time == c.lastUsedOBTime) continue;

         int    dispEnd = -1, fvgEnd = -1;
         double maxBody = 0, fH = 0, fL = 0;
         bool   fvg = false;
         int    dLimit = MathMin(k + InpDisplacementBars, last);

         if(bias == 1)
         {
            // OB haussier = dernière bougie baissière avant l'impulsion haussière
            if(r[k].close >= r[k].open)         continue;
            if(r[k + 1].close <= r[k + 1].open) continue;

            double structHigh = r[k].high;
            for(int s = k - InpStructureBars; s < k; s++) structHigh = MathMax(structHigh, r[s].high);

            for(int j = k + 1; j <= dLimit; j++)
            {
               maxBody = MathMax(maxBody, r[j].close - r[j].open);
               if(r[j].close > structHigh) { dispEnd = j; break; }   // BOS
            }
            if(dispEnd < 0 || maxBody < InpDisplacementATR * atr) continue;

            for(int m = k + 1; m <= MathMin(dispEnd + 1, last - 1); m++)
               if(r[m + 1].low > r[m - 1].high) { fvg = true; fL = r[m - 1].high; fH = r[m + 1].low; fvgEnd = m + 1; break; }
            if(InpRequireFVG && !fvg) continue;

            double zH = r[k].high, zL = r[k].low;
            int startCheck = MathMax(dispEnd, fvgEnd) + 1;
            bool fresh = true;
            for(int t = startCheck; t <= last; t++)
               if(r[t].low <= zH) { fresh = false; break; }   // déjà mitigé
            if(!fresh) continue;
            if(bid < zL) continue;                              // prix déjà sous l'OB : invalidé

            out.valid = true; out.direction = 1; out.high = zH; out.low = zL;
            out.time = r[k].time; out.fvgHigh = fH; out.fvgLow = fL;
            return 1;
         }
         else if(bias == -1)
         {
            // OB baissier = dernière bougie haussière avant l'impulsion baissière
            if(r[k].close <= r[k].open)         continue;
            if(r[k + 1].close >= r[k + 1].open) continue;

            double structLow = r[k].low;
            for(int s = k - InpStructureBars; s < k; s++) structLow = MathMin(structLow, r[s].low);

            for(int j = k + 1; j <= dLimit; j++)
            {
               maxBody = MathMax(maxBody, r[j].open - r[j].close);
               if(r[j].close < structLow) { dispEnd = j; break; }    // BOS
            }
            if(dispEnd < 0 || maxBody < InpDisplacementATR * atr) continue;

            for(int m = k + 1; m <= MathMin(dispEnd + 1, last - 1); m++)
               if(r[m + 1].high < r[m - 1].low) { fvg = true; fH = r[m - 1].low; fL = r[m + 1].high; fvgEnd = m + 1; break; }
            if(InpRequireFVG && !fvg) continue;

            double zH = r[k].high, zL = r[k].low;
            int startCheck = MathMax(dispEnd, fvgEnd) + 1;
            bool fresh = true;
            for(int t = startCheck; t <= last; t++)
               if(r[t].high >= zL) { fresh = false; break; }
            if(!fresh) continue;
            if(bid > zH) continue;

            out.valid = true; out.direction = -1; out.high = zH; out.low = zL;
            out.time = r[k].time; out.fvgHigh = fH; out.fvgLow = fL;
            return 1;
         }
      }
      return 0;
   }

   // Confirmation sur bougies LTF CLÔTURÉES (r[0] = dernière clôturée)
   bool ConfirmLTF(CSymbolContext &c)
   {
      int s    = MathMax(1, InpLTFSwingStrength);
      int need = InpConfirmMaxBars + 2 * s + 30;
      MqlRates r[];
      ArraySetAsSeries(r, true);
      int n = CopyRates(c.symbol, InpLTF, 1, need, r);
      if(n < 2 * s + 5) return false;

      int    dir = c.ob.direction;
      double zH  = c.ob.high, zL = c.ob.low;

      // 1) Engulfing au contact de la zone
      if(InpAllowEngulfing)
      {
         if(dir == 1 && r[0].close > r[0].open && r[1].close < r[1].open &&
            r[0].close > r[1].open && r[0].open <= r[1].close &&
            MathMin(r[0].low, r[1].low) <= zH && r[0].close > zL)
            return true;
         if(dir == -1 && r[0].close < r[0].open && r[1].close > r[1].open &&
            r[0].close < r[1].open && r[0].open >= r[1].close &&
            MathMax(r[0].high, r[1].high) >= zL && r[0].close < zH)
            return true;
      }

      // 2) CHoCH : première clôture au-delà du dernier swing LTF formé pendant le retour dans la zone
      datetime minTime = c.touchTime - PeriodSeconds(InpLTF) * 20;
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
         if(!broken) return false;                    // le swing le plus récent n'est pas cassé
         for(int q = 1; q < i; q++)                   // doit être la PREMIÈRE clôture au-delà
         {
            if(dir == 1  && r[q].close > level) return false;
            if(dir == -1 && r[q].close < level) return false;
         }
         return true;
      }
      return false;
   }
};

//+------------------------------------------------------------------+
//| CLASSE : BOT (scanner multi-symboles, filtres, exécution, gestion)|
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

public:
   bool Init()
   {
      if(PeriodSeconds(InpHTF) <= PeriodSeconds(InpMTF) || PeriodSeconds(InpMTF) <= PeriodSeconds(InpLTF))
      { Print("[SMC4.1] Erreur : il faut HTF > MTF > LTF"); return false; }
      if(InpRiskPercent <= 0 || InpRiskPercent > InpMaxTotalRisk)
      { Print("[SMC4.1] Erreur : 0 < risque par trade <= risque total"); return false; }
      if(InpMaxOpenTrades <= 0 || InpMaxOBAgeBars <= 0 || InpConfirmMaxBars <= 0)
      { Print("[SMC4.1] Erreur : paramètres de comptage invalides"); return false; }

      m_trade.SetExpertMagicNumber(InpMagicNumber);
      m_trade.SetDeviationInPoints(InpSlippage);
      m_trade.SetAsyncMode(false);
      m_risk.Init(InpMagicNumber);
      m_gvPrefix    = "SMC41_" + IntegerToString(InpMagicNumber) + "_R_";
      m_lastCleanup = 0;

      m_count = 0;
      ArrayResize(m_ctx, 0);
      AddSymbol(InpTradeEURUSD, InpNameEURUSD);
      AddSymbol(InpTradeXAUUSD, InpNameXAUUSD);
      AddSymbol(InpTradeUS30,   InpNameUS30);
      AddSymbol(InpTradeBTCUSD, InpNameBTCUSD);
      AddSymbol(InpTradeGBPUSD, InpNameGBPUSD);
      AddSymbol(InpTradeUSDJPY, InpNameUSDJPY);
      AddSymbol(InpTradeAUDUSD, InpNameAUDUSD);

      if(m_count == 0) { Print("[SMC4.1] Aucun symbole valide : vérifie les noms (suffixes broker)"); return false; }
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

      Print("[SMC4.1] ===== Rapport par symbole =====");
      for(int i = 0; i < m_count; i++)
      {
         double pf = (gl[i] > 0) ? gp[i] / gl[i] : (gp[i] > 0 ? 999.0 : 0.0);
         double wr = (cnt[i] > 0) ? 100.0 * wins[i] / cnt[i] : 0.0;
         Print(StringFormat("[SMC4.1] %-10s trades=%d  winrate=%.1f%%  PF=%.2f  net=%.2f  %s",
               m_ctx[i].symbol, cnt[i], wr, pf, gp[i] - gl[i], (pf >= 1.5 ? "OK" : "< 1.5")));
      }
   }

private:
   void AddSymbol(bool enabled, const string name)
   {
      if(!enabled) return;
      string sym = name;
      StringTrimLeft(sym); StringTrimRight(sym);
      if(sym == "") return;
      if(!SymbolSelect(sym, true)) { Print("[SMC4.1] Symbole introuvable : ", sym, " (vérifie le nom/suffixe du broker)"); return; }

      int handle = iATR(sym, InpMTF, InpATRPeriod);
      if(handle == INVALID_HANDLE) { Print("[SMC4.1] Impossible de créer l'ATR pour ", sym); return; }

      int idx = m_count;
      ArrayResize(m_ctx, m_count + 1);
      m_count++;
      m_ctx[idx].symbol    = sym;
      m_ctx[idx].atrHandle = handle;
      CProfileManager::Get(sym, m_ctx[idx].profile);
      m_ctx[idx].ready     = true;

      Print(StringFormat("[SMC4.1] %s ajouté - profil %s : RR=%.1f, marge SL=%.2f ATR, SL max=%.1f ATR, spread max=%.0f%% du SL",
            sym, CProfileManager::ClassName(m_ctx[idx].profile.assetClass), m_ctx[idx].profile.rewardRatio,
            m_ctx[idx].profile.slBufferATR, m_ctx[idx].profile.maxSLATR, m_ctx[idx].profile.maxSpreadPct));
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
      if(c.state == SETUP_IN_TRADE) c.ResetSetup();          // position clôturée : on repart de zéro

      // 1) Biais HTF recalculé à chaque nouvelle bougie HTF
      if(IsNewBar(sym, InpHTF, c.lastHTFBar))
      {
         int nb = 0;
         if(!m_engine.HTFBias(sym, nb)) { c.lastHTFBar = 0; return; }   // données pas prêtes : on réessaiera
         if(nb != c.bias)
         {
            Log(StringFormat("%s : biais HTF %d -> %d", sym, c.bias, nb));
            c.bias = nb;
            if(c.state != SETUP_IDLE && c.ob.direction != nb) c.ResetSetup();
         }
      }
      if(c.bias == 0) return;

      // 2) Recherche d'OB vierge à chaque nouvelle bougie MTF (sauf si le prix est déjà dans la zone)
      bool newMTF = IsNewBar(sym, InpMTF, c.lastMTFBar);
      if(newMTF && c.state != SETUP_IN_ZONE)
      {
         SOrderBlock found;
         int res = m_engine.FindFreshOB(c, c.bias, found);
         if(res < 0) { c.lastMTFBar = 0; return; }
         if(res == 1)
         {
            if(!c.ob.valid || found.time != c.ob.time)
               Log(StringFormat("%s : OB %s armé [%s - %s] du %s", sym, found.direction == 1 ? "haussier" : "baissier",
                   DoubleToString(found.low, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
                   DoubleToString(found.high, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
                   TimeToString(found.time)));
            c.ob    = found;
            c.state = SETUP_WATCHING;
         }
         else c.ResetSetup();
      }

      // 3) Attente du retour du prix dans l'OB
      if(c.state == SETUP_WATCHING)
      {
         int age = iBarShift(sym, InpMTF, c.ob.time);
         if(age < 0 || age > InpMaxOBAgeBars) { c.ResetSetup(); return; }

         double bid  = SymbolInfoDouble(sym, SYMBOL_BID);
         double lLow = iLow(sym, InpLTF, 0), lHigh = iHigh(sym, InpLTF, 0);
         if(lLow  <= 0) lLow  = bid;
         if(lHigh <= 0) lHigh = bid;

         bool touched = (c.ob.direction == 1) ? (MathMin(bid, lLow) <= c.ob.high) : (MathMax(bid, lHigh) >= c.ob.low);
         if(!touched) return;

         c.state      = SETUP_IN_ZONE;
         c.touchTime  = TimeCurrent();
         c.lastLTFBar = iTime(sym, InpLTF, 0);        // on confirmera sur les bougies clôturées à partir d'ici
         Log(StringFormat("%s : prix dans l'OB, attente de confirmation %s", sym, EnumToString(InpLTF)));
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
         if(lastClose > 0 && ((c.ob.direction == 1 && lastClose < c.ob.low) || (c.ob.direction == -1 && lastClose > c.ob.high)))
         {
            Log(sym + " : clôture LTF au-delà de l'OB, setup invalidé");
            c.lastUsedOBTime = c.ob.time; c.ResetSetup(); return;
         }

         if(!m_engine.ConfirmLTF(c)) return;
         Log(sym + " : confirmation LTF obtenue");

         string why;
         if(!EntryAllowed(c, why)) { Log(sym + " : entrée bloquée - " + why); return; }   // on attend une autre confirmation

         c.lastUsedOBTime = c.ob.time;
         if(TryEnter(c)) c.state = SETUP_IN_TRADE;
         else            c.ResetSetup();
      }
   }

   //--- Filtres -----------------------------------------------------------
   bool EntryAllowed(CSymbolContext &c, string &why)
   {
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) { why = "trading automatique désactivé"; return false; }
      ENUM_SYMBOL_TRADE_MODE tm = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(c.symbol, SYMBOL_TRADE_MODE);
      if(tm == SYMBOL_TRADE_MODE_DISABLED || tm == SYMBOL_TRADE_MODE_CLOSEONLY) { why = "symbole non négociable"; return false; }
      if(c.ob.direction == 1  && tm == SYMBOL_TRADE_MODE_SHORTONLY) { why = "achats interdits"; return false; }
      if(c.ob.direction == -1 && tm == SYMBOL_TRADE_MODE_LONGONLY)  { why = "ventes interdites"; return false; }
      if(!IsSessionOpen(c))                 { why = "hors session"; return false; }
      if(!m_risk.CanOpenNewTrade(why))      return false;
      if(IsNewsTime(c))                     { why = "news à fort impact"; return false; }
      if(IsCorrelated(c.symbol, c.ob.direction)) { why = "corrélé à une position ouverte"; return false; }
      return true;
   }

   bool IsSessionOpen(CSymbolContext &c)
   {
      if(!InpUseSessionFilter || !c.profile.useSession) return true;
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      if(InpSessionStartHour <= InpSessionEndHour) return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
      return (dt.hour >= InpSessionStartHour || dt.hour < InpSessionEndHour);
   }

   bool IsNewsTime(CSymbolContext &c)
   {
      if(!InpUseNewsFilter) return false;
      if(MQLInfoInteger(MQL_TESTER)) return false;    // le calendrier n'est pas disponible dans le testeur

      datetime now = TimeTradeServer();
      if(now - c.newsCheckTime < 60) return c.newsBlocked;    // cache 1 minute
      c.newsCheckTime = now;
      c.newsBlocked   = false;

      string curs[2];
      curs[0] = SymbolInfoString(c.symbol, SYMBOL_CURRENCY_BASE);
      curs[1] = SymbolInfoString(c.symbol, SYMBOL_CURRENCY_PROFIT);
      datetime from = now - InpNewsMinutesAfter * 60;
      datetime to   = now + InpNewsMinutesBefore * 60;

      for(int k = 0; k < 2; k++)
      {
         if(curs[k] == "" || (k == 1 && curs[1] == curs[0])) continue;
         MqlCalendarValue vals[];
         if(CalendarValueHistory(vals, from, to, NULL, curs[k]) <= 0) continue;
         for(int i = 0; i < ArraySize(vals); i++)
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
         // même sens + corrélation positive = même pari ; sens opposés + corrélation négative = même pari
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
   bool TryEnter(CSymbolContext &c)
   {
      string sym = c.symbol;
      int    dir = c.ob.direction;
      double atr = m_engine.GetATR(c);
      if(atr <= 0) { Log(sym + " : ATR indisponible, entrée annulée"); return false; }

      double ask = SymbolInfoDouble(sym, SYMBOL_ASK), bid = SymbolInfoDouble(sym, SYMBOL_BID);
      if(ask <= 0 || bid <= 0) return false;
      double spread = ask - bid;
      double entry  = (dir == 1) ? ask : bid;

      // SL structurel : au-delà de l'OB + marge ATR (+ spread pour les ventes, le SL étant déclenché sur l'Ask)
      double buffer = c.profile.slBufferATR * atr;
      double sl     = (dir == 1) ? c.ob.low - buffer : c.ob.high + buffer + spread;
      double risk   = (dir == 1) ? entry - sl : sl - entry;

      double minRisk = c.profile.minSLATR * atr;
      if(risk < minRisk) { risk = minRisk; sl = (dir == 1) ? entry - risk : entry + risk; }
      if(risk > c.profile.maxSLATR * atr)
      { Log(StringFormat("%s : SL trop large (%.2f ATR > %.2f), trade refusé", sym, risk / atr, c.profile.maxSLATR)); return false; }
      if(spread > risk * c.profile.maxSpreadPct / 100.0)
      { Log(StringFormat("%s : spread trop élevé (%.1f%% du SL)", sym, 100.0 * spread / risk)); return false; }

      double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
      double minDist = MathMax((double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL), (double)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL)) * point;
      if(risk <= minDist + spread) { Log(sym + " : SL sous la distance minimale du broker"); return false; }

      double tp = (dir == 1) ? entry + risk * c.profile.rewardRatio : entry - risk * c.profile.rewardRatio;
      sl = NormalizePrice(sym, sl);
      tp = NormalizePrice(sym, tp);

      string why;
      double lots = m_risk.CalculateLots(sym, dir, entry, sl, why);
      if(lots <= 0) { Log(sym + " : volume nul - " + why); return false; }

      m_trade.SetTypeFillingBySymbol(sym);
      string comment = StringFormat("SMC4.1 %s RR%.1f", dir == 1 ? "BUY" : "SELL", c.profile.rewardRatio);
      bool ok = (dir == 1) ? m_trade.Buy(lots, sym, 0.0, sl, tp, comment) : m_trade.Sell(lots, sym, 0.0, sl, tp, comment);
      uint rc = m_trade.ResultRetcode();
      if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_DONE_PARTIAL && rc != TRADE_RETCODE_PLACED))
      {
         Notify(StringFormat("Échec ordre %s %s : %u %s", dir == 1 ? "BUY" : "SELL", sym, rc, m_trade.ResultRetcodeDescription()));
         return false;
      }

      SaveInitialRisk(sym);
      int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      Notify(StringFormat("%s %s %.2f lots @ %s | SL %s | TP %s | %s",
             dir == 1 ? "BUY" : "SELL", sym, lots, DoubleToString(m_trade.ResultPrice(), digits),
             DoubleToString(sl, digits), DoubleToString(tp, digits),
             dir == 1 ? "OB haussier vierge + FVG + BOS" : "OB baissier vierge + FVG + BOS"));
      return true;
   }

   //--- Gestion R-Based -----------------------------------------------------
   void SaveInitialRisk(const string sym)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong t = PositionGetTicket(i);
         if(t == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber || PositionGetString(POSITION_SYMBOL) != sym) continue;
         double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
         string name = m_gvPrefix + IntegerToString(PositionGetInteger(POSITION_IDENTIFIER));
         if(sl > 0 && !GlobalVariableCheck(name)) GlobalVariableSet(name, MathAbs(open - sl));
      }
   }

   // Risque initial (1R) en prix. Stocké en variable globale -> survit à un redémarrage.
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

   void ManagePositions()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

         string sym   = PositionGetString(POSITION_SYMBOL);
         bool   isBuy = ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
         double open  = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl    = PositionGetDouble(POSITION_SL);
         double tp    = PositionGetDouble(POSITION_TP);
         long   id    = PositionGetInteger(POSITION_IDENTIFIER);

         double R0 = GetInitialRisk(sym, id, isBuy, open, sl, tp);
         if(R0 <= 0) continue;

         double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         if(bid <= 0 || ask <= 0) continue;
         double price = isBuy ? bid : ask;
         double rNow  = isBuy ? (bid - open) / R0 : (open - ask) / R0;

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

         double point   = SymbolInfoDouble(sym, SYMBOL_POINT);
         double minDist = MathMax((double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL), (double)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL)) * point;
         if(isBuy  && bid - cand <= minDist) continue;
         if(!isBuy && cand - ask <= minDist) continue;

         if(m_trade.PositionModify(ticket, cand, tp))
            Log(StringFormat("%s : SL déplacé à %s (%.2fR en cours)", sym, DoubleToString(cand, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)), rNow));
         else
            Log(StringFormat("%s : échec modification SL - %u %s", sym, m_trade.ResultRetcode(), m_trade.ResultRetcodeDescription()));
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
   // En live, le timer traite aussi les symboles qui ne sont pas celui du graphique
   if(!MQLInfoInteger(MQL_TESTER)) EventSetTimer(1);
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

// Critère d'optimisation personnalisé ("Custom max") : PF pénalisé par le drawdown,
// 0 si trop peu de trades (évite de sélectionner des résultats sur-ajustés)
double OnTester()
{
   double trades = TesterStatistics(STAT_TRADES);
   if(trades < InpTesterMinTrades) return 0;
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   return pf * (1.0 - MathMin(dd, 99.0) / 100.0);
}
//+------------------------------------------------------------------+
