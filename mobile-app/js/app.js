import * as D from './data.js';
import * as AI from './claude.js';

/* =========================================================================
   État et persistance
   ========================================================================= */
const store = {
  get(k, d) { try { const v = localStorage.getItem('pm.' + k); return v ? JSON.parse(v) : d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem('pm.' + k, JSON.stringify(v)); } catch { /* ignoré */ } },
  del(k) { try { localStorage.removeItem('pm.' + k); } catch { /* ignoré */ } },
};

const state = {
  user: store.get('user', null),
  accounts: store.get('accounts', {}),
  bias: store.get('bias', structuredClone(D.BIAS)),
  biasMeta: store.get('biasMeta', { source: 'démo', at: null, summary: '' }),
  prices: Object.fromEntries(D.ASSETS.map(a => [a.id, { price: a.price, chg: a.chg }])),
  squawk: D.SQUAWK_SEED.map((s, i) => ({ ...s, id: 'seed' + i })),
  squawkFilter: 'ALL',
  unread: 0,
  chat: store.get('chat', []),
  prefs: store.get('prefs', { theme: 'dark', notif: true, live: true, billing: 'monthly', lang: 'fr' }),
  favorites: store.get('favorites', ['SP500', 'GOLD', 'EURUSD']),
  marketsTab: 'Tous',
  homeTab: 'events',
  streamIdx: 0,
  busy: false,
};
const save = () => {
  store.set('user', state.user); store.set('accounts', state.accounts); store.set('bias', state.bias);
  store.set('biasMeta', state.biasMeta); store.set('chat', state.chat.slice(-40)); store.set('prefs', state.prefs);
  store.set('favorites', state.favorites);
};

/* =========================================================================
   Utilitaires
   ========================================================================= */
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const vKey = v => v > 0 ? 'bull' : v < 0 ? 'bear' : 'neutral';
const vLabel = v => v > 0 ? 'Haussier' : v < 0 ? 'Baissier' : 'Neutre';
const vArrow = v => v > 0 ? '▲' : v < 0 ? '▼' : '◆';
const pill = (v, extra = '') => `<span class="pill bg-${vKey(v)}">${vArrow(v)} ${vLabel(v)}${extra}</span>`;
const fmt = (n, d) => n.toLocaleString('fr-FR', { minimumFractionDigits: d, maximumFractionDigits: d });
const decimals = id => ({ EURUSD: 4, USDCAD: 4, NATGAS: 3, USDJPY: 2, OIL: 2, BTC: 0 }[id] ?? 1);
const assetName = id => D.ASSETS.find(a => a.id === id)?.name || id;
const nowHM = () => new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
const flag = cc => ({ US: '🇺🇸', EU: '🇪🇺', JP: '🇯🇵', CN: '🇨🇳', UK: '🇬🇧', CA: '🇨🇦', AU: '🇦🇺', EM: '🌍', IR: '🇮🇷', SA: '🇸🇦', RU: '🇷🇺', DE: '🇩🇪' }[cc] || '🏳️');

function md(text) {
  const lines = esc(text).split('\n');
  let html = '', inList = false;
  const inline = s => s.replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').replace(/(^|[^*])\*(?!\s)(.+?)\*/g, '$1<i>$2</i>').replace(/`(.+?)`/g, '<code class="k">$1</code>');
  for (const raw of lines) {
    const l = raw.trim();
    const li = l.match(/^([-*•]|\d+[.)])\s+(.*)/);
    if (li) { if (!inList) { html += '<ul>'; inList = true; } html += `<li>${inline(li[2])}</li>`; continue; }
    if (inList) { html += '</ul>'; inList = false; }
    if (!l) continue;
    const h = l.match(/^#{1,4}\s+(.*)/);
    html += h ? `<p><b>${inline(h[1])}</b></p>` : `<p>${inline(l)}</p>`;
  }
  if (inList) html += '</ul>';
  return html;
}

function toast(msg) {
  document.querySelectorAll('.toast').forEach(t => t.remove());
  const t = document.createElement('div'); t.className = 'toast'; t.textContent = msg;
  $('#app').appendChild(t); setTimeout(() => t.remove(), 2600);
}

function sheet(html) {
  closeSheet();
  const bg = document.createElement('div'); bg.className = 'sheet-bg'; bg.onclick = closeSheet;
  const sh = document.createElement('div'); sh.className = 'sheet'; sh.innerHTML = `<div class="grab"></div>${html}`;
  $('#app').append(bg, sh);
  return sh;
}
function closeSheet() { document.querySelectorAll('.sheet, .sheet-bg').forEach(e => e.remove()); }

async function sha256(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');
}

/* =========================================================================
   Icônes
   ========================================================================= */
const P = {
  home: '<path d="M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  chart: '<path d="M3 3v18h18"/><path d="M7 14l4-4 3 3 6-6"/>',
  spark: '<path d="M12 2l2.4 7.6L22 12l-7.6 2.4L12 22l-2.4-7.6L2 12l7.6-2.4z"/>',
  radio: '<circle cx="12" cy="12" r="2"/><path d="M16.2 7.8a6 6 0 0 1 0 8.4M7.8 16.2a6 6 0 0 1 0-8.4M19 5a10 10 0 0 1 0 14M5 19A10 10 0 0 1 5 5"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  back: '<path d="M15 18l-6-6 6-6"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  key: '<circle cx="7.5" cy="15.5" r="4.5"/><path d="M10.7 12.3L21 2M17 6l3 3M15 8l2 2"/>',
  bell: '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/>',
  compass: '<circle cx="12" cy="12" r="10"/><path d="M16.2 7.8l-2.1 6.3-6.3 2.1 2.1-6.3z"/>',
  layers: '<path d="M12 2L2 7l10 5 10-5z"/><path d="M2 17l10 5 10-5M2 12l10 5 10-5"/>',
  doc: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M8 13h8M8 17h5"/>',
  cal: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
  gauge: '<path d="M12 14l4-4"/><path d="M3.3 19a10 10 0 1 1 17.4 0"/>',
  globe: '<circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15 15 0 0 1 0 20M12 2a15 15 0 0 0 0 20"/>',
  bars: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
  users: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/>',
  percent: '<path d="M19 5L5 19"/><circle cx="6.5" cy="6.5" r="2.5"/><circle cx="17.5" cy="17.5" r="2.5"/>',
  bank: '<path d="M3 21h18M5 21V10M19 21V10M9 21V10M15 21V10M12 3L2 9h20z"/>',
  target: '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/>',
  chat: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  star: '<path d="M12 2l3.1 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.8 21l1.2-6.8-5-4.9 6.9-1z"/>',
  tag: '<path d="M20.6 13.4l-7.2 7.2a2 2 0 0 1-2.8 0L2 12V2h10l8.6 8.6a2 2 0 0 1 0 2.8z"/><circle cx="7" cy="7" r="1.5"/>',
  term: '<path d="M4 17l6-6-6-6M12 19h8"/>',
  send: '<path d="M22 2L11 13M22 2l-7 20-4-9-9-4z"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>',
  out: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  refresh: '<path d="M23 4v6h-6M1 20v-6h6"/><path d="M3.5 9a9 9 0 0 1 14.9-3.4L23 10M1 14l4.6 4.4A9 9 0 0 0 20.5 15"/>',
  trend: '<path d="M23 6l-9.5 9.5-5-5L1 18"/><path d="M17 6h6v6"/>',
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
};
const icon = (n, cls = '') => `<svg class="${cls}" viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${P[n] || ''}</svg>`;
const logo = `<svg class="logo" viewBox="0 0 64 64"><defs><linearGradient id="lg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6cc7ff"/><stop offset="1" stop-color="#a58bff"/></linearGradient></defs><path d="M32 6 L37 27 L58 32 L37 37 L32 58 L27 37 L6 32 L27 27 Z" fill="url(#lg)"/></svg>`;

/* =========================================================================
   Routage
   ========================================================================= */
const TABS = [
  ['home', 'Accueil', 'home'], ['markets', 'Marchés', 'chart'], ['ai', 'IA', 'spark'], ['squawk', 'Squawk', 'radio'], ['more', 'Plus', 'grid'],
];
const PUBLIC = ['welcome', 'login', 'signup', 'forgot', 'magic', 'pricing', 'legal'];

function route() {
  const h = location.hash.replace(/^#\/?/, '') || (state.user ? 'home' : 'welcome');
  const [name, ...args] = h.split('/');
  if (name === 'settings' && args[0] === 'api') return { name: 'api', args: [] };
  return { name, args: args.map(decodeURIComponent) };
}
const go = (path) => { location.hash = '#/' + path; };

const SCREENS = {};
function screen(name, title, fn, opts = {}) { SCREENS[name] = { title, fn, ...opts }; }

function render() {
  const r = route();
  let s = SCREENS[r.name];
  if (!s) { go(state.user ? 'home' : 'welcome'); return; }
  if (!state.user && !PUBLIC.includes(r.name)) { go('welcome'); return; }
  if (state.user && ['welcome', 'login', 'signup', 'magic', 'forgot'].includes(r.name)) { go('home'); return; }

  document.documentElement.dataset.theme = state.prefs.theme;
  const tab = s.tab ?? r.name;
  const showTabs = !!state.user && !s.noTabs;
  const connected = AI.isConnected();
  const title = typeof s.title === 'function' ? s.title(...r.args) : s.title;
  const isRoot = TABS.some(t => t[0] === r.name);

  const top = s.bare ? '' : `
    <header class="topbar">
      ${isRoot || !state.user ? logo : `<button class="icon-btn" data-back aria-label="Retour">${icon('back')}</button>`}
      <h1>${esc(title)}</h1>
      ${state.user ? `
        <button class="icon-btn" data-go="settings/api" aria-label="Clé API Claude" title="Clé API Claude">${icon('key')}<i class="dot ${connected ? 'ok' : ''}"></i></button>
        <button class="icon-btn" data-go="settings" aria-label="Réglages">${icon('gear')}</button>` :
        `<button class="btn small" data-go="login">Se connecter</button>`}
    </header>`;

  const tabs = showTabs ? `<nav class="tabbar">${TABS.map(([id, label, ic]) => `
      <button data-go="${id}" class="${tab === id ? 'on' : ''} ${id === 'ai' ? 'ai' : ''}">${icon(ic)}<span>${label}${id === 'squawk' && state.unread ? ` (${state.unread})` : ''}</span></button>`).join('')}</nav>` : '';

  $('#app').innerHTML = `${top}<main class="screen-enter ${showTabs ? '' : 'no-tabs'}" id="main">${s.fn(...r.args)}</main>${tabs}${s.after ? s.after(...r.args) : ''}`;
  if (r.name === 'squawk') { state.unread = 0; }
  s.mount?.(...r.args);
}

/* Délégation d'événements globale */
document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-go],[data-back],[data-act]');
  if (!el) return;
  if (el.dataset.go !== undefined) { e.preventDefault(); closeSheet(); go(el.dataset.go); }
  else if (el.dataset.back !== undefined) { history.length > 1 ? history.back() : go('home'); }
  else if (el.dataset.act) { if (el.tagName !== 'INPUT') e.preventDefault(); ACTIONS[el.dataset.act]?.(el, e); }
});
window.addEventListener('hashchange', render);

/* =========================================================================
   Composants
   ========================================================================= */
function gauge(conv, v) {
  const c = 2 * Math.PI * 52, off = c * (1 - conv / 100);
  const col = `var(--${vKey(v)})`;
  return `<div class="gauge"><svg width="120" height="120"><circle cx="60" cy="60" r="52" stroke="var(--card-2)" stroke-width="10" fill="none"/>
    <circle cx="60" cy="60" r="52" stroke="${col}" stroke-width="10" fill="none" stroke-linecap="round" stroke-dasharray="${c}" stroke-dashoffset="${off}"/></svg>
    <div class="val" style="color:${col}">${conv}%</div></div>`;
}

function assetTile(a) {
  const b = state.bias[a.id], p = state.prices[a.id];
  return `<div class="card tap asset-tile" data-go="asset/${a.id}">
    <div class="row between"><span class="sym">${a.id}</span><span class="small muted">${esc(a.cls)}</span></div>
    <div class="price mono"><span data-price="${a.id}">${fmt(p.price, decimals(a.id))}</span>
      <span data-chg="${a.id}" class="small ${p.chg >= 0 ? 'v-bull' : 'v-bear'}">${p.chg >= 0 ? '+' : ''}${fmt(p.chg, 2)} %</span></div>
    <div class="verdict"><span class="small v-${vKey(b.v)}" style="font-weight:700">${vArrow(b.v)} ${vLabel(b.v)}</span><b class="small">${b.conv}%</b></div>
    <div class="bar" style="margin-top:6px"><span style="width:${b.conv}%;background:var(--${vKey(b.v)})"></span></div>
  </div>`;
}

function squawkItem(s, isNew = false) {
  return `<div class="card squawk ${isNew ? 'new' : ''}" data-id="${s.id}">
    <div class="time mono">${s.t}</div>
    <div class="body">
      <div class="row" style="gap:6px"><span>${flag(s.cc)}</span><span class="sev sev-${s.sev}">${s.sev}</span></div>
      <p>${esc(s.text)}</p>
      <div class="row between"><div>${s.assets.map(a => `<span class="chip">${a}</span>`).join('')}</div>
      <button class="btn small" data-act="squawkAI" data-id="${s.id}">${icon('spark').replace('<svg', '<svg width="14" height="14"')} Impact</button></div>
    </div></div>`;
}

function biasSummary() {
  const vals = Object.values(state.bias);
  const n = v => vals.filter(b => Math.sign(b.v) === v).length;
  return `${n(1)} haussiers · ${n(-1)} baissiers · ${n(0)} neutre${n(0) > 1 ? 's' : ''}`;
}

function needKeyCard(what = 'cette fonctionnalité') {
  return `<div class="notice">${icon('key').replace('<svg', '<svg width="16" height="16" style="vertical-align:-3px"')}
    Connectez votre clé API Claude pour activer ${what}. <button class="link" data-go="settings/api">Configurer la clé →</button></div>`;
}

function aiBox(id, label = 'Analyse par Claude') {
  return `<div class="card" id="${id}" hidden><div class="row" style="margin-bottom:8px">${icon('spark').replace('<svg', '<svg width="16" height="16" style="color:var(--accent)"')}<b class="small">${label}</b></div><div class="ai-out typing"></div></div>`;
}

/** Lance une génération en streaming dans un conteneur (id) */
async function streamInto(id, prompt, { useWeb = false, system = AI.SYSTEM_ANALYST } = {}) {
  if (!AI.isConnected()) { promptConnect(); return; }
  const box = document.getElementById(id); if (!box) return;
  box.hidden = false;
  const out = box.querySelector('.ai-out'); out.classList.add('typing'); out.innerHTML = '';
  let acc = '';
  try {
    await AI.streamChat({ system, history: [{ role: 'user', content: prompt }], useWeb,
      onText: t => { acc += t; const o = document.getElementById(id)?.querySelector('.ai-out'); if (o) o.innerHTML = md(acc); } });
  } catch (err) {
    acc = '⚠️ ' + err.message;
    const o = document.getElementById(id)?.querySelector('.ai-out'); if (o) o.innerHTML = `<p class="v-bear">${esc(acc)}</p>`;
  }
  document.getElementById(id)?.querySelector('.ai-out')?.classList.remove('typing');
  return acc;
}

function promptConnect() {
  sheet(`<h2 style="margin-top:0">Connecter Claude</h2>
    <p class="muted">Les analyses IA, le chat et la mise à jour des biais utilisent l’API Claude avec votre propre clé.</p>
    <button class="btn primary block" data-go="settings/api">${icon('key')} Ajouter ma clé API</button>`);
}

function marketContext() {
  const bias = D.ASSETS.map(a => { const b = state.bias[a.id]; return `${a.id}: ${vLabel(b.v)} ${b.conv}% (${b.drivers.slice(0, 2).join('; ')})`; }).join('\n');
  const sq = state.squawk.slice(0, 6).map(s => `[${s.t} ${s.cc} ${s.sev}] ${s.text}`).join('\n');
  const regimes = D.REGIMES.map(r => `${r.zone} ${r.label}`).join(', ');
  return `Date : ${new Date().toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}\n` +
    `Biais affichés dans l'app (source : ${state.biasMeta.source}) :\n${bias}\n\nDerniers squawks :\n${sq}\n\nRégimes macro : ${regimes}`;
}

/* =========================================================================
   Écrans publics : présentation, connexion, inscription
   ========================================================================= */
screen('welcome', D.BRAND.name, () => `
  <section class="hero">
    <span class="pill bg-accent">${icon('spark').replace('<svg', '<svg width="12" height="12"')} Propulsé par Claude</span>
    <h2>Anticipez les marchés avant qu’ils ne bougent.</h2>
    <p>Quand un choc macro tombe, l’IA vous dit de quel côté le marché penche : haussier ou baissier. La décision reste la vôtre.</p>
    <div class="stack"><button class="btn primary block" data-go="signup">Commencer gratuitement</button>
    <button class="btn block" data-act="demo">Voir la démo</button></div>
    <p class="small" style="margin:12px 0 0">Essai gratuit de 7 jours · rappel avant la fin · annulation en un clic</p>
  </section>

  <h2>6 onglets ouverts pour analyser un seul trade</h2>
  <div class="card"><div>${['Twitter/X', 'TradingView', 'Bloomberg', 'FXStreet', 'Telegram', 'Excel'].map(t => `<span class="chip">${t}</span>`).join('')}</div>
  <div class="hr"></div><b>Tout au même endroit, en moins d’une seconde.</b></div>

  <h2>Aucun choc macro ne vous échappe</h2>
  <div class="grid-4">${D.REGIMES.map(r => `<div class="regime"><b>${flag(r.zone)} ${r.zone}</b><span class="v-${vKey(r.tone)}">${r.label}</span></div>`).join('')}</div>

  <h2>9 marchés suivis 24h/24</h2>
  <div class="grid-3">${D.ASSETS.map(a => `<div class="regime"><b>${a.id}</b><span class="muted">${a.cls}</span></div>`).join('')}</div>

  <h2>L’IA qui lit les marchés avant tout le monde</h2>
  <div class="stack">
    <div class="card"><span class="pill bg-accent">01</span> <b>Squawk en temps réel</b><p class="muted small">L’info macro avant tout le monde, avec sévérité et actifs impactés.</p></div>
    <div class="card"><span class="pill bg-accent">02</span> <b>Biais directionnel</b><p class="muted small">9 actifs. Un verdict. Chaque jour. ${biasSummary()}.</p></div>
    <div class="card"><span class="pill bg-accent">03</span> <b>Analyse approfondie</b><p class="muted small">Chaque verdict avec son pourquoi : macro, fondamental, géopolitique, quantitatif.</p></div>
  </div>

  <h2>Votre avantage en 4 moments</h2>
  <div class="card timeline">${D.WORKFLOW.map(w => `<div class="step"><b class="mono small">${w.t}</b> · <b>${w.title}</b><div class="small muted">${w.text}</div></div>`).join('')}</div>

  <h2>Analyse manuelle vs ${D.BRAND.name}</h2>
  ${comparisonTable()}

  <h2>Retours de nos bêta-testeurs</h2>
  <p class="muted small" style="margin-top:-4px"><span class="stars">★★★★☆</span> 4,4/5</p>
  ${testimonials()}

  <div class="card glow" style="margin-top:20px;text-align:center"><h3>Rejoignez les traders qui anticipent les marchés</h3>
    <div class="grid-2" style="margin-top:12px"><button class="btn primary" data-go="signup">Commencer</button><button class="btn" data-go="pricing">Voir les offres</button></div></div>
  ${footer()}
`, { noTabs: true });

function comparisonTable() {
  return `<div class="card scroll-x"><table class="tbl"><tr><th></th><th>Manuel</th><th style="color:var(--accent)">${D.BRAND.name}</th></tr>
    ${D.COMPARISON.map(r => `<tr><td class="small muted">${r[0]}</td><td class="small">${r[1]}</td><td class="small"><b>${r[2]}</b></td></tr>`).join('')}</table></div>`;
}
function testimonials() {
  return D.TESTIMONIALS.map(t => `<div class="card"><div class="row between"><div><b>${t.name}</b> <span class="muted small">${t.handle}</span></div><span class="chip">${t.style}</span></div>
    <div class="stars small">${'★'.repeat(t.stars)}${'☆'.repeat(5 - t.stars)}</div><p class="small" style="margin:6px 0 0">${esc(t.text)}</p></div>`).join('');
}
function footer() {
  return `<p class="disclaimer">${D.BRAND.tagline}.<br>Les lectures fournies sont informatives et ne constituent pas un conseil en investissement.<br>
    <button class="link small" data-go="legal">Mentions légales et CGU</button> · <button class="link small" data-go="pricing">Tarifs</button></p>`;
}

screen('login', 'Connexion', () => `
  <div class="auth">
    <div class="brand">${logo.replace('class="logo"', '')}<h1>${D.BRAND.name}</h1><p class="muted">Terminal macro propulsé par l’IA</p></div>
    <div class="seg" style="margin-bottom:16px"><button class="on" data-act="loginMode" data-mode="pwd">Mot de passe</button><button data-act="loginMode" data-mode="magic">Magic Link</button></div>
    <form id="loginForm">
      <label class="field"><span>Adresse e-mail</span><input class="input" type="email" name="email" required autocomplete="email"></label>
      <label class="field" id="pwdField"><span>Mot de passe</span><input class="input" type="password" name="password" autocomplete="current-password"></label>
      <div style="text-align:right;margin:-4px 0 14px" id="forgotLink"><button type="button" class="link" data-go="forgot">Mot de passe oublié ?</button></div>
      <button class="btn primary block" type="submit" id="loginBtn">Se connecter</button>
    </form>
    <p class="small muted" style="text-align:center;margin-top:18px">Pas encore de compte ? <button class="link" data-go="signup">Créer un compte</button></p>
    <p class="small" style="text-align:center"><button class="link" data-act="demo">Explorer la démo sans compte</button></p>
  </div>`, {
  noTabs: true, bare: true,
  mount() {
    let mode = 'pwd';
    ACTIONS.loginMode = (el) => {
      mode = el.dataset.mode;
      document.querySelectorAll('[data-act=loginMode]').forEach(b => b.classList.toggle('on', b === el));
      $('#pwdField').hidden = $('#forgotLink').hidden = mode === 'magic';
      $('#loginBtn').textContent = mode === 'magic' ? 'Recevoir le lien magique' : 'Se connecter';
    };
    $('#loginForm').onsubmit = async (e) => {
      e.preventDefault();
      const f = new FormData(e.target), email = f.get('email').trim().toLowerCase();
      const acc = state.accounts[email];
      if (mode === 'magic') {
        if (!acc) return toast('Aucun compte pour cette adresse.');
        sheet(`<h2 style="margin-top:0">Vérifiez votre boîte mail</h2><p class="muted">Un lien de connexion a été envoyé à <b>${esc(email)}</b>.</p>
          <p class="small muted">Version démo : aucun e-mail n’est réellement envoyé.</p><button class="btn primary block" data-act="magicOpen" data-email="${esc(email)}">Ouvrir le lien (démo)</button>`);
        return;
      }
      if (!acc || acc.hash !== await sha256(f.get('password'))) return toast('E-mail ou mot de passe incorrect.');
      login(acc);
    };
  },
});

screen('signup', 'Créer un compte', () => `
  <div class="auth">
    <div class="brand">${logo.replace('class="logo"', '')}<h1>Créez votre compte</h1><p class="muted">7 jours d’essai gratuit</p></div>
    <form id="signupForm">
      <label class="field"><span>Adresse e-mail</span><input class="input" type="email" name="email" required autocomplete="email"></label>
      <label class="field"><span>Mot de passe (8 caractères min.)</span><input class="input" type="password" name="password" minlength="8" required autocomplete="new-password"></label>
      <label class="field"><span>Pays</span><select class="input" name="country" required><option value="">Sélectionner un pays…</option>${D.COUNTRY_LIST.map(c => `<option>${c}</option>`).join('')}</select></label>
      <label class="field"><span>Code parrain (facultatif)</span><input class="input" name="referral" autocomplete="off"></label>
      <label class="check"><input type="checkbox" name="optin"> Recevoir les nouveautés, conseils et offres. Désabonnement possible à tout moment.</label>
      <button class="btn primary block" type="submit">Créer mon compte</button>
    </form>
    <p class="small muted" style="text-align:center;margin-top:18px">Déjà un compte ? <button class="link" data-go="login">Se connecter</button></p>
  </div>`, {
  noTabs: true, bare: true,
  mount() {
    $('#signupForm').onsubmit = async (e) => {
      e.preventDefault();
      const f = new FormData(e.target), email = f.get('email').trim().toLowerCase();
      if (state.accounts[email]) return toast('Un compte existe déjà pour cette adresse.');
      const acc = { email, hash: await sha256(f.get('password')), country: f.get('country'), referral: f.get('referral') || '',
        optin: !!f.get('optin'), plan: 'pro', trialEnds: Date.now() + 7 * 864e5, createdAt: Date.now() };
      state.accounts[email] = acc; login(acc); toast('Bienvenue ! Votre essai de 7 jours commence.');
    };
  },
});

screen('forgot', 'Mot de passe oublié', () => `
  <div class="auth"><h2>Réinitialiser le mot de passe</h2><p class="muted">Saisissez votre adresse : nous vous enverrons un lien de réinitialisation.</p>
  <label class="field"><span>Adresse e-mail</span><input class="input" type="email" id="fEmail"></label>
  <button class="btn primary block" data-act="forgotSend">Envoyer le lien</button>
  <p style="text-align:center"><button class="link" data-go="login">Retour à la connexion</button></p></div>`, { noTabs: true, bare: true });

function login(acc) {
  state.user = { email: acc.email, country: acc.country, plan: acc.plan, trialEnds: acc.trialEnds, demo: !!acc.demo };
  save(); go('home');
}

/* =========================================================================
   Accueil / dashboard
   ========================================================================= */
screen('home', 'Tableau de bord', () => {
  const fav = D.ASSETS.filter(a => state.favorites.includes(a.id));
  const daysLeft = state.user?.trialEnds ? Math.max(0, Math.ceil((state.user.trialEnds - Date.now()) / 864e5)) : 0;
  const t = state.homeTab;
  return `
  ${!AI.isConnected() ? `<div class="card glow tap" data-go="settings/api" style="margin-bottom:12px"><div class="row">${icon('key')}<div style="flex:1"><b>Connectez Claude</b><div class="small muted">Ajoutez votre clé API pour activer l’analyse IA en direct.</div></div>›</div></div>` : ''}
  <div class="card glow">
    <div class="row between"><span class="small muted">Biais du jour · ${state.biasMeta.source === 'claude' ? 'généré par Claude' : 'démo'}${state.biasMeta.at ? ' · ' + new Date(state.biasMeta.at).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : ''}</span>
      ${state.user?.demo ? '<span class="chip">Démo</span>' : daysLeft ? `<span class="chip">Essai : ${daysLeft} j</span>` : ''}</div>
    <h2 style="margin:6px 0 4px">${biasSummary()}</h2>
    ${state.biasMeta.summary ? `<p class="small" style="margin:4px 0 10px">${esc(state.biasMeta.summary)}</p>` : ''}
    <div class="grid-2" style="margin-top:10px"><button class="btn small" data-go="bias">Voir les 9 verdicts</button>
      <button class="btn small primary" data-act="refreshBias" id="refreshBtn">${icon('refresh').replace('<svg', '<svg width="14" height="14"')} Actualiser via Claude</button></div>
  </div>

  <div class="section-title"><h2>Mes actifs</h2><button class="link" data-go="markets">Tout voir</button></div>
  <div class="grid-2">${fav.map(assetTile).join('') || '<p class="muted small">Ajoutez des favoris depuis la fiche d’un actif.</p>'}</div>

  <div class="section-title"><h2>Couverture macro</h2><span class="live">LIVE</span></div>
  <div class="seg" style="margin-bottom:10px">${[['events', 'Événements'], ['macro', 'Macro'], ['fx', 'Devises']].map(([k, l]) => `<button class="${t === k ? 'on' : ''}" data-act="homeTab" data-tab="${k}">${l}</button>`).join('')}</div>
  ${t === 'events' ? state.squawk.slice(0, 3).map(s => squawkItem(s)).join('') + `<button class="btn block small" style="margin-top:10px" data-go="squawk">Tout le flux</button>` : ''}
  ${t === 'macro' ? `<div class="grid-4">${D.REGIMES.map(r => `<div class="regime"><b>${flag(r.zone)} ${r.zone}</b><span class="v-${vKey(r.tone)}">${r.label}</span></div>`).join('')}</div>` : ''}
  ${t === 'fx' ? `<div class="card">${D.CURRENCIES.map(c => `<div class="row between" style="padding:8px 0"><b>${c.pair}</b>${pill(c.v)}</div>`).join('')}</div>` : ''}

  <div class="section-title"><h2>Pilote macro</h2><button class="link" data-go="drivers">Découvrir</button></div>
  <div class="card tap" data-go="drivers">${D.DRIVERS.slice(0, 3).map(d => `<div style="margin-bottom:10px"><div class="row between small"><b>${esc(d.topic)}</b><b>${d.w}%</b></div>
    <div class="bar"><span style="width:${d.w * 2.5}%;background:var(--accent)"></span></div></div>`).join('')}</div>

  <div class="section-title"><h2>Votre journée</h2></div>
  <div class="card timeline">${D.WORKFLOW.map(w => `<div class="step"><b class="mono small">${w.t}</b> · <b class="small">${w.title}</b><div class="small muted">${w.text}</div></div>`).join('')}</div>
  <p class="disclaimer">Lecture informative uniquement. Vous gardez la décision.</p>`;
}, {
  mount() {
    ACTIONS.homeTab = (el) => { state.homeTab = el.dataset.tab; render(); };
  },
});

/* =========================================================================
   Biais directionnel (9 verdicts)
   ========================================================================= */
screen('bias', 'Biais directionnel', () => `
  <div class="card glow"><h2 style="margin:0 0 4px">9 actifs. Un verdict. Chaque jour.</h2><p class="small muted" style="margin:0">${biasSummary()} · source : ${state.biasMeta.source}</p>
    <button class="btn small primary" style="margin-top:10px" data-act="refreshBias" id="refreshBtn">${icon('refresh').replace('<svg', '<svg width="14" height="14"')} Actualiser via Claude</button></div>
  ${D.ASSETS.map(a => { const b = state.bias[a.id]; return `<div class="card tap" data-go="asset/${a.id}"><div class="row between"><div><b>${a.id}</b> <span class="small muted">${esc(a.name)}</span></div>${pill(b.v, ` ${b.conv}%`)}</div>
    <div class="small muted" style="margin-top:6px">${esc(b.drivers[0] || '')}</div></div>`; }).join('')}
  <p class="disclaimer">À titre d’information uniquement. Vous gardez la décision.</p>`, { tab: 'home' });

/* =========================================================================
   Marchés et fiche actif
   ========================================================================= */
screen('markets', 'Marchés', () => {
  const classes = ['Tous', ...new Set(D.ASSETS.map(a => a.cls))];
  const list = D.ASSETS.filter(a => state.marketsTab === 'Tous' || a.cls === state.marketsTab);
  return `<div class="suggests" style="margin-bottom:12px">${classes.map(c => `<button class="btn small ${state.marketsTab === c ? 'primary' : ''}" data-act="mktTab" data-c="${c}">${c}</button>`).join('')}</div>
    <div class="grid-2">${list.map(assetTile).join('')}</div>
    <div class="section-title"><h2>Vue d’ensemble par classe</h2></div>
    ${[...new Set(D.ASSETS.map(a => a.cls))].map(c => { const as = D.ASSETS.filter(a => a.cls === c); const avg = Math.round(as.reduce((s, a) => s + state.bias[a.id].v * state.bias[a.id].conv, 0) / as.length);
      return `<div class="card"><div class="row between"><b>${c}</b>${pill(Math.sign(avg), ` ${Math.abs(avg)}`)}</div><div class="small muted" style="margin-top:4px">${as.map(a => a.id).join(' · ')}</div></div>`; }).join('')}`;
}, { mount() { ACTIONS.mktTab = el => { state.marketsTab = el.dataset.c; render(); }; } });

const ANGLES = [['macro', 'Macroéconomique'], ['fonda', 'Fondamental'], ['geo', 'Géopolitique'], ['quant', 'Quantitatif']];
screen('asset', id => id, (id) => {
  const a = D.ASSETS.find(x => x.id === id); if (!a) return '<div class="empty">Actif introuvable.</div>';
  const b = state.bias[id], p = state.prices[id], fav = state.favorites.includes(id);
  const seas = D.SEASONALITY[id];
  return `
  <div class="card"><div class="row between"><div><div class="small muted">${esc(a.cls)}</div><h2 style="margin:2px 0">${esc(a.name)}</h2></div>
    <button class="icon-btn" data-act="fav" data-id="${id}" aria-label="Favori" style="color:${fav ? 'var(--neutral)' : 'inherit'}">${icon('star')}</button></div>
    <div class="mono" style="font-size:24px;font-weight:800"><span data-price="${id}">${fmt(p.price, decimals(id))}</span>
      <span data-chg="${id}" class="small ${p.chg >= 0 ? 'v-bull' : 'v-bear'}">${p.chg >= 0 ? '+' : ''}${fmt(p.chg, 2)} %</span></div>
    <canvas id="spark" height="70" style="width:100%;margin-top:8px"></canvas></div>

  <div class="card" style="text-align:center"><div class="small muted">Verdict du jour</div>${gauge(b.conv, b.v)}
    <div style="margin-top:8px">${pill(b.v, ' · conviction ' + b.conv + '%')}</div></div>

  <div class="section-title"><h2>Chaque verdict, avec le pourquoi</h2></div>
  <div class="grid-2">${ANGLES.map(([k, l]) => `<div class="card"><div class="small muted">${l}</div><b class="v-${vKey(b.angles[k])}">${vArrow(b.angles[k])} ${vLabel(b.angles[k])}</b></div>`).join('')}</div>
  <div class="card"><h3>Drivers</h3><ul style="margin:0;padding-left:18px">${b.drivers.map(d => `<li class="small" style="margin:4px 0">${esc(d)}</li>`).join('')}</ul>
    <div class="hr"></div><div class="small"><b class="v-bear">Risque clé :</b> ${esc(b.risk)}</div></div>

  ${seas ? `<div class="section-title"><h2>Saisonnalité</h2></div><div class="card">${seasonBars(seas)}</div>` : ''}

  <div class="section-title"><h2>Analyse IA</h2></div>
  ${AI.isConnected() ? '' : needKeyCard('l’analyse approfondie')}
  <div class="grid-2" style="margin-top:10px"><button class="btn primary" data-act="assetAI" data-id="${id}">${icon('spark').replace('<svg', '<svg width="16" height="16"')} Analyse approfondie</button>
    <button class="btn" data-act="askAbout" data-id="${id}">${icon('chat').replace('<svg', '<svg width="16" height="16"')} Poser une question</button></div>
  <div style="margin-top:10px">${aiBox('assetAiBox', `Analyse ${id} par Claude`)}</div>
  <p class="disclaimer">À titre d’information uniquement. Vous gardez la décision.</p>`;
}, {
  tab: 'markets',
  mount(id) {
    const cv = $('#spark'); if (!cv) return;
    // Série intrajournalière simulée, reconstruite à rebours depuis le dernier prix.
    const end = state.prices[id].price, start = end / (1 + state.prices[id].chg / 100);
    const pts = []; let noise = 0, seed = id.length * 97;
    for (let i = 0; i <= 60; i++) {
      seed = (seed * 9301 + 49297) % 233280; noise += ((seed / 233280) - 0.5) * 0.004;
      const t = i / 60; pts.push((start + (end - start) * t) * (1 + noise * Math.sin(Math.PI * t)));
    }
    const dpr = devicePixelRatio || 1, w = cv.clientWidth, h = 70; cv.width = w * dpr; cv.height = h * dpr;
    const ctx = cv.getContext('2d'); ctx.scale(dpr, dpr);
    const mn = Math.min(...pts), mx = Math.max(...pts);
    const col = getComputedStyle(document.documentElement).getPropertyValue(state.prices[id].chg >= 0 ? '--bull' : '--bear').trim();
    ctx.beginPath(); pts.forEach((p, i) => { const x = i / (pts.length - 1) * w, y = h - 4 - (p - mn) / (mx - mn || 1) * (h - 8); i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); });
    ctx.strokeStyle = col; ctx.lineWidth = 2; ctx.stroke();
    ctx.lineTo(w, h); ctx.lineTo(0, h); ctx.closePath(); ctx.globalAlpha = .12; ctx.fillStyle = col; ctx.fill();
  },
});

function seasonBars(vals) {
  const m = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'], cur = new Date().getMonth();
  const mx = Math.max(...vals.map(Math.abs));
  return `<div style="display:flex;align-items:center;gap:4px;height:110px">${vals.map((v, i) => `<div style="flex:1;display:flex;flex-direction:column;align-items:center;height:100%">
    <div style="flex:1;display:flex;align-items:flex-end;width:100%"><div style="width:100%;height:${v > 0 ? v / mx * 100 : 0}%;background:var(--bull);border-radius:3px 3px 0 0;${i === cur ? 'outline:2px solid var(--accent)' : ''}"></div></div>
    <div style="flex:1;width:100%"><div style="width:100%;height:${v < 0 ? -v / mx * 100 : 0}%;background:var(--bear);border-radius:0 0 3px 3px"></div></div>
    <span class="small muted" style="${i === cur ? 'color:var(--accent);font-weight:800' : ''}">${m[i]}</span></div>`).join('')}</div>
    <p class="small muted" style="margin:6px 0 0">Performance moyenne mensuelle sur 15 ans (%). Mois en cours encadré.</p>`;
}

/* =========================================================================
   Squawk temps réel
   ========================================================================= */
screen('squawk', 'Squawk temps réel', () => {
  const filters = ['ALL', 'CRITIQUE', ...D.ASSETS.map(a => a.id)];
  const list = state.squawk.filter(s => state.squawkFilter === 'ALL' || s.sev === state.squawkFilter || s.assets.includes(state.squawkFilter));
  return `<div class="row between" style="margin-bottom:10px"><span class="live">${state.prefs.live ? 'EN DIRECT' : 'EN PAUSE'}</span>
      <button class="btn small" data-act="toggleLive">${state.prefs.live ? 'Pause' : 'Reprendre'}</button></div>
    <div class="suggests" style="margin-bottom:10px">${filters.map(f => `<button class="btn small ${state.squawkFilter === f ? 'primary' : ''}" data-act="sqFilter" data-f="${f}">${f === 'ALL' ? 'Tout' : f}</button>`).join('')}</div>
    <div id="sqList">${list.map(s => squawkItem(s)).join('') || '<div class="empty">Aucun événement pour ce filtre.</div>'}</div>`;
}, {
  mount() {
    ACTIONS.sqFilter = el => { state.squawkFilter = el.dataset.f; render(); };
    ACTIONS.toggleLive = () => { state.prefs.live = !state.prefs.live; save(); render(); };
  },
});

function pushSquawk() {
  if (!state.prefs.live) return;
  const base = D.SQUAWK_STREAM[state.streamIdx++ % D.SQUAWK_STREAM.length];
  const item = { ...base, t: nowHM(), id: 'live' + Date.now() };
  state.squawk.unshift(item); state.squawk = state.squawk.slice(0, 60);
  const r = route();
  if (r.name === 'squawk') {
    const list = $('#sqList');
    if (list && (state.squawkFilter === 'ALL' || item.sev === state.squawkFilter || item.assets.includes(state.squawkFilter))) {
      list.insertAdjacentHTML('afterbegin', squawkItem(item, true));
    }
  } else {
    state.unread++;
    const tabLabel = document.querySelector('.tabbar button[data-go=squawk] span');
    if (tabLabel) tabLabel.textContent = `Squawk (${state.unread})`;
    if (state.prefs.notif && state.user && (item.sev === 'CRITIQUE' || item.sev === 'ÉLEVÉ')) toast(`${flag(item.cc)} ${item.sev} · ${item.text.slice(0, 70)}…`);
  }
}

/* =========================================================================
   Assistant IA (chat)
   ========================================================================= */
const SUGGESTIONS = [
  'Résume-moi le marché ce matin',
  'Quel actif a la conviction la plus forte et pourquoi ?',
  'Quels sont les événements à surveiller cette semaine ?',
  'Explique l’impact du dernier squawk critique',
  'Construis-moi un scénario de risque pour l’or',
];
screen('ai', 'Analyste IA', () => `
  ${AI.isConnected() ? `<div class="small muted" style="margin-bottom:10px">${icon('spark').replace('<svg', '<svg width="13" height="13" style="vertical-align:-2px;color:var(--accent)"')} Connecté · ${esc(AI.MODELS.find(m => m.id === AI.getConfig().model)?.label || AI.getConfig().model)} ${AI.getConfig().webSearch ? '· recherche web activée' : ''}</div>` : needKeyCard('l’analyste IA')}
  <div class="chat" id="chat" style="margin-top:10px">
    ${state.chat.length ? '' : `<div class="empty">${icon('spark').replace('<svg', '<svg width="40" height="40" style="color:var(--accent)"')}<p><b>L’IA qui lit les marchés avant tout le monde.</b><br>Posez une question sur un actif, un événement ou un scénario.</p></div>`}
    ${state.chat.map(m => `<div class="msg ${m.role} ${m.role === 'assistant' ? 'md' : ''}">${m.role === 'assistant' ? md(m.content) : esc(m.content)}</div>`).join('')}
  </div>
  <div class="suggests" style="margin-top:14px">${SUGGESTIONS.map(s => `<button class="btn small" data-act="suggest">${esc(s)}</button>`).join('')}</div>
  ${state.chat.length ? '<div style="text-align:center;margin-top:8px"><button class="link small" data-act="clearChat">Effacer la conversation</button></div>' : ''}
  <div style="height:70px"></div>`, {
  after: () => `<form class="composer" id="composer"><textarea class="input" id="chatInput" rows="1" placeholder="Demandez à l’IA…"></textarea>
    <button class="btn primary" type="submit" aria-label="Envoyer" id="sendBtn">${icon('send').replace('<svg', '<svg width="18" height="18"')}</button></form>`,
  mount() {
    const main = $('#main'); main.scrollTop = main.scrollHeight;
    const input = $('#chatInput');
    input.addEventListener('input', () => { input.style.height = 'auto'; input.style.height = Math.min(120, input.scrollHeight) + 'px'; });
    input.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); $('#composer').requestSubmit(); } });
    $('#composer').onsubmit = e => { e.preventDefault(); const v = input.value.trim(); if (v) { input.value = ''; sendChat(v); } };
    ACTIONS.suggest = el => sendChat(el.textContent);
    ACTIONS.clearChat = () => { state.chat = []; save(); render(); };
    if (pendingQuestion) { const q = pendingQuestion; pendingQuestion = null; sendChat(q); }
  },
});

let pendingQuestion = null;
let chatAbort = null;
async function sendChat(text) {
  if (!AI.isConnected()) { promptConnect(); return; }
  if (state.busy) return;
  state.busy = true;
  state.chat.push({ role: 'user', content: text });
  const chat = $('#chat'); chat.querySelector('.empty')?.remove();
  chat.insertAdjacentHTML('beforeend', `<div class="msg user">${esc(text)}</div><div class="msg assistant md typing" id="live"></div>`);
  const main = $('#main'); main.scrollTop = main.scrollHeight;
  $('#sendBtn').disabled = true;
  let acc = '';
  chatAbort = new AbortController();
  try {
    await AI.streamChat({
      system: `${AI.SYSTEM_ANALYST}\n\nContexte actuel de l'application :\n${marketContext()}`,
      history: state.chat.map(m => ({ role: m.role, content: m.content })),
      signal: chatAbort.signal,
      onText: t => { acc += t; const el = $('#live'); if (el) { el.innerHTML = md(acc); const mm = $('#main'); if (mm) mm.scrollTop = mm.scrollHeight; } },
    });
    state.chat.push({ role: 'assistant', content: acc || '(réponse vide)' });
  } catch (err) {
    const el = $('#live'); if (el) { el.classList.add('error'); el.textContent = '⚠️ ' + err.message; }
    state.chat.pop();
  }
  $('#live')?.classList.remove('typing'); $('#live')?.removeAttribute('id');
  const b = $('#sendBtn'); if (b) b.disabled = false;
  state.busy = false; save();
}

/* =========================================================================
   Menu « Plus » et fonctionnalités de la plateforme
   ========================================================================= */
const FEATURES = [
  ['Lire le marché', [
    ['drivers', 'Pilote macro', 'Pourquoi le marché bouge, thème par thème', 'compass'],
    ['regime', 'Régime de marché', 'Risk-on / risk-off par zone', 'gauge'],
    ['recaps', 'Récaps', 'Sessions et semaine', 'doc'],
    ['squawk', 'Événements', 'Flux macro en temps réel', 'radio'],
    ['map', 'Carte macro', 'Géopolitique et fiches pays', 'globe'],
  ]],
  ['Données & positionnement', [
    ['calendar', 'Calendrier', 'Agenda économique', 'cal'],
    ['indicators', 'Indicateurs', 'PIB, CPI, emploi, PMI', 'bars'],
    ['markets', 'Vue d’ensemble', 'Actifs par classe', 'layers'],
    ['correlations', 'Corrélations', 'Matrice sur 60 jours', 'link'],
    ['strength', 'Force des devises', 'Classement G8', 'trend'],
    ['cot', 'Positionnement COT', 'Spéculateurs CFTC', 'users'],
    ['rates', 'Taux d’intérêt', 'Banques centrales et anticipations', 'percent'],
    ['bonds', 'Obligations', 'Rendements souverains', 'bank'],
    ['seasonality', 'Saisonnalité', 'Tendances mensuelles', 'cal'],
  ]],
  ['Recherche & anticipations', [
    ['research', 'Recherche bancaire', 'Vues des grandes banques', 'bank'],
    ['predictions', 'Marchés prédictifs', 'Probabilités Kalshi / Polymarket', 'target'],
  ]],
  ['Agir', [
    ['home', 'Dashboard', 'Votre vue principale', 'home'],
    ['opportunities', 'Opportunités', 'Setups directionnels', 'target', true],
    ['markets', 'Actifs', 'Les 9 marchés suivis', 'chart'],
    ['support', 'Support', 'Discuter avec l’équipe', 'chat'],
  ]],
  ['Compte', [
    ['settings/api', 'Clé API Claude', 'Connecter l’IA', 'key'],
    ['claude-code', 'Claude Code', 'Utiliser l’app avec Claude Code', 'term'],
    ['pricing', 'Abonnement', 'Offres et facturation', 'tag'],
    ['settings', 'Réglages', 'Thème, notifications, compte', 'gear'],
    ['about', 'À propos', 'Présentation et avis', 'info'],
  ]],
];
screen('more', 'Plateforme', () => FEATURES.map(([g, items]) => `<div class="section-title"><h2>${g}</h2></div><div class="card" style="padding:2px 14px">
  ${items.map(([r, t, d, ic, pro]) => `<div class="list-item" data-go="${r}"><div class="ico">${icon(ic)}</div><div class="txt"><b>${t} ${pro ? '<span class="badge-pro">PRO</span>' : ''}</b><small>${d}</small></div><span class="muted">›</span></div>`).join('')}</div>`).join('') + footer());

screen('about', 'À propos', () => SCREENS.welcome.fn().replace(/<section class="hero">[\s\S]*?<\/section>/, `<div class="hero"><h2>${D.BRAND.name}</h2><p>${D.BRAND.tagline}.</p></div>`), { tab: 'more' });

/* ---- Pilote macro ---- */
screen('drivers', 'Pilote macro', () => `
  <div class="card glow"><h2 style="margin:0 0 4px">Pourquoi le marché bouge, thème par thème.</h2>
    <p class="small muted" style="margin:0">Ce qui fait bouger le marché, mis à jour chaque matin : 3 à 6 thèmes, leur poids et la direction attendue par actif.</p></div>
  ${D.DRIVERS.map((d, i) => `<div class="card tap" data-go="driver/${i}">
    <div class="row between"><b>${esc(d.topic)}</b><b style="font-size:18px">${d.w}%</b></div>
    <div class="bar" style="margin:8px 0"><span style="width:${d.w * 2.5}%;background:linear-gradient(90deg,var(--accent),var(--accent-2))"></span></div>
    <div class="row between small"><div>${d.impacts.map(([a, v]) => `<span class="chip v-${vKey(v)}">${vArrow(v)} ${a}</span>`).join('')}</div>
      <span class="muted">J ${d.dd >= 0 ? '+' : ''}${d.dd} · S ${d.wk >= 0 ? '+' : ''}${d.wk}</span></div></div>`).join('')}
  <button class="btn block primary" style="margin-top:12px" data-act="askAI" data-q="Quels sont aujourd'hui les 3 à 6 thèmes macro qui expliquent l'essentiel des mouvements de marché ? Donne leur poids, la direction attendue par actif et les signaux à surveiller.">${icon('spark').replace('<svg', '<svg width="16" height="16"')} Demander le pilote du jour à Claude</button>
  <p class="disclaimer">Les probabilités proviennent des marchés prédictifs, avec leur source. Aucune n’est produite par le modèle.</p>`, { tab: 'more' });

screen('driver', 'Thème macro', (i) => {
  const d = D.DRIVERS[+i]; if (!d) return '<div class="empty">Thème introuvable.</div>';
  return `<div class="card"><h2 style="margin:0 0 6px">${esc(d.topic)}</h2><div class="row between"><span class="muted small">Poids dans les mouvements</span><b style="font-size:22px">${d.w}%</b></div>
    <div class="small muted">Variation : ${d.dd >= 0 ? '+' : ''}${d.dd} pt sur un jour, ${d.wk >= 0 ? '+' : ''}${d.wk} pt sur une semaine</div></div>
  <div class="section-title"><h2>Direction par actif</h2></div>
  <div class="card">${d.impacts.map(([a, v]) => `<div class="row between" style="padding:7px 0"><b>${a}</b>${pill(v)}</div>`).join('')}</div>
  <div class="section-title"><h2>Scénarios</h2></div>
  ${d.scenarios.map(s => `<div class="card"><div class="row between"><b>${esc(s.name)}</b><b>${s.p}%</b></div><div class="bar" style="margin:8px 0"><span style="width:${s.p}%;background:var(--accent-2)"></span></div><div class="small muted">Analogue historique : ${esc(s.analog)}</div></div>`).join('')}
  <div class="section-title"><h2>Signaux à surveiller</h2></div>
  <div class="card">${d.watch.map(w => `<div class="feat">${esc(w)}</div>`).join('')}</div>
  <button class="btn block primary" style="margin-top:12px" data-act="driverAI" data-i="${i}">${icon('spark').replace('<svg', '<svg width="16" height="16"')} Approfondir avec Claude</button>
  <div style="margin-top:10px">${aiBox('driverAiBox')}</div>`;
}, { tab: 'more' });

/* ---- Régime ---- */
screen('regime', 'Régime de marché', () => `
  <div class="grid-2">${D.REGIMES.map(r => `<div class="card"><div class="row between"><b>${flag(r.zone)} ${r.zone}</b>${pill(r.tone)}</div><div style="margin-top:6px;font-weight:700" class="v-${vKey(r.tone)}">${r.label}</div></div>`).join('')}</div>
  <div class="section-title"><h2>Devises</h2></div>
  <div class="card">${D.CURRENCIES.map(c => `<div class="row between" style="padding:7px 0"><b>${c.pair}</b>${pill(c.v)}</div>`).join('')}</div>`, { tab: 'more' });

/* ---- Récaps ---- */
screen('recaps', 'Récaps', () => `
  <button class="btn block primary" data-act="recapAI">${icon('spark').replace('<svg', '<svg width="16" height="16"')} Générer le récap du moment avec Claude</button>
  <div style="margin-top:10px">${aiBox('recapAiBox', 'Récap généré par Claude')}</div>
  ${D.RECAPS.map(r => `<div class="card"><div class="row between"><b>${r.title}</b><span class="small muted">${r.when}</span></div><p class="small" style="margin:8px 0 0;line-height:1.5">${esc(r.text)}</p></div>`).join('')}`, { tab: 'more' });

/* ---- Carte macro ---- */
screen('map', 'Carte macro', () => `
  <div class="card" style="padding:8px">${worldMap()}</div>
  <div class="section-title"><h2>Fiches pays</h2></div>
  ${D.COUNTRIES.map(c => `<div class="card"><div class="row between"><b>${flag(c.cc)} ${c.name}</b><span class="pill ${c.risk === 'Critique' || c.risk === 'Élevé' ? 'bg-bear' : c.risk === 'Faible' ? 'bg-bull' : 'bg-neutral'}">${c.risk}</span></div><p class="small muted" style="margin:6px 0 0">${esc(c.text)}</p></div>`).join('')}`, { tab: 'more' });

function worldMap() {
  const pts = { US: [22, 38], CA: [20, 26], EU: [49, 30], UK: [46, 27], RU: [66, 24], CN: [76, 40], JP: [86, 38], IR: [62, 42], SA: [59, 48], AU: [85, 74], EM: [32, 66] };
  const risk = Object.fromEntries(D.COUNTRIES.map(c => [c.cc, c.risk]));
  const col = r => r === 'Critique' || r === 'Élevé' ? 'var(--bear)' : r === 'Faible' ? 'var(--bull)' : r ? 'var(--neutral)' : 'var(--accent)';
  return `<svg viewBox="0 0 100 80" style="width:100%;display:block">
    <rect width="100" height="80" rx="4" fill="var(--bg-2)"/>
    ${[...Array(9)].map((_, i) => `<line x1="0" y1="${i * 10}" x2="100" y2="${i * 10}" stroke="var(--line)" stroke-width=".2"/>`).join('')}
    ${[...Array(11)].map((_, i) => `<line x1="${i * 10}" y1="0" x2="${i * 10}" y2="80" stroke="var(--line)" stroke-width=".2"/>`).join('')}
    <path d="M8 22 Q20 12 34 20 L32 44 Q24 52 18 46 Z M26 52 Q34 52 36 62 L30 76 Q24 66 26 52 Z M44 22 Q54 16 60 24 L56 32 Q48 34 44 28 Z M46 36 Q58 34 62 46 L56 66 Q48 60 46 36 Z M60 18 Q80 12 94 24 L90 44 Q74 48 64 40 Z M78 66 Q88 62 92 70 L86 76 Q78 74 78 66 Z" fill="var(--card-2)" stroke="var(--line)" stroke-width=".4"/>
    ${Object.entries(pts).map(([cc, [x, y]]) => `<circle cx="${x}" cy="${y}" r="2.2" fill="${col(risk[cc])}"><animate attributeName="r" values="2;3;2" dur="2s" repeatCount="indefinite"/></circle><text x="${x + 3}" y="${y + 1}" font-size="3" fill="var(--text)">${cc}</text>`).join('')}
  </svg>`;
}

/* ---- Calendrier ---- */
screen('calendar', 'Calendrier économique', () => D.CALENDAR.map(d => `<div class="section-title"><h2>${d.day}</h2></div><div class="card" style="padding:4px 12px">
  ${d.items.map(i => `<div class="list-item" style="cursor:default"><div class="mono small" style="width:42px">${i.t}</div><div class="txt"><b>${flag(i.cc)} ${esc(i.ev)}</b>
    <small>Préc. ${i.prev} · Cons. ${i.cons} · Réel <b style="color:var(--text)">${i.act}</b></small></div><span title="Importance" style="color:var(--bear);letter-spacing:-2px">${'●'.repeat(i.imp)}<span class="muted">${'●'.repeat(3 - i.imp)}</span></span></div>`).join('')}</div>`).join(''), { tab: 'more' });

/* ---- Indicateurs ---- */
screen('indicators', 'Indicateurs macro', () => D.INDICATORS.map(z => `<div class="card"><h3>${flag(z.cc)} ${z.cc}</h3>
  <table class="tbl">${z.rows.map(r => `<tr><td class="muted">${r[0]}</td><td style="text-align:right"><b class="mono">${r[1]}</b></td></tr>`).join('')}</table></div>`).join(''), { tab: 'more' });

/* ---- Force des devises ---- */
screen('strength', 'Force des devises', () => `<div class="card">${D.CURRENCY_STRENGTH.map(([c, v]) => `<div style="margin:10px 0"><div class="row between small"><b>${c}</b><b class="mono">${v}</b></div>
  <div class="bar"><span style="width:${v}%;background:${v > 60 ? 'var(--bull)' : v < 35 ? 'var(--bear)' : 'var(--neutral)'}"></span></div></div>`).join('')}</div>
  <p class="small muted">Score composite 0–100 sur 28 paires, glissant sur 5 jours.</p>`, { tab: 'more' });

/* ---- Corrélations ---- */
screen('correlations', 'Corrélations', () => {
  const c = v => v >= 0 ? `color-mix(in srgb, var(--bull) ${Math.round(v * 80)}%, var(--card-2))` : `color-mix(in srgb, var(--bear) ${Math.round(-v * 80)}%, var(--card-2))`;
  return `<div class="card scroll-x"><table class="heat" style="border-spacing:3px;border-collapse:separate;width:100%"><tr><td></td>${D.CORR_ASSETS.map(a => `<td class="muted" style="font-size:9px">${a}</td>`).join('')}</tr>
    ${D.CORR.map((row, i) => `<tr><td class="muted" style="font-size:9px;text-align:right">${D.CORR_ASSETS[i]}</td>${row.map(v => `<td style="background:${c(v)}">${v.toFixed(2)}</td>`).join('')}</tr>`).join('')}</table></div>
    <p class="small muted">Corrélation des rendements journaliers sur 60 jours.</p>`;
}, { tab: 'more' });

/* ---- COT ---- */
screen('cot', 'Positionnement COT', () => D.COT.map(c => `<div class="card"><div class="row between"><b>${c.a}</b><span class="mono small ${c.chg >= 0 ? 'v-bull' : 'v-bear'}">${c.chg >= 0 ? '+' : ''}${c.chg.toLocaleString('fr-FR')}</span></div>
  <div class="small muted">Net spéculatif : <b style="color:var(--text)">${c.net.toLocaleString('fr-FR')}</b> contrats</div>
  <div class="bar" style="margin-top:8px;display:flex"><span style="width:${c.longPct}%;background:var(--bull)"></span><span style="width:${100 - c.longPct}%;background:var(--bear)"></span></div>
  <div class="row between small muted" style="margin-top:4px"><span>Long ${c.longPct}%</span><span>Short ${100 - c.longPct}%</span></div></div>`).join('') + '<p class="small muted">Source : rapport CFTC hebdomadaire (données de démonstration).</p>', { tab: 'more' });

/* ---- Taux ---- */
screen('rates', 'Taux & anticipations', () => D.RATES.map(r => `<div class="card"><div class="row between"><b>${flag(r.cc)} ${r.cb}</b><b class="mono">${r.rate}</b></div>
  <div class="small muted">Prochaine réunion : ${r.next}</div>
  <div class="bar" style="margin-top:8px;display:flex;height:10px"><span style="width:${r.cut}%;background:var(--bull)"></span><span style="width:${r.hold}%;background:var(--neutral)"></span><span style="width:${r.hike}%;background:var(--bear)"></span></div>
  <div class="row between small" style="margin-top:4px"><span class="v-bull">Baisse ${r.cut}%</span><span class="v-neutral">Statu quo ${r.hold}%</span><span class="v-bear">Hausse ${r.hike}%</span></div></div>`).join(''), { tab: 'more' });

/* ---- Obligations ---- */
screen('bonds', 'Obligations souveraines', () => `<div class="card"><table class="tbl"><tr><th>Titre</th><th style="text-align:right">Rendement</th><th style="text-align:right">Var. (pb)</th></tr>
  ${D.BONDS.map(([n, y, c]) => `<tr><td><b>${n}</b></td><td class="mono" style="text-align:right">${y.toFixed(2)} %</td><td class="mono ${c >= 0 ? 'v-bear' : 'v-bull'}" style="text-align:right">${c >= 0 ? '+' : ''}${c}</td></tr>`).join('')}</table></div>
  <div class="card"><div class="small muted">Spread US 10A – US 2A</div><b class="mono" style="font-size:22px">${Math.round((D.BONDS[1][1] - D.BONDS[0][1]) * 100)} pb</b></div>`, { tab: 'more' });

/* ---- Saisonnalité ---- */
screen('seasonality', 'Saisonnalité', () => Object.entries(D.SEASONALITY).map(([a, v]) => `<div class="card"><h3>${a}</h3>${seasonBars(v)}</div>`).join(''), { tab: 'more' });

/* ---- Recherche bancaire ---- */
screen('research', 'Recherche bancaire', () => D.BANK_RESEARCH.map(b => `<div class="card"><div class="row between"><span class="small muted">${b.bank}</span>${pill(b.view)}</div>
  <b style="display:block;margin-top:6px">${esc(b.title)}</b><span class="chip" style="margin-top:6px">${b.asset}</span></div>`).join('') +
  `<button class="btn block" style="margin-top:10px" data-act="askAI" data-q="Fais une synthèse du consensus des grandes banques sur l'or, le dollar, le S&P 500 et le pétrole, et signale les divergences.">${icon('spark').replace('<svg', '<svg width="16" height="16"')} Synthèse par Claude</button>`, { tab: 'more' });

/* ---- Marchés prédictifs ---- */
screen('predictions', 'Marchés prédictifs', () => D.PREDICTION_MARKETS.map(p => `<div class="card"><b>${esc(p.q)}</b>
  <div class="row between" style="margin:8px 0 4px"><span class="v-bull" style="font-weight:800;font-size:20px">Oui ${p.yes}%</span><span class="muted">Non ${100 - p.yes}%</span></div>
  <div class="bar"><span style="width:${p.yes}%;background:var(--bull)"></span></div>
  <div class="small muted" style="margin-top:6px">${p.src} · volume ${p.vol}</div></div>`).join(''), { tab: 'more' });

/* ---- Opportunités (Pro) ---- */
screen('opportunities', 'Opportunités', () => `
  <div class="card glow"><div class="row between"><b>Opportunités directionnelles</b><span class="badge-pro">PRO</span></div>
    <p class="small muted" style="margin:6px 0 0">Setups avec niveaux de stop et d’objectif (bêta). Performance publiée telle quelle.</p></div>
  ${D.OPPORTUNITIES.map(o => `<div class="card"><div class="row between"><div><b>${o.asset}</b> ${pill(o.dir)}</div>
    <span class="pill ${o.status === 'Active' ? 'bg-accent' : o.status === 'Cible atteinte' ? 'bg-bull' : 'bg-bear'}">${o.status}</span></div>
    <div class="grid-4 small" style="margin-top:10px;text-align:center"><div><div class="muted">Entrée</div><b class="mono">${o.entry}</b></div><div><div class="muted">Stop</div><b class="mono v-bear">${o.stop}</b></div>
    <div><div class="muted">Objectif</div><b class="mono v-bull">${o.target}</b></div><div><div class="muted">R/R</div><b class="mono">${o.rr}</b></div></div></div>`).join('')}
  <div class="card"><div class="row between"><span class="small muted">Taux de réussite (30 j)</span><b>58 %</b></div><div class="row between"><span class="small muted">R/R moyen</span><b>2,1</b></div></div>
  <div class="card tap" data-act="telegram"><div class="row">${icon('send')}<div><b>Canal Telegram privé</b><div class="small muted">Recevoir les opportunités en temps réel</div></div></div></div>
  <p class="disclaimer">Ces setups ne sont pas des conseils en investissement.</p>`, { tab: 'more' });

/* ---- Support ---- */
screen('support', 'Support', () => `
  <div class="card"><h3>Discuter avec l’équipe</h3><p class="small muted">Réponse en moins de 24 h ouvrées.</p>
    <label class="field"><span>Sujet</span><select class="input" id="supSubject"><option>Question sur l’abonnement</option><option>Problème technique</option><option>Clé API / Claude</option><option>Suggestion</option></select></label>
    <label class="field"><span>Message</span><textarea class="input" id="supMsg" rows="5"></textarea></label>
    <button class="btn primary block" data-act="supportSend">Envoyer</button></div>
  <div class="section-title"><h2>FAQ</h2></div>
  ${[['Les lectures sont-elles des conseils en investissement ?', 'Non. Elles sont fournies à titre d’information. Vous gardez la décision.'],
     ['Comment fonctionne l’essai gratuit ?', '7 jours gratuits. Rappel avant la fin, annulation en un clic.'],
     ['Où est stockée ma clé API Claude ?', 'Uniquement sur cet appareil (stockage local). Elle n’est envoyée qu’à api.anthropic.com.'],
     ['Puis-je utiliser l’app avec Claude Code ?', 'Oui : voir Plus › Claude Code pour exporter le contexte de marché et utiliser la même clé.']]
    .map(([q, a]) => `<details class="card"><summary style="cursor:pointer;font-weight:600">${q}</summary><p class="small muted" style="margin:8px 0 0">${a}</p></details>`).join('')}`, { tab: 'more' });

/* ---- Tarifs ---- */
screen('pricing', 'Choisissez votre offre', () => {
  const y = state.prefs.billing === 'yearly';
  return `<div class="seg" style="margin-bottom:14px"><button class="${!y ? 'on' : ''}" data-act="billing" data-b="monthly">Mensuel</button><button class="${y ? 'on' : ''}" data-act="billing" data-b="yearly">Annuel · 2 mois offerts</button></div>
  ${D.PLANS.map(p => `<div class="card plan ${p.recommended ? 'rec' : ''}"><div class="row between"><h3 style="margin:0">${p.name}</h3>${p.recommended ? '<span class="pill bg-accent">Recommandé</span>' : ''}${state.user?.plan === p.id ? '<span class="chip">Offre actuelle</span>' : ''}</div>
    <p class="small muted" style="margin:4px 0 10px">${p.tag}</p>
    <div class="price">${p.custom ? 'Sur devis' : `${y ? Math.round(p.yearly / 12) : p.monthly} €<span class="small muted" style="font-weight:400"> /mois${y ? ', facturé ' + p.yearly + ' €/an' : ''}</span>`}</div>
    <div style="margin:10px 0">${p.features.map(f => `<div class="feat">${esc(f)}</div>`).join('')}</div>
    ${p.custom ? `<a class="btn block" href="mailto:contact@example.com?subject=Offre%20Enterprise">Nous contacter</a>` :
      `<button class="btn block ${p.recommended ? 'primary' : ''}" data-act="choosePlan" data-p="${p.id}">Démarrer l’essai gratuit</button>`}</div>`).join('')}
  <p class="small muted" style="text-align:center">${icon('shield').replace('<svg', '<svg width="14" height="14" style="vertical-align:-2px"')} Annulable à tout moment · Paiements sécurisés · Aucun débit avant la fin de l’essai</p>
  <div class="section-title"><h2>Manuel vs ${D.BRAND.name}</h2></div>${comparisonTable()}`;
}, {
  tab: 'more',
  mount() {
    ACTIONS.billing = el => { state.prefs.billing = el.dataset.b; save(); render(); };
    ACTIONS.choosePlan = el => {
      if (!state.user) return go('signup');
      state.user.plan = el.dataset.p; const acc = state.accounts[state.user.email]; if (acc) acc.plan = el.dataset.p; save();
      toast(`Offre ${el.dataset.p === 'pro' ? 'Pro' : 'Basic'} activée (essai 7 jours, démo sans paiement).`); render();
    };
  },
});

screen('legal', 'Mentions légales', () => `<div class="card small" style="line-height:1.55">
  <h3>Avertissement</h3><p>Les informations, biais et analyses affichés sont fournis à titre purement informatif et ne constituent ni un conseil en investissement, ni une recommandation d’achat ou de vente.</p>
  <h3>Données</h3><p>Les données de marché de cette application sont des données de démonstration. Les analyses générées par Claude dépendent de votre clé API et des informations disponibles au moment de la requête.</p>
  <h3>Confidentialité</h3><p>Votre compte, vos préférences et votre clé API sont stockés localement sur votre appareil. Aucune donnée n’est transmise à un serveur tiers, hormis les requêtes envoyées à l’API Claude (api.anthropic.com) lorsque vous utilisez les fonctions IA.</p>
  <h3>Cookies</h3><p>L’application n’utilise pas de cookies de suivi. Seul le stockage local du navigateur est utilisé.</p></div>`, { tab: 'more' });

/* =========================================================================
   Réglages et clé API
   ========================================================================= */
screen('settings', 'Réglages', () => {
  const u = state.user || {};
  return `<div class="card"><div class="row"><div class="ico" style="width:44px;height:44px;border-radius:50%;background:linear-gradient(135deg,var(--accent),var(--accent-2));display:grid;place-items:center;color:#061021;font-weight:800">${esc((u.email || '?')[0].toUpperCase())}</div>
    <div style="flex:1;min-width:0"><b style="display:block;overflow:hidden;text-overflow:ellipsis">${esc(u.email)}</b><span class="small muted">Offre ${esc(u.plan || '—')} · ${esc(u.country || '')}</span></div></div></div>

  <div class="section-title"><h2>Intelligence artificielle</h2></div>
  <div class="card" style="padding:2px 14px">
    <div class="list-item" data-go="settings/api"><div class="ico">${icon('key')}</div><div class="txt"><b>Clé API Claude</b><small>${AI.isConnected() ? 'Connectée · ' + AI.maskKey(AI.getConfig().apiKey) : 'Non configurée'}</small></div><span class="muted">›</span></div>
    <div class="list-item" data-go="claude-code"><div class="ico">${icon('term')}</div><div class="txt"><b>Claude Code</b><small>Exporter le contexte, utiliser la même clé</small></div><span class="muted">›</span></div>
  </div>

  <div class="section-title"><h2>Préférences</h2></div>
  <div class="card" style="padding:2px 14px">
    ${toggleRow('theme', 'Thème clair', 'sun', state.prefs.theme === 'light')}
    ${toggleRow('notif', 'Alertes squawk critiques', 'bell', state.prefs.notif)}
    ${toggleRow('live', 'Flux en direct', 'radio', state.prefs.live)}
  </div>

  <div class="section-title"><h2>Compte</h2></div>
  <div class="card" style="padding:2px 14px">
    <div class="list-item" data-go="pricing"><div class="ico">${icon('tag')}</div><div class="txt"><b>Abonnement</b><small>Changer d’offre</small></div><span class="muted">›</span></div>
    <div class="list-item" data-act="affiliate"><div class="ico">${icon('users')}</div><div class="txt"><b>Programme d’affiliation</b><small>Parrainez et gagnez des mois offerts</small></div><span class="muted">›</span></div>
    <div class="list-item" data-go="legal"><div class="ico">${icon('doc')}</div><div class="txt"><b>Mentions légales</b><small>CGU, confidentialité, cookies</small></div><span class="muted">›</span></div>
    <div class="list-item" data-act="logout"><div class="ico">${icon('out')}</div><div class="txt"><b class="v-bear">Se déconnecter</b></div></div>
  </div>
  <div style="text-align:center;margin-top:14px"><button class="link small v-bear" data-act="resetAll">Réinitialiser toutes les données locales</button></div>`;
}, {
  tab: 'more',
  mount() {
    ACTIONS.toggle = el => {
      const k = el.dataset.k, on = el.checked;
      if (k === 'theme') state.prefs.theme = on ? 'light' : 'dark'; else state.prefs[k] = on;
      save(); document.documentElement.dataset.theme = state.prefs.theme;
    };
  },
});
function toggleRow(k, label, ic, on) {
  return `<div class="list-item" style="cursor:default"><div class="ico">${icon(ic)}</div><div class="txt"><b>${label}</b></div>
    <label class="switch"><input type="checkbox" data-act="toggle" data-k="${k}" ${on ? 'checked' : ''}><span></span></label></div>`;
}

screen('api', 'Clé API Claude', () => {
  const cfg = AI.getConfig();
  return `
  <div class="card glow"><div class="row">${icon('key')}<div><b>Connecter l’application à Claude</b><div class="small muted">${AI.isConnected() ? `Clé active : <span class="mono">${esc(AI.maskKey(cfg.apiKey))}</span>` : 'Aucune clé configurée'}</div></div></div></div>

  <div class="card">
    <label class="field"><span>Clé API Anthropic</span>
      <input class="input mono" id="apiKey" type="password" placeholder="sk-ant-api03-…" autocomplete="off" spellcheck="false" value="${esc(cfg.apiKey)}"></label>
    <label class="check" style="margin-top:-4px"><input type="checkbox" id="showKey"> Afficher la clé</label>
    <label class="field"><span>Modèle</span><select class="input" id="model">${AI.MODELS.map(m => `<option value="${m.id}" ${m.id === cfg.model ? 'selected' : ''}>${m.label}</option>`).join('')}</select></label>
    <label class="field"><span>Niveau d’effort (profondeur de réflexion)</span><select class="input" id="effort">${AI.EFFORTS.map(e => `<option ${e === cfg.effort ? 'selected' : ''}>${e}</option>`).join('')}</select></label>
    <div class="row between" style="margin-bottom:14px"><div><b class="small">Recherche web</b><div class="small muted">Claude consulte l’actualité en direct</div></div>
      <label class="switch"><input type="checkbox" id="webSearch" ${cfg.webSearch ? 'checked' : ''}><span></span></label></div>
    <div class="grid-2"><button class="btn primary" data-act="saveKey">Enregistrer</button><button class="btn" data-act="testKey" id="testBtn">Tester</button></div>
    <div id="testResult" style="margin-top:10px"></div>
    ${cfg.apiKey ? '<button class="btn block danger small" style="margin-top:10px" data-act="removeKey">Supprimer la clé</button>' : ''}
  </div>

  <div class="section-title"><h2>Ce que la clé active</h2></div>
  <div class="card">${['Chat avec l’analyste IA (streaming)', 'Actualisation des 9 biais directionnels', 'Analyse approfondie de chaque actif', 'Impact IA de chaque squawk', 'Récaps et pilote macro générés à la demande'].map(f => `<div class="feat">${f}</div>`).join('')}</div>

  <div class="section-title"><h2>Obtenir une clé</h2></div>
  <div class="card small" style="line-height:1.55"><ol style="margin:0;padding-left:18px">
    <li>Créez un compte sur <a href="https://console.anthropic.com/" target="_blank" rel="noopener">console.anthropic.com</a>.</li>
    <li>Ouvrez <b>Settings › API Keys</b> et créez une clé.</li>
    <li>Collez-la ci-dessus puis appuyez sur <b>Tester</b>.</li></ol></div>

  <div class="notice" style="margin-top:12px">${icon('shield').replace('<svg', '<svg width="15" height="15" style="vertical-align:-3px"')}
    La clé est stockée uniquement sur cet appareil et envoyée directement à <b>api.anthropic.com</b>. Pour un usage public, faites transiter les appels par votre propre serveur afin de ne pas exposer la clé dans le navigateur.</div>

  <div class="card tap" style="margin-top:12px" data-go="claude-code"><div class="row">${icon('term')}<div style="flex:1"><b>Utiliser avec Claude Code</b><div class="small muted">Même clé, contexte de marché exportable</div></div>›</div></div>`;
}, {
  tab: 'more',
  mount() {
    $('#showKey').onchange = e => { $('#apiKey').type = e.target.checked ? 'text' : 'password'; };
    const read = () => ({ apiKey: $('#apiKey').value.trim(), model: $('#model').value, effort: $('#effort').value, webSearch: $('#webSearch').checked });
    ACTIONS.saveKey = () => {
      const v = read();
      if (v.apiKey && !v.apiKey.startsWith('sk-ant-')) toast('Attention : une clé Anthropic commence normalement par « sk-ant- ».');
      AI.saveConfig(v); toast(v.apiKey ? 'Clé enregistrée.' : 'Réglages enregistrés.'); render();
    };
    ACTIONS.testKey = async () => {
      AI.saveConfig(read());
      const btn = $('#testBtn'), out = $('#testResult');
      btn.disabled = true; btn.innerHTML = '<span class="spinner"></span>';
      const r = await AI.testConnection();
      btn.disabled = false; btn.textContent = 'Tester';
      out.innerHTML = r.ok ? `<div class="notice v-bull">✓ Connexion réussie (${esc(r.model)}) : « ${esc(r.text)} »</div>` : `<div class="notice v-bear">✗ ${esc(r.text)}</div>`;
      const dot = document.querySelector('.topbar .dot'); if (dot) dot.classList.toggle('ok', AI.isConnected());
    };
    ACTIONS.removeKey = () => { AI.saveConfig({ apiKey: '' }); toast('Clé supprimée.'); render(); };
  },
});

/* ---- Claude Code ---- */
screen('claude-code', 'Claude Code', () => `
  <div class="card glow"><div class="row">${icon('term')}<div><b>Connecter l’app à Claude Code</b><div class="small muted">Claude Code utilise la même clé API Anthropic.</div></div></div></div>

  <div class="section-title"><h2>1. Utiliser votre clé dans Claude Code</h2></div>
  <div class="card small"><p style="margin-top:0">Dans un terminal, exportez votre clé puis lancez Claude Code :</p>
  <pre class="code">export ANTHROPIC_API_KEY="sk-ant-…"
claude</pre>
  <p class="muted" style="margin-bottom:0">Ou connectez-vous avec <code class="k">claude</code> puis <code class="k">/login</code>. ${AI.isConnected() ? 'Votre clé enregistrée dans l’app peut être copiée ci-dessous.' : ''}</p>
  ${AI.isConnected() ? '<button class="btn small" style="margin-top:10px" data-act="copyExport">Copier la commande avec ma clé</button>' : ''}</div>

  <div class="section-title"><h2>2. Exporter le contexte de marché</h2></div>
  <div class="card small"><p style="margin-top:0">Copiez un instantané (biais, squawks, régimes, pilote macro) à coller dans Claude Code, ou téléchargez-le en JSON pour qu’un script le lise.</p>
  <div class="grid-2"><button class="btn primary" data-act="copyContext">Copier (Markdown)</button><button class="btn" data-act="downloadJson">Télécharger JSON</button></div></div>

  <div class="section-title"><h2>3. Modifier l’application avec Claude Code</h2></div>
  <div class="card small"><p style="margin-top:0">Le code source est dans le dossier <code class="k">mobile-app/</code> du dépôt. Ouvrez-le avec Claude Code :</p>
  <pre class="code">cd github-slideshow/mobile-app
claude "Ajoute un nouvel actif DAX avec son biais"</pre>
  <p class="muted" style="margin-bottom:0">Le fichier <code class="k">CLAUDE.md</code> du dossier décrit l’architecture pour Claude Code.</p></div>`, { tab: 'more' });

/* =========================================================================
   Actions
   ========================================================================= */
const ACTIONS = {
  demo() { login({ email: 'demo@demo.local', country: 'France', plan: 'pro', trialEnds: Date.now() + 7 * 864e5, demo: true }); toast('Mode démo : explorez librement.'); },
  magicOpen(el) { const acc = state.accounts[el.dataset.email]; closeSheet(); if (acc) login(acc); },
  forgotSend() { const v = $('#fEmail').value.trim(); if (!v) return toast('Saisissez votre e-mail.'); toast('Si un compte existe, un lien a été envoyé (démo).'); go('login'); },
  logout() { state.user = null; save(); go('welcome'); },
  resetAll() {
    if (!confirm('Supprimer toutes les données locales (compte, clé API, conversation) ?')) return;
    try { Object.keys(localStorage).filter(k => k.startsWith('pm.')).forEach(k => localStorage.removeItem(k)); } catch { /* ignoré */ }
    location.hash = ''; location.reload();
  },
  fav(el) {
    const id = el.dataset.id, i = state.favorites.indexOf(id);
    i >= 0 ? state.favorites.splice(i, 1) : state.favorites.push(id); save(); render();
    toast(i >= 0 ? 'Retiré des favoris' : 'Ajouté aux favoris');
  },
  askAI(el) { pendingQuestion = el.dataset.q; go('ai'); },
  askAbout(el) { pendingQuestion = `Que penses-tu de ${el.dataset.id} en ce moment ? Donne-moi le verdict, la conviction, les drivers et les niveaux à surveiller.`; go('ai'); },
  assetAI(el) {
    const id = el.dataset.id, b = state.bias[id];
    streamInto('assetAiBox', `Fais une analyse approfondie de ${id} (${assetName(id)}). Verdict actuel affiché : ${vLabel(b.v)} à ${b.conv}% de conviction.
Drivers actuels : ${b.drivers.join(' ; ')}. Risque clé : ${b.risk}.
Vérifie l'actualité récente si tu as accès à la recherche web. Structure : **Verdict**, puis les 4 angles (Macro, Fondamental, Géopolitique, Quantitatif), **Niveaux à surveiller**, **Risque clé**. 200 mots maximum.`, { useWeb: true });
  },
  driverAI(el) {
    const d = D.DRIVERS[+el.dataset.i];
    streamInto('driverAiBox', `Approfondis le thème macro « ${d.topic} » (poids ${d.w}% dans les mouvements). Scénarios : ${d.scenarios.map(s => `${s.name} (${s.p}%, analogue ${s.analog})`).join(' ; ')}.
Explique le mécanisme de transmission vers ${d.impacts.map(i => i[0]).join(', ')}, ce que disent les analogues historiques, et ce qui ferait basculer le scénario. 200 mots max.`, { useWeb: true });
  },
  recapAI() {
    streamInto('recapAiBox', `Rédige le récap de marché du moment (session en cours) : indices, devises, matières premières, crypto, et les 3 événements à surveiller ensuite. Utilise la recherche web si disponible. 180 mots max.\n\nContexte de l'app :\n${marketContext()}`, { useWeb: true });
  },
  squawkAI(el) {
    const s = state.squawk.find(x => x.id === el.dataset.id); if (!s) return;
    if (!AI.isConnected()) return promptConnect();
    sheet(`<div class="row" style="gap:6px;margin-bottom:6px"><span>${flag(s.cc)}</span><span class="sev sev-${s.sev}">${s.sev}</span><span class="small muted mono">${s.t}</span></div>
      <b>${esc(s.text)}</b><div style="margin-top:12px">${aiBox('sqAiBox', 'Impact selon Claude')}</div>`);
    streamInto('sqAiBox', `Un squawk macro vient de tomber : « ${s.text} » (pays ${s.cc}, sévérité ${s.sev}). Actifs probablement concernés : ${s.assets.join(', ')}.
Pour chaque actif concerné : direction probable (haussier/baissier/neutre), intensité, et le mécanisme en une phrase. Termine par ce qui invaliderait cette lecture. 150 mots max.`);
  },
  async refreshBias(el) {
    if (!AI.isConnected()) return promptConnect();
    if (state.busy) return;
    state.busy = true;
    const btn = el || $('#refreshBtn'); const old = btn.innerHTML; btn.disabled = true; btn.innerHTML = '<span class="spinner"></span> Claude analyse…';
    try {
      const txt = await AI.ask({
        system: AI.SYSTEM_ANALYST, useWeb: true,
        prompt: `Établis le biais directionnel du jour pour les 9 actifs, en t'appuyant sur l'actualité macro la plus récente (utilise la recherche web si disponible).
Réponds UNIQUEMENT avec un objet JSON valide, sans texte autour, de la forme :
{"summary":"une phrase de synthèse du marché","assets":{"SP500":{"verdict":"bullish|bearish|neutral","conviction":0-100,"angles":{"macro":-1|0|1,"fonda":-1|0|1,"geo":-1|0|1,"quant":-1|0|1},"drivers":["…","…","…"],"risk":"…"}, … pour SP500, NASDAQ, GOLD, OIL, NATGAS, EURUSD, USDJPY, USDCAD, BTC}}
Les drivers sont des phrases courtes en français.`,
      });
      const json = AI.extractJson(txt);
      let n = 0;
      for (const a of D.ASSETS) {
        const x = json.assets?.[a.id]; if (!x) continue;
        const v = x.verdict === 'bullish' ? 1 : x.verdict === 'bearish' ? -1 : 0;
        const ang = k => Math.max(-1, Math.min(1, Math.round(Number(x.angles?.[k]) || 0)));
        state.bias[a.id] = { v, conv: Math.max(0, Math.min(100, Math.round(Number(x.conviction) || 50))),
          angles: { macro: ang('macro'), fonda: ang('fonda'), geo: ang('geo'), quant: ang('quant') },
          drivers: (Array.isArray(x.drivers) ? x.drivers : []).slice(0, 4).map(String), risk: String(x.risk || '') };
        n++;
      }
      if (!n) throw new Error('La réponse ne contenait aucun actif exploitable.');
      state.biasMeta = { source: 'claude', at: Date.now(), summary: String(json.summary || '') };
      save(); toast(`${n} biais mis à jour par Claude.`);
    } catch (err) { toast('⚠️ ' + err.message); }
    state.busy = false;
    if (document.body.contains(btn)) { btn.disabled = false; btn.innerHTML = old; }
    render();
  },
  telegram() { toast('Canal Telegram réservé aux abonnés Pro (démo).'); },
  affiliate() {
    const code = (state.user?.email || 'demo').split('@')[0].toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8) + '30';
    sheet(`<h2 style="margin-top:0">Programme d’affiliation</h2><p class="muted">Partagez votre code : vos filleuls obtiennent 30 % de remise et vous gagnez un mois offert par abonnement.</p>
      <div class="card row between"><b class="mono" style="font-size:20px">${code}</b><button class="btn small" data-act="copy" data-t="${code}">Copier</button></div>`);
  },
  async copy(el) { await copyText(el.dataset.t); },
  supportSend() {
    const msg = $('#supMsg').value.trim(); if (!msg) return toast('Écrivez votre message.');
    const subj = $('#supSubject').value;
    location.href = `mailto:contact@example.com?subject=${encodeURIComponent('[Support] ' + subj)}&body=${encodeURIComponent(msg)}`;
    $('#supMsg').value = ''; toast('Message prêt dans votre messagerie.');
  },
  async copyExport() { await copyText(`export ANTHROPIC_API_KEY="${AI.getConfig().apiKey}"\nclaude`); },
  async copyContext() { await copyText(contextMarkdown()); },
  downloadJson() {
    const data = { generatedAt: new Date().toISOString(), biasSource: state.biasMeta.source, summary: state.biasMeta.summary,
      bias: state.bias, prices: state.prices, squawk: state.squawk.slice(0, 20), regimes: D.REGIMES, drivers: D.DRIVERS };
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }));
    a.download = `contexte-marche-${new Date().toISOString().slice(0, 10)}.json`; a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  },
};

async function copyText(t) {
  try { await navigator.clipboard.writeText(t); toast('Copié dans le presse-papiers.'); }
  catch { sheet(`<h3>Copiez ce texte</h3><textarea class="input mono" rows="10" readonly>${esc(t)}</textarea>`); }
}

function contextMarkdown() {
  return `# Contexte de marché — ${new Date().toLocaleString('fr-FR')}\n\n` +
    `Source des biais : ${state.biasMeta.source}${state.biasMeta.summary ? `\n\n> ${state.biasMeta.summary}` : ''}\n\n` +
    `## Biais directionnels\n\n| Actif | Verdict | Conviction | Driver principal | Risque clé |\n|---|---|---|---|---|\n` +
    D.ASSETS.map(a => { const b = state.bias[a.id]; return `| ${a.id} | ${vLabel(b.v)} | ${b.conv}% | ${b.drivers[0] || ''} | ${b.risk} |`; }).join('\n') +
    `\n\n## Derniers squawks\n\n` + state.squawk.slice(0, 8).map(s => `- **${s.t} ${s.cc} [${s.sev}]** ${s.text} (${s.assets.join(', ')})`).join('\n') +
    `\n\n## Régimes macro\n\n` + D.REGIMES.map(r => `- ${r.zone} : ${r.label}`).join('\n') +
    `\n\n## Pilote macro\n\n` + D.DRIVERS.map(d => `- ${d.topic} — ${d.w}% (${d.impacts.map(([a, v]) => `${a} ${vArrow(v)}`).join(', ')})`).join('\n') + '\n';
}

/* =========================================================================
   Simulation temps réel des prix
   ========================================================================= */
function tickPrices() {
  for (const a of D.ASSETS) {
    const p = state.prices[a.id], d = (Math.random() - 0.5) * 0.0016;
    p.price *= 1 + d; p.chg += d * 100;
    document.querySelectorAll(`[data-price="${a.id}"]`).forEach(el => { el.textContent = fmt(p.price, decimals(a.id)); });
    document.querySelectorAll(`[data-chg="${a.id}"]`).forEach(el => {
      el.textContent = `${p.chg >= 0 ? '+' : ''}${fmt(p.chg, 2)} %`; el.className = `small ${p.chg >= 0 ? 'v-bull' : 'v-bear'}`;
    });
  }
}

/* =========================================================================
   Démarrage
   ========================================================================= */
render();
setInterval(tickPrices, 4000);
setInterval(pushSquawk, 25000);
if ('serviceWorker' in navigator && location.protocol !== 'file:') navigator.serviceWorker.register('sw.js').catch(() => {});
