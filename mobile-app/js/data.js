// Données de démonstration. Elles sont remplacées par des lectures générées par Claude
// lorsque l'utilisateur a connecté sa clé API (voir claude.js).

export const BRAND = {
  name: 'Polar Macro',
  tagline: 'Terminal d’intelligence macro propulsé par l’IA',
};

export const ASSETS = [
  { id: 'SP500', name: 'S&P 500', cls: 'Indices', price: 6124.3, chg: 0.62 },
  { id: 'NASDAQ', name: 'Nasdaq 100', cls: 'Indices', price: 21987.1, chg: 0.91 },
  { id: 'GOLD', name: 'Or (XAU/USD)', cls: 'Métaux', price: 2641.8, chg: -0.74 },
  { id: 'OIL', name: 'Pétrole WTI', cls: 'Énergie', price: 78.42, chg: 1.85 },
  { id: 'NATGAS', name: 'Gaz naturel', cls: 'Énergie', price: 3.214, chg: -0.12 },
  { id: 'EURUSD', name: 'EUR/USD', cls: 'Forex', price: 1.0712, chg: -0.31 },
  { id: 'USDJPY', name: 'USD/JPY', cls: 'Forex', price: 154.62, chg: 0.44 },
  { id: 'USDCAD', name: 'USD/CAD', cls: 'Forex', price: 1.3958, chg: 0.18 },
  { id: 'BTC', name: 'Bitcoin', cls: 'Crypto', price: 97450, chg: 2.36 },
];

// verdict: 1 haussier, -1 baissier, 0 neutre
export const BIAS = {
  SP500: { v: 1, conv: 84, angles: { macro: 1, fonda: 1, geo: 0, quant: 1 },
    drivers: ['Résultats tech supérieurs aux attentes', 'Détente des taux réels US', 'Flux acheteurs des fonds systématiques'],
    risk: 'Un CPI au-dessus du consensus relancerait le scénario Fed restrictive.' },
  NASDAQ: { v: 1, conv: 78, angles: { macro: 1, fonda: 1, geo: -1, quant: 1 },
    drivers: ['Momentum IA/semi-conducteurs', 'Baisse de la volatilité implicite', 'Rachats d’actions record'],
    risk: 'Nouvelles restrictions export de puces vers la Chine.' },
  GOLD: { v: -1, conv: 71, angles: { macro: -1, fonda: 0, geo: 1, quant: -1 },
    drivers: ['Dollar (DXY) en hausse après le NFP', 'Taux réels en remontée', 'Prises de profits après le record'],
    risk: 'Escalade géopolitique au Moyen-Orient : retour de la demande refuge.' },
  OIL: { v: 1, conv: 76, angles: { macro: 0, fonda: 1, geo: 1, quant: 1 },
    drivers: ['Tensions dans le détroit d’Ormuz', 'Discipline de production OPEP+', 'Baisse des stocks EIA'],
    risk: 'Annonce surprise d’une hausse de quotas OPEP+.' },
  NATGAS: { v: 0, conv: 52, angles: { macro: 0, fonda: 0, geo: 0, quant: -1 },
    drivers: ['Météo douce attendue', 'Stocks proches de la moyenne 5 ans', 'Exportations GNL soutenues'],
    risk: 'Vague de froid précoce sur le nord-est américain.' },
  EURUSD: { v: -1, conv: 68, angles: { macro: -1, fonda: -1, geo: 0, quant: 0 },
    drivers: ['Divergence BCE accommodante / Fed patiente', 'PMI zone euro sous 50', 'Écart de taux 2 ans défavorable'],
    risk: 'Discours plus ferme de la BCE sur l’inflation des services.' },
  USDJPY: { v: 1, conv: 73, angles: { macro: 1, fonda: 1, geo: 0, quant: 1 },
    drivers: ['Différentiel de taux US/Japon', 'BoJ prudente sur la normalisation', 'Carry trade attractif'],
    risk: 'Intervention verbale ou effective du ministère des Finances japonais.' },
  USDCAD: { v: 1, conv: 61, angles: { macro: 1, fonda: 0, geo: 0, quant: 1 },
    drivers: ['Dollar US fort', 'Baisse de taux BoC anticipée', 'Pétrole compensant partiellement'],
    risk: 'Rebond marqué du brut soutenant le CAD.' },
  BTC: { v: 1, conv: 66, angles: { macro: 1, fonda: 1, geo: 0, quant: 0 },
    drivers: ['Entrées nettes sur les ETF spot', 'Appétit pour le risque', 'Offre en baisse sur les plateformes'],
    risk: 'Durcissement réglementaire ou liquidation de positions à levier.' },
};

export const REGIMES = [
  { zone: 'US', label: 'Risk-off', tone: -1 },
  { zone: 'EU', label: 'Neutre', tone: 0 },
  { zone: 'JP', label: 'Expansion', tone: 1 },
  { zone: 'CN', label: 'Fragile', tone: -1 },
  { zone: 'UK', label: 'Stagflation', tone: -1 },
  { zone: 'CA', label: 'Ralentissement', tone: 0 },
  { zone: 'AU', label: 'Neutre', tone: 0 },
  { zone: 'EM', label: 'Reprise', tone: 1 },
];

export const CURRENCIES = [
  { pair: 'EUR/USD', v: -1 }, { pair: 'USD/JPY', v: 1 },
  { pair: 'GBP/USD', v: 0 }, { pair: 'USD/CAD', v: 1 },
];

export const SQUAWK_SEED = [
  { t: '14:30', cc: 'US', sev: 'CRITIQUE', text: 'NFP : +275k vs +200k attendus. Chômage 3,9 %. DXY +0,4 %.', assets: ['GOLD', 'EURUSD', 'SP500'] },
  { t: '14:12', cc: 'IR', sev: 'ÉLEVÉ', text: 'Rapports d’incidents navals près du détroit d’Ormuz, primes de risque en hausse.', assets: ['OIL', 'GOLD'] },
  { t: '13:45', cc: 'EU', sev: 'MOYEN', text: 'Lagarde : « Les risques sur la croissance sont orientés à la baisse. »', assets: ['EURUSD'] },
  { t: '12:02', cc: 'JP', sev: 'MOYEN', text: 'Kanda (MoF) : surveille les mouvements du yen « avec un sentiment d’urgence ».', assets: ['USDJPY'] },
  { t: '10:30', cc: 'UK', sev: 'ÉLEVÉ', text: 'CPI UK 3,2 % a/a vs 3,0 % attendu ; l’inflation des services accélère.', assets: ['GBPUSD'] },
  { t: '09:15', cc: 'CN', sev: 'FAIBLE', text: 'La PBoC maintient ses taux directeurs, injection de liquidités de 200 Md CNY.', assets: ['OIL', 'SP500'] },
  { t: '08:00', cc: 'SA', sev: 'ÉLEVÉ', text: 'OPEP+ : prolongation des réductions volontaires jusqu’à fin T1.', assets: ['OIL', 'USDCAD'] },
];

export const SQUAWK_STREAM = [
  { cc: 'US', sev: 'ÉLEVÉ', text: 'Powell : « Pas d’urgence à baisser les taux. » Les rendements 2 ans montent de 6 pb.', assets: ['SP500', 'GOLD', 'USDJPY'] },
  { cc: 'US', sev: 'MOYEN', text: 'Stocks de brut EIA : -4,2 M barils vs -1,5 M attendus.', assets: ['OIL'] },
  { cc: 'EU', sev: 'MOYEN', text: 'PMI manufacturier allemand 43,1 vs 44,0 attendu.', assets: ['EURUSD'] },
  { cc: 'US', sev: 'CRITIQUE', text: 'CPI core +0,4 % m/m vs +0,3 %. Les marchés repoussent la première baisse de la Fed.', assets: ['SP500', 'NASDAQ', 'GOLD', 'EURUSD'] },
  { cc: 'CA', sev: 'MOYEN', text: 'Emploi Canada : -12k vs +15k attendu, le CAD recule.', assets: ['USDCAD'] },
  { cc: 'US', sev: 'FAIBLE', text: 'La SEC approuve de nouvelles options sur les ETF bitcoin spot.', assets: ['BTC'] },
  { cc: 'RU', sev: 'ÉLEVÉ', text: 'Frappe de drones sur une raffinerie de la Baltique, exportations perturbées.', assets: ['OIL', 'NATGAS'] },
  { cc: 'JP', sev: 'ÉLEVÉ', text: 'Ueda : une hausse de taux en décembre « reste possible ».', assets: ['USDJPY'] },
];

export const DRIVERS = [
  { topic: 'Blocage du détroit d’Ormuz', w: 34, dd: +6, wk: +12,
    impacts: [['OIL', 1], ['GOLD', 1], ['NASDAQ', -1]],
    scenarios: [
      { name: 'Escalade contenue', p: 55, analog: 'Attaques de tankers 2019' },
      { name: 'Fermeture partielle', p: 30, analog: 'Guerre des tankers 1987' },
      { name: 'Désescalade rapide', p: 15, analog: 'Abqaiq 2019' },
    ],
    watch: ['Primes d’assurance maritime', 'Spread Brent-Dubaï', 'Communiqués de l’US Navy'] },
  { topic: 'Une Fed plus restrictive', w: 27, dd: +3, wk: -2,
    impacts: [['EURUSD', -1], ['GOLD', -1], ['SP500', -1]],
    scenarios: [
      { name: 'Statu quo prolongé', p: 62, analog: 'Pause 2006-2007' },
      { name: 'Baisse en mars', p: 28, analog: 'Pivot 2019' },
      { name: 'Hausse supplémentaire', p: 10, analog: 'Fin de cycle 2000' },
    ],
    watch: ['Swaps OIS mars', 'Discours des membres votants', 'Core PCE'] },
  { topic: 'L’inflation britannique accélère', w: 18, dd: -1, wk: +5,
    impacts: [['GBPUSD', 1], ['DAX', -1]],
    scenarios: [
      { name: 'BoE maintient', p: 70, analog: 'Été 2023' },
      { name: 'BoE remonte', p: 30, analog: 'Août 2023' },
    ],
    watch: ['Salaires UK', 'Gilts 2 ans', 'Minutes MPC'] },
  { topic: 'Stimulus chinois', w: 12, dd: -2, wk: -4,
    impacts: [['OIL', 1], ['SP500', 1]],
    scenarios: [
      { name: 'Mesures ciblées', p: 65, analog: 'Septembre 2024' },
      { name: 'Bazooka budgétaire', p: 35, analog: 'Plan 2008' },
    ],
    watch: ['Crédit total (TSF)', 'Minerai de fer', 'CNH'] },
  { topic: 'Rally IA / semi-conducteurs', w: 9, dd: 0, wk: +1,
    impacts: [['NASDAQ', 1], ['SP500', 1]],
    scenarios: [
      { name: 'Poursuite du momentum', p: 58, analog: '1998-1999' },
      { name: 'Rotation sectorielle', p: 42, analog: 'Juillet 2024' },
    ],
    watch: ['Capex des hyperscalers', 'Guidance Nvidia/TSMC', 'Breadth du Nasdaq'] },
];

export const CALENDAR = [
  { day: 'Aujourd’hui', items: [
    { t: '14:30', cc: 'US', ev: 'Inscriptions chômage', imp: 2, prev: '218k', cons: '220k', act: '212k' },
    { t: '16:00', cc: 'US', ev: 'Ventes de logements existants', imp: 1, prev: '3,96M', cons: '3,93M', act: '—' },
    { t: '20:00', cc: 'US', ev: 'Minutes du FOMC', imp: 3, prev: '—', cons: '—', act: '—' },
  ]},
  { day: 'Demain', items: [
    { t: '01:30', cc: 'JP', ev: 'CPI national', imp: 2, prev: '2,5 %', cons: '2,3 %', act: '—' },
    { t: '09:30', cc: 'DE', ev: 'PMI manufacturier', imp: 2, prev: '43,0', cons: '43,5', act: '—' },
    { t: '10:30', cc: 'UK', ev: 'Ventes au détail', imp: 2, prev: '0,3 %', cons: '0,2 %', act: '—' },
    { t: '14:30', cc: 'CA', ev: 'Ventes au détail', imp: 1, prev: '0,4 %', cons: '0,1 %', act: '—' },
  ]},
  { day: 'Vendredi', items: [
    { t: '14:30', cc: 'US', ev: 'Core PCE m/m', imp: 3, prev: '0,3 %', cons: '0,3 %', act: '—' },
    { t: '16:00', cc: 'US', ev: 'Confiance Michigan', imp: 2, prev: '73,0', cons: '73,7', act: '—' },
  ]},
];

export const INDICATORS = [
  { cc: 'US', rows: [['PIB t/t ann.', '2,8 %'], ['CPI a/a', '2,6 %'], ['Chômage', '4,1 %'], ['PMI composite', '54,1'], ['Taux directeur', '4,75 %']] },
  { cc: 'EU', rows: [['PIB t/t', '0,4 %'], ['CPI a/a', '2,0 %'], ['Chômage', '6,3 %'], ['PMI composite', '48,1'], ['Taux directeur', '3,25 %']] },
  { cc: 'JP', rows: [['PIB t/t ann.', '0,9 %'], ['CPI a/a', '2,3 %'], ['Chômage', '2,5 %'], ['PMI composite', '49,8'], ['Taux directeur', '0,25 %']] },
  { cc: 'UK', rows: [['PIB t/t', '0,1 %'], ['CPI a/a', '3,2 %'], ['Chômage', '4,3 %'], ['PMI composite', '49,9'], ['Taux directeur', '4,75 %']] },
];

export const CURRENCY_STRENGTH = [
  ['USD', 82], ['JPY', 64], ['CHF', 58], ['GBP', 51], ['CAD', 40], ['AUD', 37], ['EUR', 29], ['NZD', 22],
];

export const COT = [
  { a: 'GOLD', net: 231400, chg: -12300, longPct: 78 },
  { a: 'OIL', net: 182900, chg: +9800, longPct: 69 },
  { a: 'EURUSD', net: -48200, chg: -15600, longPct: 41 },
  { a: 'USDJPY', net: 61700, chg: +4400, longPct: 63 },
  { a: 'SP500', net: 104500, chg: +22100, longPct: 66 },
  { a: 'BTC', net: -1200, chg: +800, longPct: 48 },
];

export const RATES = [
  { cb: 'Fed', cc: 'US', rate: '4,75 %', next: '18 déc.', hold: 62, cut: 38, hike: 0 },
  { cb: 'BCE', cc: 'EU', rate: '3,25 %', next: '12 déc.', hold: 15, cut: 85, hike: 0 },
  { cb: 'BoJ', cc: 'JP', rate: '0,25 %', next: '19 déc.', hold: 58, cut: 0, hike: 42 },
  { cb: 'BoE', cc: 'UK', rate: '4,75 %', next: '19 déc.', hold: 86, cut: 14, hike: 0 },
  { cb: 'BoC', cc: 'CA', rate: '3,75 %', next: '11 déc.', hold: 30, cut: 70, hike: 0 },
];

export const BONDS = [
  ['US 2A', 4.31, +6], ['US 10A', 4.42, +4], ['DE 10A', 2.34, -2], ['FR 10A', 3.11, +1],
  ['IT 10A', 3.58, -3], ['UK 10A', 4.48, +5], ['JP 10A', 1.08, +2],
];

export const SEASONALITY = {
  GOLD: [1.8, 0.4, -0.6, 0.9, -0.2, -0.8, 1.1, 0.7, 1.5, -0.3, -0.9, 1.2],
  SP500: [1.1, -0.3, 1.0, 1.4, 0.2, 0.1, 1.5, -0.4, -0.9, 0.8, 1.8, 1.4],
  OIL: [0.9, 2.1, 1.7, 2.3, 0.5, -0.4, -0.8, -0.5, -1.4, -1.1, -1.6, -0.2],
  EURUSD: [-0.6, -0.3, 0.4, 0.2, -0.8, 0.1, 0.5, -0.3, -0.5, -0.2, -0.4, 0.9],
};

export const BANK_RESEARCH = [
  { bank: 'Goldman Sachs', title: 'Or : objectif 12 mois relevé à 3 000 $', view: 1, asset: 'GOLD' },
  { bank: 'JPMorgan', title: 'Le dollar reste la devise de l’exceptionnalisme américain', view: 1, asset: 'USD' },
  { bank: 'Morgan Stanley', title: 'S&P 500 : un objectif fin d’année à 6 500', view: 1, asset: 'SP500' },
  { bank: 'Citi', title: 'Pétrole : le marché sera excédentaire en 2025', view: -1, asset: 'OIL' },
  { bank: 'BNP Paribas', title: 'EUR/USD vers 1,03 sur divergence monétaire', view: -1, asset: 'EURUSD' },
];

export const PREDICTION_MARKETS = [
  { q: 'La Fed baisse-t-elle ses taux en décembre ?', yes: 38, src: 'Kalshi', vol: '4,1 M$' },
  { q: 'Le Brent dépasse-t-il 90 $ avant fin janvier ?', yes: 27, src: 'Polymarket', vol: '1,8 M$' },
  { q: 'Récession américaine en 2025 ?', yes: 21, src: 'Polymarket', vol: '9,6 M$' },
  { q: 'Le BTC dépasse-t-il 120 000 $ cette année ?', yes: 33, src: 'Polymarket', vol: '22,4 M$' },
  { q: 'La BoJ relève-t-elle ses taux en décembre ?', yes: 42, src: 'Kalshi', vol: '0,9 M$' },
];

export const OPPORTUNITIES = [
  { asset: 'USDJPY', dir: 1, entry: '154,40', stop: '153,20', target: '157,00', rr: '2,2', status: 'Active' },
  { asset: 'GOLD', dir: -1, entry: '2 650', stop: '2 685', target: '2 580', rr: '2,0', status: 'Active' },
  { asset: 'OIL', dir: 1, entry: '77,80', stop: '75,90', target: '82,00', rr: '2,2', status: 'Cible atteinte' },
  { asset: 'EURUSD', dir: -1, entry: '1,0760', stop: '1,0830', target: '1,0620', rr: '2,0', status: 'Stop touché' },
];

export const RECAPS = [
  { title: 'Récap session US', when: 'Hier, 22:15', text: 'Les indices terminent en hausse portés par la tech. Le dollar se renforce après des données d’emploi solides, l’or recule sous 2 650 $. Le pétrole gagne près de 2 % sur fond de tensions au Moyen-Orient.' },
  { title: 'Récap session Asie', when: 'Aujourd’hui, 08:05', text: 'Le Nikkei progresse avec la faiblesse du yen. La PBoC maintient ses taux et injecte des liquidités. Le cuivre se stabilise.' },
  { title: 'Récap hebdomadaire', when: 'Dimanche', text: 'Semaine dominée par la Fed et l’OPEP+. Le dollar signe sa 3e semaine de hausse, le Nasdaq atteint un plus haut historique, l’or corrige de 2,1 %.' },
];

export const COUNTRIES = [
  { cc: 'US', name: 'États-Unis', risk: 'Modéré', text: 'Croissance résiliente, inflation collante, Fed en pause.' },
  { cc: 'CN', name: 'Chine', risk: 'Élevé', text: 'Immobilier fragile, déflation, soutien budgétaire graduel.' },
  { cc: 'IR', name: 'Iran', risk: 'Critique', text: 'Tensions maritimes dans le Golfe, risque sur l’offre de brut.' },
  { cc: 'RU', name: 'Russie', risk: 'Élevé', text: 'Sanctions énergétiques et frappes sur les infrastructures.' },
  { cc: 'EU', name: 'Zone euro', risk: 'Modéré', text: 'Industrie en contraction, BCE en cycle de baisse.' },
  { cc: 'JP', name: 'Japon', risk: 'Faible', text: 'Normalisation monétaire progressive, yen faible.' },
];

export const CORR_ASSETS = ['SP500', 'GOLD', 'OIL', 'EURUSD', 'USDJPY', 'BTC'];
export const CORR = [
  [1, -0.12, 0.21, 0.18, 0.34, 0.58],
  [-0.12, 1, 0.15, 0.46, -0.52, 0.09],
  [0.21, 0.15, 1, 0.08, 0.11, 0.17],
  [0.18, 0.46, 0.08, 1, -0.61, 0.12],
  [0.34, -0.52, 0.11, -0.61, 1, 0.22],
  [0.58, 0.09, 0.17, 0.12, 0.22, 1],
];

export const COMPARISON = [
  ['Temps de réaction', '> 30 minutes', '< 1 seconde'],
  ['Couverture macro', 'Partielle, manuelle', '24/7, automatisée'],
  ['Moteur d’analyse', 'Intuition', 'IA multi-angles'],
  ['Contexte historique', 'Mémoire', 'Recherche vectorielle IA'],
  ['Lecture directionnelle', '—', 'Biais + conviction + drivers'],
  ['Actifs suivis', '1 à 2', '9 en parallèle'],
  ['Effort requis', 'Plusieurs heures/jour', 'Aucun'],
];

export const TESTIMONIALS = [
  { name: 'Julien', handle: '@jul_fx', style: 'Day trading', stars: 5, text: 'Le squawk me fait gagner un temps fou le matin. Je ne jongle plus entre six onglets.' },
  { name: 'Sarah', handle: '@sarahswing', style: 'Swing', stars: 4, text: 'Les biais avec conviction sont un excellent point de départ pour mes analyses.' },
  { name: 'Marc', handle: '@macro_marc', style: 'Global macro', stars: 5, text: 'Le pilote macro est exactement ce qui me manquait pour hiérarchiser les thèmes.' },
];

export const WORKFLOW = [
  { t: '08:30', title: 'Squawk du matin', text: 'NFP publié, DXY +0,4 %, impact baissier sur l’or.' },
  { t: '09:00', title: 'Biais directionnel mis à jour', text: 'Les 9 actifs recalculés avec leur conviction.' },
  { t: '09:15', title: 'Lecture directionnelle', text: 'Or baissier, conviction élevée, drivers expliqués.' },
  { t: 'En continu', title: 'Suivi en temps réel', text: 'Chaque nouveau choc macro est analysé à la seconde.' },
];

export const COUNTRY_LIST = ['France', 'Belgique', 'Suisse', 'Canada', 'Luxembourg', 'Monaco', 'Maroc', 'Algérie', 'Tunisie', 'Sénégal', 'Côte d’Ivoire', 'Cameroun', 'États-Unis', 'Royaume-Uni', 'Allemagne', 'Espagne', 'Italie', 'Portugal', 'Pays-Bas', 'Autre'];
