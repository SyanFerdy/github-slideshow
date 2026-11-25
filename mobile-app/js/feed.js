// Flux de prix réels. Sources vérifiées depuis un navigateur (CORS autorisé) :
//  - Kraken (sans clé)      : BTC (XBT/USD), Or via PAXG/USD (jeton adossé à l'or, proche du spot)
//  - Coinbase (sans clé)    : EUR/USD, USD/JPY, USD/CAD (taux agrégés ; mesuré : mis à jour toutes les 2-3 min ou plus, retard possible de 2-3 pips)
//  - Twelve Data (clé)      : S&P 500, Nasdaq 100, pétrole WTI, gaz naturel, or spot XAU/USD et devises
//    (prioritaire sur Kraken/Coinbase tant que sa cotation est fraîche ; repli automatique sinon).
//    Offre gratuite : 8 crédits/min et 800/jour (1 crédit par symbole et par requête).
// Un actif sans source disponible reste « hors flux » : aucune alerte ne peut s'y déclencher.

const LS = 'pm.feed';
const DEFAULT_TD_SYMBOLS = { SP500: 'SPX', NASDAQ: 'NDX', OIL: 'WTI/USD', NATGAS: 'NG/USD', GOLD: 'XAU/USD', EURUSD: 'EUR/USD', USDJPY: 'USD/JPY', USDCAD: 'USD/CAD' };
const DEFAULTS = { tdKey: '', tdInterval: 2, tdOnlyAlerts: true, tdDaily: 780 };
const FULL_REFRESH_MS = 15 * 60e3; // relevé de tous les symboles (affichage) quand le mode économe est actif
const KRAKEN = { BTC: 'XXBTZUSD', GOLD: 'PAXGUSD' };
const COINBASE = { EURUSD: c => 1 / +c.EUR, USDJPY: c => +c.JPY, USDCAD: c => +c.CAD };

// Délai au-delà duquel une cotation est considérée périmée (ms)
const STALE = { kraken: 90e3, coinbase: 5 * 60e3, twelvedata: 20 * 60e3 };
const LABEL = { kraken: 'Kraken', coinbase: 'Coinbase', twelvedata: 'Twelve Data' };

export function getFeedConfig() {
  let saved = {};
  try { saved = JSON.parse(localStorage.getItem(LS) || '{}'); } catch { /* ignoré */ }
  // Fusion des symboles : une config enregistrée avant l'ajout des devises récupère leurs symboles par défaut.
  return { ...DEFAULTS, ...saved, tdSymbols: { ...DEFAULT_TD_SYMBOLS, ...(saved.tdSymbols || {}) } };
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

function set(id, price, open, src, note, maxAge) {
  if (!isFinite(price) || price <= 0) return;
  const prev = quotes[id];
  // Une cotation Twelve Data encore fraîche n'est pas écrasée par une source gratuite moins précise.
  if (src !== 'twelvedata' && prev?.src === 'twelvedata' && !isStale(id)) return;
  const changedAt = prev && prev.price === price && prev.src === src ? prev.changedAt : Date.now();
  quotes[id] = { price, chg: open ? (price / open - 1) * 100 : 0, src, at: Date.now(), changedAt, note, maxAge };
  delete errors[id];
}

async function pollKraken() {
  const r = await fetch('https://api.kraken.com/0/public/Ticker?pair=XBTUSD,PAXGUSD');
  const j = await r.json();
  if (j.error?.length) throw new Error(j.error.join(', '));
  const t = j.result[KRAKEN.BTC]; if (t) set('BTC', +t.c[0], +t.o, 'kraken');
  const g = j.result[KRAKEN.GOLD];
  if (g) set('GOLD', +g.c[0], +g.o, 'kraken', 'PAXG/USD, proche de l’or spot');
}

async function pollCoinbase() {
  const r = await fetch('https://api.coinbase.com/v2/exchange-rates?currency=USD');
  const rates = (await r.json()).data.rates;
  for (const [id, f] of Object.entries(COINBASE)) { const p = f(rates); set(id, p, dayOpen(id, p), 'coinbase'); }
}

/* ---- Budget de crédits Twelve Data ---- */
function credits() {
  const today = new Date().toISOString().slice(0, 10);
  try { const c = JSON.parse(localStorage.getItem('pm.tdCredits') || 'null'); if (c?.d === today) return c; } catch { /* ignoré */ }
  return { d: today, n: 0 };
}
function spend(n) { const c = credits(); c.n += n; try { localStorage.setItem('pm.tdCredits', JSON.stringify(c)); } catch { /* ignoré */ } }
export const creditsUsedToday = () => credits().n;

/** Estimation des heures de surveillance par jour avec le budget quotidien. */
export function coverageHours(cfg, alertedCount) {
  const n = Object.values(cfg.tdSymbols).filter(Boolean).length;
  const perHour = cfg.tdOnlyAlerts
    ? alertedCount * 60 / cfg.tdInterval + n * 60e3 * 60 / FULL_REFRESH_MS
    : n * 60 / cfg.tdInterval;
  return perHour ? cfg.tdDaily / perHour : Infinity;
}

let priorityFn = () => [];
/** Fonction renvoyant les actifs à surveiller en priorité (ceux qui ont une alerte active). */
export const setPriority = fn => { priorityFn = fn; };

async function pollTwelve(cfg, ids, maxAgeFor) {
  if (!ids.length) return;
  const c = credits();
  if (c.n + ids.length > cfg.tdDaily) {
    ids.forEach(id => { errors[id] = `Twelve Data : quota du jour atteint (${c.n}/${cfg.tdDaily}), repli sur la source gratuite`; });
    return;
  }
  const syms = ids.map(id => cfg.tdSymbols[id]);
  spend(ids.length);
  const r = await fetch(`https://api.twelvedata.com/quote?symbol=${encodeURIComponent(syms.join(','))}&apikey=${encodeURIComponent(cfg.tdKey)}`);
  const j = await r.json();
  if (j.code && j.status === 'error') throw new Error(String(j.message).slice(0, 90));
  const one = syms.length === 1;
  ids.forEach((id, i) => {
    const q = one ? j : j[syms[i]];
    if (!q || q.status === 'error' || q.code) { errors[id] = `Twelve Data : ${String(q?.message || 'symbole indisponible').slice(0, 90)}`; return; }
    set(id, +q.close, +q.previous_close || +q.open, 'twelvedata', q.is_market_open === false ? 'marché fermé' : '', maxAgeFor(id));
  });
}

let started = false, lastAlertPoll = 0, lastFullPoll = 0, tdBusy = false;
const emit = () => listeners.forEach(fn => { try { fn(quotes); } catch (e) { console.error(e); } });

async function safe(fn, ids) {
  try { await fn(); } catch (e) { ids.forEach(id => { if (!quotes[id] || isStale(id)) errors[id] = e.message || 'erreur réseau'; }); }
}

export async function refreshFast() {
  await Promise.all([safe(pollKraken, ['BTC', 'GOLD']), safe(pollCoinbase, Object.keys(COINBASE))]);
  emit();
}

/**
 * Appelé chaque minute. Mode économe : les actifs avec une alerte active sont relevés à chaque intervalle,
 * les autres seulement toutes les 15 min (pour l'affichage). Sinon tous les symboles à chaque intervalle.
 * Jamais plus de 8 symboles par requête (limite par minute de l'offre gratuite).
 */
export async function refreshTwelve(force = false) {
  const cfg = getFeedConfig();
  if (!cfg.tdKey || tdBusy || (document.hidden && !force)) return;
  // force === true : relevé complet ; force === 'prio' : seulement les actifs sous alerte (ex. alerte qui vient d'être créée).
  const now = Date.now(), every = cfg.tdInterval * 60e3;
  const all = Object.keys(cfg.tdSymbols).filter(id => cfg.tdSymbols[id]);
  const prio = cfg.tdOnlyAlerts ? all.filter(id => priorityFn().includes(id)) : all;
  const ids = new Set();
  if (force || now - lastAlertPoll >= every - 5e3) { prio.forEach(id => ids.add(id)); if (prio.length) lastAlertPoll = now; }
  if (force === true || now - lastFullPoll >= (cfg.tdOnlyAlerts ? FULL_REFRESH_MS : every) - 5e3) { all.forEach(id => ids.add(id)); lastFullPoll = now; lastAlertPoll = now; }
  const list = [...ids].slice(0, 8);
  if (!list.length) return;
  const alertAge = every * 2.5 + 60e3;
  const maxAgeFor = id => (prio.includes(id) || !cfg.tdOnlyAlerts) ? alertAge : FULL_REFRESH_MS + 5 * 60e3;
  tdBusy = true;
  try { await safe(() => pollTwelve(cfg, list, maxAgeFor), list); } finally { tdBusy = false; }
  emit();
}

export function start() {
  if (started) return; started = true;
  refreshFast(); refreshTwelve(true);
  setInterval(refreshFast, 20e3);
  setInterval(() => refreshTwelve(), 60e3);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) { refreshFast(); refreshTwelve(); } });
}
export function restartTwelve() {
  for (const id of Object.keys(DEFAULT_TD_SYMBOLS)) if (quotes[id]?.src === 'twelvedata') delete quotes[id];
  lastAlertPoll = lastFullPoll = 0;
  refreshTwelve(true); refreshFast();
}

export function isStale(id) { const q = quotes[id]; return !q || Date.now() - q.at > (q.maxAge || STALE[q.src]); }
export function isLive(id) { return !!quotes[id] && !isStale(id); }

/** Texte d'état d'un actif pour l'interface */
export function status(id) {
  const q = quotes[id];
  if (!q) {
    if (errors[id]) return { live: false, text: errors[id] };
    const cfg = getFeedConfig();
    if (DEFAULT_TD_SYMBOLS[id] && !KRAKEN[id] && !COINBASE[id] && !cfg.tdKey) return { live: false, text: 'Aucun flux sans clé Twelve Data' };
    return { live: false, text: 'Connexion au flux…' };
  }
  const age = Math.round((Date.now() - q.at) / 1000);
  const ageTxt = age < 60 ? `il y a ${age} s` : `il y a ${Math.round(age / 60)} min`;
  const still = Math.round((Date.now() - q.changedAt) / 60e3);
  return { live: !isStale(id), text: `${LABEL[q.src]}${q.note ? ' · ' + q.note : ''} · ${ageTxt}${still >= 3 ? ` · inchangé depuis ${still} min` : ''}${isStale(id) ? ' · PÉRIMÉ' : ''}` };
}
export const SOURCES_INFO = DEFAULT_TD_SYMBOLS;
