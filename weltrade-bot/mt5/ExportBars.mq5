//+------------------------------------------------------------------+
//|                                                 ExportBars.mq5   |
//|  Script : exporte en une fois l'historique de TOUS les indices   |
//|  autorises (FX Vol / SFX Vol 20-40-60, GainX) dans les unites de  |
//|  temps utiles, plus leurs caracteristiques reelles (spread,      |
//|  swap, distances minimales, lots...).                            |
//|                                                                  |
//|  Sortie : <Dossier commun>\Files\SyntX_data\                     |
//|    - un CSV par indice et par UT  (ex. FX_Vol_40_M15.csv)        |
//|    - SyntX_specs.csv                                             |
//|  Envoyez ce dossier a backtest/calibrate.py.                     |
//|                                                                  |
//|  Astuce : Outils > Options > Graphiques > "Barres max. dans le    |
//|  graphique" limite l'historique disponible : mettez Illimite.    |
//+------------------------------------------------------------------+
#property script_show_inputs
#property version "2.00"

input int  InpBarsM1  = 300000;  // Barres M1 (GainX)          ~ 7 mois
input int  InpBarsM15 = 100000;  // Barres M15 (FX/SFX Vol)    ~ 2,8 ans
input int  InpBarsH1  = 30000;   // Barres H1 (FX/SFX Vol)     ~ 3,4 ans
input bool InpAlsoM5  = false;   // Exporter aussi M5 pour FX/SFX Vol
input int  InpBarsM5  = 150000;  // Barres M5

const string FOLDER = "SyntX_data\\";

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

//--- 1 = FX/SFX Vol autorise, 2 = GainX, 0 = autre
int Kind(const string symbol)
  {
   string s = NormalizeSymbol(symbol);
   int lvl;
   if(StringFind(s, "SFXVOL") >= 0) { lvl = NumberAfter(s, "SFXVOL"); return (lvl == 20 || lvl == 40 || lvl == 60) ? 1 : 0; }
   if(StringFind(s, "FXVOL") >= 0)  { lvl = NumberAfter(s, "FXVOL");  return (lvl == 20 || lvl == 40 || lvl == 60) ? 1 : 0; }
   if(StringFind(s, "GAINX") >= 0)  return 2;
   return 0;
  }

string TFName(ENUM_TIMEFRAMES tf)
  {
   string n = EnumToString(tf);
   StringReplace(n, "PERIOD_", "");
   return n;
  }

//--- Copie l'historique en laissant au terminal le temps de le telecharger
int LoadRates(const string sym, ENUM_TIMEFRAMES tf, int want, MqlRates &r[])
  {
   ArraySetAsSeries(r, false);
   int got = -1;
   for(int attempt = 0; attempt < 30 && !IsStopped(); attempt++)
     {
      got = CopyRates(sym, tf, 0, want, r);
      if(got >= want) break;
      int prev = got;
      Sleep(1000);
      got = CopyRates(sym, tf, 0, want, r);
      if(got == prev && got > 0) break;   // plus rien n'arrive : on garde ce qu'on a
     }
   return got;
  }

bool ExportOne(const string sym, ENUM_TIMEFRAMES tf, int want)
  {
   MqlRates r[];
   int n = LoadRates(sym, tf, want, r);
   if(n <= 0)
     {
      PrintFormat("  %s %s : aucune donnee", sym, TFName(tf));
      return false;
     }
   string name = sym;
   StringReplace(name, " ", "_");
   string file = FOLDER + name + "_" + TFName(tf) + ".csv";
   int fh = FileOpen(file, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, '\t');
   if(fh == INVALID_HANDLE)
     {
      PrintFormat("  Impossible de creer %s", file);
      return false;
     }
   FileWrite(fh, "<DATE>", "<TIME>", "<OPEN>", "<HIGH>", "<LOW>", "<CLOSE>", "<TICKVOL>", "<SPREAD>");
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   for(int i = 0; i < n; i++)
      FileWrite(fh, TimeToString(r[i].time, TIME_DATE), TimeToString(r[i].time, TIME_SECONDS),
                DoubleToString(r[i].open, digits), DoubleToString(r[i].high, digits),
                DoubleToString(r[i].low, digits), DoubleToString(r[i].close, digits),
                (string)r[i].tick_volume, (string)r[i].spread);
   FileClose(fh);
   PrintFormat("  %s %s : %d barres (%s -> %s)%s", sym, TFName(tf), n,
               TimeToString(r[0].time, TIME_DATE), TimeToString(r[n - 1].time, TIME_DATE),
               n < want ? "  [moins que demande : augmentez les barres max. du terminal]" : "");
   return true;
  }

void WriteSpecs(int fh, const string sym)
  {
   FileWrite(fh, sym,
             DoubleToString(SymbolInfoDouble(sym, SYMBOL_POINT), 10),
             (string)SymbolInfoInteger(sym, SYMBOL_DIGITS),
             DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE), 10),
             DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE), 10),
             DoubleToString(SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE), 4),
             DoubleToString(SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN), 4),
             DoubleToString(SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP), 4),
             DoubleToString(SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX), 4),
             (string)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL),
             (string)SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL),
             (string)SymbolInfoInteger(sym, SYMBOL_SWAP_MODE),
             DoubleToString(SymbolInfoDouble(sym, SYMBOL_SWAP_LONG), 6),
             DoubleToString(SymbolInfoDouble(sym, SYMBOL_SWAP_SHORT), 6),
             (string)SymbolInfoInteger(sym, SYMBOL_SPREAD),
             (string)SymbolInfoInteger(sym, SYMBOL_TRADE_MODE));
  }

void OnStart()
  {
   int fs = FileOpen(FOLDER + "SyntX_specs.csv", FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fs == INVALID_HANDLE) { Print("Impossible de creer SyntX_specs.csv"); return; }
   FileWrite(fs, "symbol", "point", "digits", "tick_size", "tick_value", "contract_size", "volume_min",
             "volume_step", "volume_max", "stops_level", "freeze_level", "swap_mode", "swap_long",
             "swap_short", "spread_points", "trade_mode");

   int found = 0;
   int total = SymbolsTotal(false);   // tous les symboles du serveur
   for(int i = 0; i < total && !IsStopped(); i++)
     {
      string sym = SymbolName(i, false);
      int kind = Kind(sym);
      if(kind == 0) continue;
      found++;
      SymbolSelect(sym, true);
      PrintFormat("%s :", sym);
      WriteSpecs(fs, sym);
      if(kind == 2)
         ExportOne(sym, PERIOD_M1, InpBarsM1);
      else
        {
         ExportOne(sym, PERIOD_M15, InpBarsM15);
         ExportOne(sym, PERIOD_H1, InpBarsH1);
         if(InpAlsoM5) ExportOne(sym, PERIOD_M5, InpBarsM5);
        }
     }
   FileClose(fs);
   PrintFormat("Termine : %d indice(s) exporte(s) dans <Dossier commun>\\Files\\%s", found, FOLDER);
   if(found == 0) Print("Aucun indice autorise trouve : verifiez que vous etes connecte au serveur Weltrade.");
  }
