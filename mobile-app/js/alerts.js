// Moteur d'alertes : niveaux de prix et suivi de trades (entrée, stop-loss, take-profit).
// Les alertes ne sont évaluées que sur des cotations réelles et fraîches (voir feed.js).
// L'application ne passe aucun ordre : elle prévient, l'utilisateur agit dans son broker.

const LS_ALERTS = 'pm.alerts', LS_LOG = 'pm.alertLog';
const load = (k, d) => { try { return JSON.parse(localStorage.getItem(k) || 'null') ?? d; } catch { return d; } };
const persist = (k, v) => { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* ignoré */ } };

export let alerts = load(LS_ALERTS, []);
export let log = load(LS_LOG, []);
export const saveAlerts = () => { persist(LS_ALERTS, alerts); persist(LS_LOG, log.slice(0, 200)); };

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 6);

/** Alerte de niveau : se déclenche quand le prix franchit `level` (dans un sens ou dans l'autre). */
export function addLevel({ asset, level, price, note = '', proximity = 0 }) {
  const a = { id: uid(), kind: 'level', asset, level, dir: price < level ? 'up' : 'down', note, proximity,
    last: price, created: Date.now(), status: 'active', nearSent: false };
  alerts.unshift(a); saveAlerts(); return a;
}

/** Valide les niveaux d'un trade. Renvoie un message d'erreur ou null. */
export function validateTrade({ side, entry, sl, tp1, tp2 }) {
  const ok = n => n === null || (isFinite(n) && n > 0);
  if (![entry, sl, tp1, tp2].every(ok) || !entry || !sl || !tp1) return 'Renseignez au moins l’entrée, le stop-loss et le TP1.';
  if (side === 'long') {
    if (!(sl < entry)) return 'Achat : le stop-loss doit être sous l’entrée.';
    if (!(tp1 > entry)) return 'Achat : le TP1 doit être au-dessus de l’entrée.';
    if (tp2 && !(tp2 > tp1)) return 'Achat : le TP2 doit être au-dessus du TP1.';
  } else {
    if (!(sl > entry)) return 'Vente : le stop-loss doit être au-dessus de l’entrée.';
    if (!(tp1 < entry)) return 'Vente : le TP1 doit être sous l’entrée.';
    if (tp2 && !(tp2 < tp1)) return 'Vente : le TP2 doit être sous le TP1.';
  }
  return null;
}

/**
 * Trade suivi. `open: true` = déjà en position (pas d'attente d'entrée).
 * États : waiting → open → (tp1) → closed (tp | sl) ; ou cancelled.
 */
export function addTrade({ asset, side, entry, sl, tp1, tp2 = null, price, open = false, note = '', proximity = 0, beAfterTp1 = true }) {
  const t = { id: uid(), kind: 'trade', asset, side, entry, sl, tp1, tp2, note, proximity, beAfterTp1,
    status: open ? 'open' : 'waiting', tp1Hit: false, last: price, created: Date.now(), events: [], near: {} };
  if (open) t.events.push({ at: Date.now(), type: 'open', price });
  alerts.unshift(t); saveAlerts(); return t;
}

export function remove(id) { alerts = alerts.filter(a => a.id !== id); saveAlerts(); }
export function cancel(id) { const a = alerts.find(x => x.id === id); if (a) { a.status = 'cancelled'; saveAlerts(); } }
export function clearLog() { log = []; saveAlerts(); }

const GAP_MS = 3 * 60e3;
const crossed = (prev, cur, level) => (prev < level && cur >= level) || (prev > level && cur <= level);
const pctAway = (cur, level) => Math.abs(cur - level) / level * 100;

/**
 * Évalue toutes les alertes actives d'un actif avec un nouveau prix.
 * Renvoie la liste des notifications à émettre : { title, body, level: 'info'|'good'|'bad', alertId }.
 */
export function evaluate(asset, cur, fmt = String) {
  const out = [];
  const push = (a, title, body, level) => {
    const n = { title, body, level, alertId: a.id, asset, price: cur, at: Date.now() };
    out.push(n); log.unshift(n);
  };
  const now = Date.now();
  for (const a of alerts) {
    if (a.asset !== asset) continue;
    const prev = a.last ?? cur;
    const watching = a.status === 'active' || a.status === 'waiting' || a.status === 'open';
    // Trou de surveillance (app fermée, téléphone verrouillé, réseau coupé) : seul le dernier prix connu est comparé
    // au prix actuel, un aller-retour sur le SL ou le TP pendant ce temps n'est pas visible.
    if (watching && a.lastAt && now - a.lastAt > GAP_MS) {
      const min = Math.round((now - a.lastAt) / 60e3);
      push(a, `⏸️ ${asset} : surveillance interrompue ${min} min`, `Un niveau a pu être touché puis abandonné pendant ce temps. Vérifiez votre position chez votre broker.`, 'bad');
    }

    if (a.kind === 'level' && a.status === 'active') {
      if (a.proximity && !a.nearSent && pctAway(cur, a.level) <= a.proximity && !crossed(prev, cur, a.level)) {
        a.nearSent = true;
        push(a, `${asset} proche de ${fmt(a.level)}`, `Prix ${fmt(cur)}, à moins de ${a.proximity} % du niveau.`, 'info');
      }
      if (crossed(prev, cur, a.level)) {
        a.status = 'triggered'; a.triggeredAt = Date.now(); a.triggerPrice = cur;
        push(a, `🔔 ${asset} : niveau ${fmt(a.level)} atteint`, `${a.dir === 'up' ? 'Franchi à la hausse' : 'Franchi à la baisse'} · prix ${fmt(cur)}${a.note ? ' · ' + a.note : ''}`, 'info');
      }
    }

    if (a.kind === 'trade' && (a.status === 'waiting' || a.status === 'open')) {
      const long = a.side === 'long', S = long ? 'Achat' : 'Vente';
      if (a.status === 'waiting' && (crossed(prev, cur, a.entry) || cur === a.entry)) {
        a.status = 'open'; a.events.push({ at: Date.now(), type: 'entry', price: cur });
        push(a, `▶️ ${asset} : entrée ${fmt(a.entry)} atteinte`, `${S} : placez votre ordre. SL ${fmt(a.sl)} · TP1 ${fmt(a.tp1)}${a.tp2 ? ' · TP2 ' + fmt(a.tp2) : ''}`, 'info');
      }
      if (a.status === 'open') {
        const slHit = long ? cur <= a.sl : cur >= a.sl;
        const tp1Hit = long ? cur >= a.tp1 : cur <= a.tp1;
        const tp2Hit = a.tp2 && (long ? cur >= a.tp2 : cur <= a.tp2);
        if (slHit) {
          a.status = 'closed'; a.result = a.tp1Hit ? 'be' : 'sl'; a.events.push({ at: Date.now(), type: 'sl', price: cur });
          push(a, `🛑 ${asset} : stop-loss ${fmt(a.sl)} touché`, `${S} · prix ${fmt(cur)}. Vérifiez la clôture chez votre broker.`, a.tp1Hit ? 'info' : 'bad');
        } else if (tp2Hit) {
          a.status = 'closed'; a.result = 'tp2'; a.events.push({ at: Date.now(), type: 'tp2', price: cur });
          push(a, `🎯 ${asset} : TP2 ${fmt(a.tp2)} atteint`, `${S} · prix ${fmt(cur)}. Objectif final atteint.`, 'good');
        } else if (tp1Hit && !a.tp1Hit) {
          a.tp1Hit = true; a.events.push({ at: Date.now(), type: 'tp1', price: cur });
          if (!a.tp2) { a.status = 'closed'; a.result = 'tp1'; }
          else if (a.beAfterTp1) { a.slOriginal = a.sl; a.sl = a.entry; }
          push(a, `🎯 ${asset} : TP1 ${fmt(a.tp1)} atteint`, a.tp2
            ? `${S} · prix ${fmt(cur)}.${a.beAfterTp1 ? ` Suggestion : remontez le SL au point d’entrée (${fmt(a.entry)}).` : ''} Prochain objectif TP2 ${fmt(a.tp2)}.`
            : `${S} · prix ${fmt(cur)}. Objectif atteint.`, 'good');
        } else if (a.proximity) {
          for (const [k, lvl, lab] of [['sl', a.sl, 'du stop-loss'], ['tp', a.tp1Hit && a.tp2 ? a.tp2 : a.tp1, 'de l’objectif']]) {
            if (!a.near[k] && pctAway(cur, lvl) <= a.proximity) {
              a.near[k] = true;
              push(a, `⚠️ ${asset} proche ${lab}`, `Prix ${fmt(cur)}, à moins de ${a.proximity} % de ${fmt(lvl)}.`, k === 'sl' ? 'bad' : 'info');
            }
          }
        }
      }
    }
    a.last = cur; a.lastAt = now;
  }
  if (out.length || alerts.some(a => a.asset === asset)) saveAlerts();
  return out;
}

/** P&L en % d'un trade au prix courant */
export function pnl(t, cur) {
  if (!cur || t.status === 'waiting') return null;
  const ref = t.events.find(e => e.type === 'entry' || e.type === 'open')?.price ?? t.entry;
  return (t.side === 'long' ? cur / ref - 1 : ref / cur - 1) * 100;
}

/** Ratio risque/rendement planifié */
export const rr = t => Math.abs((t.tp2 || t.tp1) - t.entry) / Math.abs(t.entry - (t.slOriginal ?? t.sl));
