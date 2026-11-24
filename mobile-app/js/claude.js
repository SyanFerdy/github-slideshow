// Connexion à l'API Claude avec la clé fournie par l'utilisateur.
// Le SDK officiel est chargé à la demande depuis un CDN (aucune étape de build).
// La clé reste dans le stockage local de l'appareil et n'est envoyée qu'à api.anthropic.com.

const SDK_URL = 'https://cdn.jsdelivr.net/npm/@anthropic-ai/sdk@1.6.0/+esm';
const LS = 'pm.claude';

export const MODELS = [
  { id: 'claude-opus-5-5', label: 'Claude Opus 5.5 (recommandé)' },
  { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5 (rapide)' },
  { id: 'claude-haiku-5-5', label: 'Claude Haiku 5.5 (économique)' },
];
export const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];

const DEFAULTS = { apiKey: '', model: 'claude-opus-5-5', effort: 'medium', webSearch: true };

export function getConfig() {
  try { return { ...DEFAULTS, ...JSON.parse(localStorage.getItem(LS) || '{}') }; }
  catch { return { ...DEFAULTS }; }
}
export function saveConfig(patch) {
  const cfg = { ...getConfig(), ...patch };
  try { localStorage.setItem(LS, JSON.stringify(cfg)); } catch { /* stockage indisponible */ }
  _client = null;
  return cfg;
}
export function isConnected() { return !!getConfig().apiKey; }
export function maskKey(k) { return k ? `${k.slice(0, 10)}…${k.slice(-4)}` : ''; }

let _sdk = null, _client = null;
async function client() {
  const { apiKey } = getConfig();
  if (!apiKey) throw new Error('Aucune clé API configurée. Ouvrez Réglages › Clé API Claude.');
  if (!_sdk) _sdk = (await import(SDK_URL)).default;
  if (!_client) _client = new _sdk({ apiKey, dangerouslyAllowBrowser: true });
  return _client;
}

// Paramètres communs : effort choisi, et repli automatique côté serveur si le modèle refuse
// (non disponible sur Haiku).
function baseParams(cfg) {
  const p = {
    model: cfg.model,
    output_config: { effort: cfg.effort },
  };
  if (cfg.model !== 'claude-haiku-5-5') {
    p.betas = ['server-side-fallback-2026-07-01'];
    p.fallbacks = 'default';
  }
  return p;
}

function tools(cfg, useWeb) {
  return useWeb && cfg.webSearch ? [{ type: 'web_search_20260209', name: 'web_search', max_uses: 5 }] : undefined;
}

function textOf(msg) {
  if (msg.stop_reason === 'refusal') return '⚠️ La requête a été refusée par le modèle.';
  return msg.content.filter(b => b.type === 'text').map(b => b.text).join('');
}

function explainError(e) {
  const s = e?.status;
  if (s === 401) return 'Clé API invalide (401). Vérifiez la clé dans les réglages.';
  if (s === 403) return 'Accès refusé (403) : la clé n’a pas les droits nécessaires.';
  if (s === 429) return 'Limite de requêtes atteinte (429). Réessayez dans un instant.';
  if (s === 529 || s >= 500) return 'Le service Claude est momentanément indisponible. Réessayez.';
  if (e?.name === 'APIConnectionError' || /fetch|network/i.test(e?.message || '')) return 'Connexion impossible à l’API Claude (réseau).';
  return e?.message || String(e);
}

/** Vérifie la clé avec une requête minimale. */
export async function testConnection() {
  try {
    const c = await client();
    const cfg = getConfig();
    const msg = await c.beta.messages.create({
      ...baseParams(cfg), output_config: { effort: 'low' }, max_tokens: 64,
      messages: [{ role: 'user', content: 'Réponds uniquement : OK' }],
    });
    return { ok: true, text: textOf(msg).trim(), model: msg.model };
  } catch (e) { return { ok: false, text: explainError(e) }; }
}

/**
 * Chat en streaming. `history` est une liste {role, content}. `onText` reçoit chaque fragment.
 */
export async function streamChat({ system, history, onText, useWeb = true, signal }) {
  const c = await client();
  const cfg = getConfig();
  try {
    const stream = c.beta.messages.stream({
      ...baseParams(cfg),
      max_tokens: 64000,
      system,
      tools: tools(cfg, useWeb),
      messages: history,
    }, { signal });
    for await (const ev of stream) {
      if (ev.type === 'content_block_delta' && ev.delta.type === 'text_delta') onText(ev.delta.text);
    }
    const final = await stream.finalMessage();
    if (final.stop_reason === 'refusal') onText('\n\n⚠️ La requête a été refusée par le modèle.');
    return final;
  } catch (e) {
    if (e?.name === 'APIUserAbortError') return null;
    throw new Error(explainError(e));
  }
}

/** Requête simple, renvoie le texte complet. */
export async function ask({ system, prompt, useWeb = false, maxTokens = 16000 }) {
  const c = await client();
  const cfg = getConfig();
  try {
    const stream = c.beta.messages.stream({
      ...baseParams(cfg), max_tokens: maxTokens, system,
      tools: tools(cfg, useWeb),
      messages: [{ role: 'user', content: prompt }],
    });
    return textOf(await stream.finalMessage());
  } catch (e) { throw new Error(explainError(e)); }
}

/** Extrait le dernier objet JSON d'une réponse texte. */
export function extractJson(text) {
  const fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const src = fence ? fence[1] : text;
  const start = src.indexOf('{'), end = src.lastIndexOf('}');
  if (start < 0 || end < start) throw new Error('Réponse JSON introuvable.');
  return JSON.parse(src.slice(start, end + 1));
}

export const SYSTEM_ANALYST = `Tu es l'analyste macro d'un terminal de trading mobile francophone.
Tu lis les événements macroéconomiques (banques centrales, OPEP+, CPI, NFP, géopolitique) et tu en déduis un biais directionnel (haussier, baissier ou neutre) avec un niveau de conviction, pour 9 actifs : SP500, NASDAQ, GOLD, OIL, NATGAS, EURUSD, USDJPY, USDCAD, BTC.
Réponds en français, de façon concise et structurée, adaptée à un écran de téléphone (paragraphes courts, listes à puces).
Explique toujours le « pourquoi » selon 4 angles : macroéconomique, fondamental, géopolitique, quantitatif, et termine par le risque principal.
Ce que tu fournis est une lecture d'information, pas un conseil en investissement : la décision reste à l'utilisateur.`;
