// Flux de prix réels. Sources vérifiées depuis un navigateur (CORS autorisé) :
//  - Kraken (sans clé)      : BTC (XBT/USD), Or via PAXG/USD (jeton adossé à l'or, proche du spot)
//  - Coinbase (sans clé)    : EUR/USD, USD/JPY, USD/CAD (taux agrégés ; mesuré : mis à jour toutes les 2-3 min ou plus, retard possible de 2-3 pips)
//  - Twelve Data (clé)      : S&P 500, Nasdaq 100, pétrole WTI, gaz naturel, et or spot XAU/USD
// Un actif sans source disponible reste « hors flux » : aucune alerte ne peut s'y déclencher.

const LS = 'pm.feed';
const DEFAULT_TD_SYMBOLS = { SP500: 'SPX', NASDAQ: 'NDX', OIL: 'WTI/USD', NATGAS: 'NG/USD', GOLD: 'XAU/USD' };
const KRAKEN = { BTC: 'XXBTZUSD', GOLD: 'PAXGUSD' };
const COINBASE = { EURUSD: c => 1 / +c.EUR, USDJPY: c => +c.JPY, USDCAD: c => +c.CAD };

// Délai au-delà duquel une cotation est considérée périmée (ms)
const STALE = { kraken: 90e3, coinbase: 5 * 60e3, twelvedata: 15 * 60e3 };
const LABEL = { kraken: 'Kraken', coinbase: 'Coinbase', twelvedata: 'Twelve Data' };

export function getFeedConfig() {
  try { return { tdKey: '', tdSymbols: { ...DEFAULT_TD_SYMBOLS }, ...JSON.parse(localStorage.getItem(LS) || '{}') }; }
  catch { return { tdKey: '', tdSymbols: { ...DEFAULT_TD_SYMBOLS } }; }
}
export function saveFeedConfig(patch) {
  const cfg = { ...getFeedConfig(), ...patch };
  try { localStorage.setItem(LS, JSON.stringify(cfg)); } catch { /* ignoré */ }
  return cfg;
}

/** quotes[id] = { price, chg, src, at, note } */
export const quotes = {};
export const errors = {};
const listeners = new Set();
export const onQuotes = fn => listeners.add(fn);

function dayOpen(id, price) {
  // Variation calculée depuis la première cotation reçue ce jour (UTC) quand la source ne fournit pas d'ouverture.
  const key = 'pm.open.' + id, today = new Date().toISOString().slice(0, 10);
  try {
    const o = JSON.parse(localStorage.getItem(key) || 'null');
    if (o && o.d === today) return o.p;
    localStorage.setItem(key, JSON.stringify({ d: today, p: price }));
  } catch { /* ignoré */ }
  return price;
}

function set(id, price, open, src, note) {
  if (!isFinite(price) || price <= 0) return;
  const prev = quotes[id];
  const changedAt = prev && prev.price === price && prev.src === src ? prev.changedAt : Date.now();
  quotes[id] = { price, chg: open ? (price / open - 1) * 100 : 0, src, at: Date.now(), changedAt, note };
  delete errors[id];
}

async function pollKraken() {
  const r = await fetch('https://api.kraken.com/0/public/Ticker?pair=XBTUSD,PAXGUSD');
  const j = await r.json();
  if (j.error?.length) throw new Error(j.error.join(', '));
  const t = j.result[KRAKEN.BTC]; if (t) set('BTC', +t.c[0], +t.o, 'kraken');
  const g = j.result[KRAKEN.GOLD];
  // XAU/USD de Twelve Data, s'il est frais, est prioritaire sur PAXG.
  if (g && !(quotes.GOLD?.src === 'twelvedata' && !isStale('GOLD'))) set('GOLD', +g.c[0], +g.o, 'kraken', 'PAXG/USD, proche de l’or spot');
}

async function pollCoinbase() {
  const r = await fetch('https://api.coinbase.com/v2/exchange-rates?currency=USD');
  const rates = (await r.json()).data.rates;
  for (const [id, f] of Object.entries(COINBASE)) { const p = f(rates); set(id, p, dayOpen(id, p), 'coinbase'); }
}

async function pollTwelve(cfg) {
  const ids = Object.keys(cfg.tdSymbols).filter(id => cfg.tdSymbols[id]);
  if (!ids.length) return;
  const syms = ids.map(id => cfg.tdSymbols[id]);
  const r = await fetch(`https://api.twelvedata.com/quote?symbol=${encodeURIComponent(syms.join(','))}&apikey=${encodeURIComponent(cfg.tdKey)}`);
  const j = await r.json();
  if (j.code && j.status === 'error') throw new Error(String(j.message).slice(0, 90));
  const one = syms.length === 1;
  ids.forEach((id, i) => {
    const q = one ? j : j[syms[i]];
    if (!q || q.status === 'error' || q.code) { errors[id] = `Twelve Data : ${String(q?.message || 'symbole indisponible').slice(0, 90)}`; return; }
    set(id, +q.close, +q.previous_close || +q.open, 'twelvedata', q.is_market_open === false ? 'marché fermé' : '');
  });
}

let started = false, tdTimer = null;
const emit = () => listeners.forEach(fn => { try { fn(quotes); } catch (e) { console.error(e); } });

async function safe(fn, ids) {
  try { await fn(); } catch (e) { ids.forEach(id => { if (!quotes[id] || isStale(id)) errors[id] = e.message || 'erreur réseau'; }); }
}

export async function refreshFast() {
  await Promise.all([safe(pollKraken, ['BTC', 'GOLD']), safe(pollCoinbase, Object.keys(COINBASE))]);
  emit();
}
export async function refreshTwelve() {
  const cfg = getFeedConfig();
  if (!cfg.tdKey) return;
  await safe(() => pollTwelve(cfg), Object.keys(cfg.tdSymbols));
  emit();
}

export function start() {
  if (started) return; started = true;
  refreshFast(); refreshTwelve();
  setInterval(refreshFast, 20e3);
  tdTimer = setInterval(refreshTwelve, 5 * 60e3); // offre gratuite : 8 crédits/min, 800/jour
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { refreshFast(); refreshTwelve(); } });
}
export function restartTwelve() {
  clearInterval(tdTimer); tdTimer = setInterval(refreshTwelve, 5 * 60e3);
  for (const id of Object.keys(DEFAULT_TD_SYMBOLS)) if (quotes[id]?.src === 'twelvedata') delete quotes[id];
  refreshTwelve(); refreshFast();
}

export function isStale(id) { const q = quotes[id]; return !q || Date.now() - q.at > STALE[q.src]; }
export function isLive(id) { return !!quotes[id] && !isStale(id); }

/** Texte d'état d'un actif pour l'interface */
export function status(id) {
  const q = quotes[id];
  if (!q) {
    if (errors[id]) return { live: false, text: errors[id] };
    const cfg = getFeedConfig();
    if (DEFAULT_TD_SYMBOLS[id] && !KRAKEN[id] && !cfg.tdKey) return { live: false, text: 'Aucun flux sans clé Twelve Data' };
    return { live: false, text: 'Connexion au flux…' };
  }
  const age = Math.round((Date.now() - q.at) / 1000);
  const ageTxt = age < 60 ? `il y a ${age} s` : `il y a ${Math.round(age / 60)} min`;
  const still = Math.round((Date.now() - q.changedAt) / 60e3);
  return { live: !isStale(id), text: `${LABEL[q.src]}${q.note ? ' · ' + q.note : ''} · ${ageTxt}${still >= 3 ? ` · inchangé depuis ${still} min` : ''}${isStale(id) ? ' · PÉRIMÉ' : ''}` };
}
export const SOURCES_INFO = DEFAULT_TD_SYMBOLS;
