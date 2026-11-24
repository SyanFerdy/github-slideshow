# Polar Macro : application mobile

Application mobile (PWA installable) de terminal d’intelligence macro. Son interface et ses fonctionnalités reprennent celles de polairyx.com. Les analyses IA passent par l’API Claude, avec la clé de l’utilisateur.

## Lancer l’application

Aucune compilation n’est nécessaire. Il suffit de servir le dossier en HTTP :

```bash
cd mobile-app
python3 -m http.server 8080
# puis ouvrir http://localhost:8080 sur le téléphone ou le navigateur
```

Sur mobile, utilisez « Ajouter à l’écran d’accueil » pour l’installer comme une application. Elle s’ouvre alors en plein écran et l’interface reste disponible hors ligne.

## Fonctionnalités

| Domaine | Écrans |
|---|---|
| Compte | Présentation, inscription (e-mail, mot de passe, pays, code parrain, opt-in), connexion par mot de passe ou Magic Link, mot de passe oublié, mode démo |
| Lire le marché | Tableau de bord, biais directionnel des 9 actifs (verdict, conviction, 4 angles, drivers, risque clé), pilote macro avec scénarios, régime de marché, récaps, flux squawk en direct, carte macro et fiches pays |
| Données | Calendrier économique, indicateurs, vue d’ensemble par classe, corrélations, force des devises, COT, taux et anticipations, obligations, saisonnalité |
| Recherche | Recherche bancaire, marchés prédictifs |
| Agir | Opportunités (Pro), support et FAQ, favoris |
| Offres | Basic, Pro, Enterprise, bascule mensuel/annuel, tableau comparatif |
| IA (clé API) | Chat en streaming, actualisation des 9 biais avec recherche web, analyse approfondie d’un actif, impact d’un squawk, récap et pilote macro générés |
| Claude Code | Commande d’export de la clé, contexte de marché à copier en Markdown ou à télécharger en JSON |

Les données de marché sont des **données de démonstration**. Seules les fonctions IA produisent des lectures réelles, et seulement quand une clé est connectée.

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
    └── claude.js         Connexion à l’API Claude
```
