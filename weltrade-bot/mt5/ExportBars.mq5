//+------------------------------------------------------------------+
//|                                                 ExportBars.mq5   |
//|  Script : exporte l'historique du graphique courant en CSV       |
//|  (dossier MQL5\Files) pour le backtester Python.                  |
//+------------------------------------------------------------------+
#property script_show_inputs
#property version "1.00"

input int InpBars = 200000; // Nombre de barres a exporter

void OnStart()
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, _Period, 0, InpBars, r);
   if(n <= 0)
     {
      Print("Aucune donnee. Faites defiler le graphique pour charger l'historique.");
      return;
     }

   string sym = _Symbol;
   StringReplace(sym, " ", "_");
   string name = StringFormat("%s_%s.csv", sym, EnumToString(_Period));
   StringReplace(name, "PERIOD_", "");

   int fh = FileOpen(name, FILE_WRITE | FILE_CSV | FILE_ANSI, '\t');
   if(fh == INVALID_HANDLE) { Print("Impossible de creer ", name); return; }

   FileWrite(fh, "<DATE>", "<TIME>", "<OPEN>", "<HIGH>", "<LOW>", "<CLOSE>", "<TICKVOL>", "<SPREAD>");
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   for(int i = 0; i < n; i++)
      FileWrite(fh,
                TimeToString(r[i].time, TIME_DATE),
                TimeToString(r[i].time, TIME_SECONDS),
                DoubleToString(r[i].open, digits),
                DoubleToString(r[i].high, digits),
                DoubleToString(r[i].low, digits),
                DoubleToString(r[i].close, digits),
                (string)r[i].tick_volume,
                (string)r[i].spread);
   FileClose(fh);
   PrintFormat("%d barres exportees dans MQL5\\Files\\%s (point = %s)",
               n, name, DoubleToString(_Point, digits));
  }
