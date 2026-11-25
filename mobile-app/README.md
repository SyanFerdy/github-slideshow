# Polar Macro : application mobile

Application mobile (PWA installable) de terminal d’intelligence macro. Son interface et ses fonctionnalités reprennent celles de polairyx.com. Les analyses IA passent par l’API Claude, avec la clé de l’utilisateur.

## Lancer l’application

Aucune compilation n’est nécessaire.

**Sur ordinateur (test)** :

```bash
cd mobile-app
python3 -m http.server 8080
# ouvrir http://localhost:8080
```

**Sur téléphone, l’application doit être servie en HTTPS** : les notifications, le service worker et l’installation ne fonctionnent pas sur une adresse `http://192.168…` du réseau local. Le plus simple est d’activer GitHub Pages sur ce dépôt (Settings › Pages, branche choisie, dossier racine), puis d’ouvrir `https://<utilisateur>.github.io/github-slideshow/mobile-app/`.

Sur le téléphone, utilisez ensuite « Ajouter à l’écran d’accueil » pour l’installer comme une application. Elle s’ouvre alors en plein écran et l’interface reste disponible hors ligne.

## Fonctionnalités

| Domaine | Écrans |
|---|---|
| Compte | Présentation, inscription (e-mail, mot de passe, pays, opt-in), connexion par mot de passe ou Magic Link, mot de passe oublié, mode démo |
| Lire le marché | Tableau de bord, biais directionnel des 9 actifs (verdict, conviction, 4 angles, drivers, risque clé), pilote macro avec scénarios, régime de marché, récaps, flux squawk (simulé), carte macro et fiches pays |
| Données | Calendrier économique, indicateurs, vue d’ensemble par classe, corrélations, force des devises, COT, taux et anticipations, obligations, saisonnalité |
| Recherche | Recherche bancaire, marchés prédictifs |
| Agir | **Alertes & trades** (niveau atteint, entrée, SL, TP1/TP2, approche d’un niveau, SL au point d’entrée après le TP1), idées de setups (exemples), support et FAQ, favoris |
| IA (clé API) | Chat en streaming, actualisation des 9 biais avec recherche web, analyse approfondie d’un actif, impact d’un squawk, récap et pilote macro générés |
| Claude Code | Commande d’export de la clé, contexte de marché à copier en Markdown ou à télécharger en JSON |

Aucune partie paiement ni abonnement : toutes les fonctionnalités sont accessibles.

## Prix réels et alertes

| Actif | Source | Clé |
|---|---|---|
| BTC | Kraken XBT/USD | non |
| Or | Kraken PAXG/USD (jeton adossé à l’or, proche du spot), ou XAU/USD via Twelve Data | non |
| EUR/USD, USD/JPY, USD/CAD | Coinbase (taux agrégés) | non |
| S&P 500, Nasdaq, pétrole WTI, gaz naturel | Twelve Data (symboles modifiables) | oui, gratuite |

- Les prix sont relevés toutes les 20 s (toutes les 5 min pour Twelve Data). Un actif sans flux réel affiche sa valeur de démonstration en grisé avec la mention « démo ».
- Les alertes ne se déclenchent **que sur une cotation réelle et fraîche**. Elles sont enregistrées sur l’appareil et survivent à un rechargement.
- L’application **ne passe aucun ordre** : elle notifie, et vous agissez dans votre broker. Les prix du flux peuvent différer de ceux de votre broker (spread, horaires, instrument).
- Sans serveur, la surveillance ne tourne que lorsque l’application est ouverte. Au retour dans l’app, tout niveau franchi entre-temps est détecté et notifié. Pour des alertes téléphone verrouillé, il faudrait ajouter un serveur avec Web Push.

Les biais, squawks, indicateurs, calendrier et autres données de marché restent des **données de démonstration**. Le flux squawk est explicitement marqué « simulé ». Les fonctions IA produisent des lectures réelles quand une clé Claude est connectée.

## Clé API Claude

Pour connecter la clé : **Réglages › Clé API Claude** (ou l’icône de clé en haut de l’écran). Collez une clé créée sur https://console.anthropic.com puis appuyez sur **Tester**.

- La clé est stockée **uniquement sur l’appareil** (`localStorage`) et envoyée directement à `api.anthropic.com`, via le SDK officiel `@anthropic-ai/sdk`.
- Les réglages proposent le modèle (Claude Opus 5.5 par défaut, Sonnet 5.5 ou Haiku 5.5), le niveau d’effort et la recherche web.
- Le repli automatique côté serveur (`fallbacks: "default"`) est activé : si le modèle refuse une requête, une autre tentative est faite automatiquement. Il n’est pas disponible sur Haiku.
- ⚠️ Pour une publication grand public, ne laissez pas les utilisateurs appeler l’API depuis le navigateur avec une clé partagée. Placez un petit serveur proxy entre l’application et l’API.

## Utilisation avec Claude Code

1. Claude Code accepte la même clé : `export ANTHROPIC_API_KEY="sk-ant-…"` puis `claude`.
2. L’écran **Plus › Claude Code** exporte le contexte de marché courant, à coller dans une session Claude Code.
3. Pour faire évoluer l’application, lancez `claude` dans ce dossier. Le fichier `CLAUDE.md` lui décrit l’architecture.

## Structure

```
mobile-app/
├── index.html            Point d’entrée
├── manifest.webmanifest  Manifeste PWA
├── sw.js                 Service worker (cache hors ligne)
├── icon.svg
├── css/app.css           Thème sombre/clair, composants mobiles
└── js/
    ├── app.js            Routeur, écrans, actions
    ├── data.js           Données de démonstration et nom de marque
    ├── feed.js           Flux de prix réels (Kraken, Coinbase, Twelve Data)
    ├── alerts.js         Moteur d’alertes niveau / entrée / SL / TP
    └── claude.js         Connexion à l’API Claude
```
