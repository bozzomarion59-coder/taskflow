# Post-mortem : API TaskFlow indisponible en production (19/11/2026)

Post-mortem sans blâme : on cherche les causes du système, pas un coupable.

## Résumé

Le 19/11/2026, l'API de production ne démarrait plus à cause d'une variable d'environnement mal nommée (`DATABASE_UR` au lieu de `DATABASE_URL`). Le front (nginx) répondait 502 sur toutes les routes `/api`. La base de données n'a jamais été touchée et aucune donnée n'a été perdue. L'alerte `TaskFlowApiDown` a prévenu l'équipe, le service a été rétabli en moins de 6 minutes.

- Impact utilisateur : application inutilisable (502) pendant environ 5 min 40.
- Gravité : critique (indisponibilité totale), sans perte de données.
- Environnement : production (Docker Compose).

## Chronologie (heure de Paris)

| Heure | Événement |
|---|---|
| 15:35:07 | Début de l'incident : `.env` de production modifié, l'API redémarre en boucle (`Restarting (1)`) |
| ~15:37 | Alerte `TaskFlowApiDown` passée en firing, mail `[FIRING:1]` reçu |
| 15:39 | Diagnostic : `curl /health` renvoie 502, `docker compose ps` montre l'API en redémarrage |
| 15:40 | Logs de l'API : `ECONNREFUSED 127.0.0.1:5432`, puis `.env` : variable `DATABASE_UR` |
| 15:40:24 | Correction de `.env` (`DATABASE_UR` renommée en `DATABASE_URL`) et relance de l'API |
| 15:40:45 | Service rétabli : API `healthy`, `/health` renvoie `ok`, création de tâche OK |
| 15:41 | Mail `[RESOLVED]` reçu, Grafana repassé à OK |

## Indicateurs

- MTTD (détection) : environ 2 min 30 entre le début et l'alerte (sonde périodique, règle `for: 1m`, `group_wait` 10 s).
- MTTR depuis le début : environ 5 min 40.
- MTTR depuis l'alerte : environ 3 min 45.
- Le mail `[RESOLVED]` arrive après la reprise à cause de `group_interval: 2m`.

## Cause racine

L'API lit sa connexion à la base dans `DATABASE_URL`. La variable étant absente (faute de frappe dans `.env`), `config.js` utilise silencieusement une valeur par défaut `localhost`. Dans un conteneur, `localhost` n'est pas la base : la connexion est refusée (`ECONNREFUSED`), l'API s'arrête au démarrage, Docker la relance en boucle et nginx renvoie 502.

## Les 5 pourquoi

1. Pourquoi les utilisateurs ont-ils eu des 502 ? Parce que l'API était en boucle de redémarrage et nginx n'avait plus de service à joindre.
2. Pourquoi l'API redémarrait-elle ? Parce qu'elle plantait au démarrage avec `ECONNREFUSED 127.0.0.1:5432`.
3. Pourquoi visait-elle `127.0.0.1` ? Parce que `DATABASE_URL` était absente et que `config.js` retombe sur `localhost` par défaut.
4. Pourquoi `DATABASE_URL` était-elle absente ? Parce que le `.env` contenait `DATABASE_UR` (faute de frappe).
5. Pourquoi cette faute est-elle arrivée jusqu'à la production sans être vue ? Parce que rien ne valide la configuration au démarrage : le fallback silencieux transforme une erreur de config en erreur réseau trompeuse.

## Ce qui a bien fonctionné

- L'alerte a détecté la panne avant tout signalement humain et le mail contenait le lien vers ce runbook.
- Le diagnostic a suivi un chemin simple : santé, état des conteneurs, logs, configuration.
- La base de données, sur son propre volume, n'a pas été affectée.

## Ce qui a moins bien fonctionné

- Le message `ECONNREFUSED` ne désigne pas la vraie cause (variable mal nommée) et a retardé le diagnostic.
- Une relance manuelle de `docker compose` sans `IMAGE_TAG` a pris `latest` depuis `.env` au lieu du tag déployé (`f4ccdcd`). Il a fallu remettre le bon tag.
- Après un changement de branche, des fichiers montés en bind-mount étaient obsolètes et ont perturbé Grafana : il a fallu recréer la stack de monitoring.
- Le panneau « Erreurs 5xx » reste à 0 % pendant cette panne : les 502 sont produits par nginx, pas par l'API, donc invisibles pour les métriques de l'application. Seule la sonde `/health` les voit.
- Un rollback d'image n'aurait rien corrigé : la cause est dans la configuration, pas dans le code déployé.

## Actions

| Action | Type | Suivi |
|---|---|---|
| Refuser de démarrer en production sans `DATABASE_URL`, avec message explicite | Prévention | Issue #26 |
| Vérifier les variables obligatoires dans `deploy.sh` avant tout `docker compose up` | Prévention | À créer |
| Toujours passer par `deploy.sh` (ou `IMAGE_TAG=<tag>` explicite) pour relancer un service | Processus | Documenté dans le runbook |
| Ajouter une règle d'alerte sur les 502 du front (ou un panneau basé sur la sonde) | Détection | À créer |
| Recréer la stack de monitoring (`up -d --force-recreate`) après un changement de branche | Processus | Documenté dans le runbook |

## Annexes

- Issue d'amélioration : https://github.com/bozzomarion59-coder/taskflow/issues/26
- Règle d'alerte : `TaskFlowApiDown` (`monitoring/prometheus/rules/taskflow.yml`).