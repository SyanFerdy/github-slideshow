# Polar Macro : notes pour Claude Code

Cette PWA mobile n’utilise ni framework ni étape de build. Pour tester : `python3 -m http.server 8080` depuis ce dossier.

## Architecture
- `js/app.js` : routeur par hash (`#/nom/arg`). Chaque écran se déclare avec `screen(nom, titre, renderFn, { tab, mount, after, noTabs, bare })`. `renderFn` renvoie du HTML (échapper avec `esc()`). `mount` branche les écouteurs après le rendu.
- Les clics passent par délégation : `data-go="route"` sert à naviguer, `data-back` à revenir en arrière, et `data-act="nom"` appelle `ACTIONS.nom(el, event)`.
- L’état vit dans l’objet `state` et `save()` le persiste dans `localStorage` sous le préfixe `pm.`.
- `js/data.js` contient toutes les données de démo et la constante `BRAND`. Pour ajouter un actif : l’ajouter dans `ASSETS` **et** `BIAS`.
- `js/claude.js` contient tous les appels à l’API Claude (SDK `@anthropic-ai/sdk` chargé depuis jsDelivr, version figée) : `streamChat`, `ask`, `testConnection`, `extractJson`. Le modèle par défaut est `claude-opus-5-5`, et l’effort comme la recherche web se règlent dans l’écran Clé API.
- La vue Plus (`FEATURES` dans app.js) liste toutes les fonctionnalités. Il faut l’enrichir à chaque nouvel écran.

## Conventions
- L’interface est en français.
- Garder la mention « informatif, pas un conseil en investissement » sur les écrans de verdict.
- Ne jamais journaliser ni envoyer la clé API ailleurs qu’à api.anthropic.com.
- Après modification d’un fichier mis en cache, incrémenter `CACHE` dans `sw.js`.
