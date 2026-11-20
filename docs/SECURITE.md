# Sécurité de TaskFlow

Ce document décrit les contrôles de sécurité du projet, les corrections appliquées et le registre des exceptions (faux positifs assumés). Il est mis à jour à chaque alerte traitée.

## 1. Les contrôles et leur place dans le pipeline

| Contrôle | Outil | Où | Déclencheur | Ce qu'il protège |
|---|---|---|---|---|
| Secrets (pré-commit) | gitleaks (hook pre-commit) | poste du développeur | `git commit` | un secret qui part dans un commit |
| Secrets (historique) | gitleaks | CI, job `secrets` | PR, push `main`, hebdomadaire | un secret déjà présent dans l'historique |
| Dépendances (SCA) | `npm audit --audit-level=high` | CI, job `dependances` | PR, push `main`, hebdomadaire | dépendances avec une CVE connue |
| Dépendances (veille) | Dependabot | dépôt | planifié | dépendances qui vieillissent |
| Code (SAST) | Semgrep (`p/javascript`, `p/nodejsscan`) | CI, job `sast` | PR, push `main`, hebdomadaire | injection, XSS, `eval`, secrets en dur |
| Image (SCA) | Trivy (bloquant sur CRITICAL) | `release.yml` | push `main` | CVE dans l'image publiée |
| Application (DAST) | OWASP ZAP baseline | CI, job `dast` | PR, push `main`, hebdomadaire | en-têtes, cookies, fuites d'information |
| Durcissement HTTP | en-têtes Nginx | exécution | chaque requête | XSS, clickjacking, fuite d'information |
| Moindre privilège | `permissions:` et actions épinglées par SHA | workflows | toujours | un jeton détourné, une action modifiée |

Le déclenchement hebdomadaire de `security.yml` (lundi, 5h17 UTC) rattrape les CVE publiées après un merge.

## 2. Triage du premier scan (20/11/2026)

Premier passage de la PR #28 : 2 jobs rouges (`dependances`, `dast`), `secrets` et `sast` verts.

| Alerte | Outil | Sévérité | Vrai ou faux positif | Décision |
|---|---|---|---|---|
| nginx Version with Known Vulnerabilities | ZAP | High | vrai (nginx 1.27.5) | image passée en nginx 1.31-alpine |
| CSP Header Not Set | ZAP | Medium | vrai | CSP stricte dans `front/nginx.conf` |
| Missing Anti-clickjacking Header | ZAP | Medium | vrai | `X-Frame-Options` et `frame-ancestors` |
| X-Content-Type-Options, Permissions-Policy, Server | ZAP | Low | vrai | en-têtes et `server_tokens off` |
| COEP, COOP, CORP | ZAP | Low | vrai (isolation d'origine absente) | en-têtes posés |
| Modern Web Application | ZAP | Info | faux positif | IGNORE (registre ci-dessous) |
| Storable and Cacheable Content | ZAP | Info | faux positif | IGNORE (registre ci-dessous) |
| `body-parser` | npm audit (api) | high | vrai, dépendance d'exécution (via Express) | `npm audit fix` |
| `vite` | npm audit (front) | high | vrai, mais outil de build : seul `dist/` est déployé | `vite` 8.3.8 |
| `vitest`, `tinypool`, `@vitest/coverage-v8` et dépendances | npm audit | critical / moderate | vrai, mais `devDependencies` absentes de l'image | `vitest` et `@vitest/coverage-v8` 5.1.1 |

Après correction : `npm audit` donne 0 vulnérabilité (api et front), tests verts, build vert, et le re-scan ZAP ne donne aucun FAIL ni WARN.

## 3. Durcissement HTTP (en-têtes du front)

Posés dans `front/nginx.conf`, sur toutes les réponses (`always`) :

| En-tête | Valeur | Rôle |
|---|---|---|
| `Content-Security-Policy` | `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'` | n'autorise que nos propres ressources, bloque la plupart des XSS |
| `X-Content-Type-Options` | `nosniff` | empêche le navigateur de deviner un type de fichier |
| `X-Frame-Options` | `DENY` | anti-clickjacking pour les anciens navigateurs |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | ne divulgue pas l'URL complète aux sites tiers |
| `Permissions-Policy` | `camera=(), microphone=(), geolocation=(), payment=(), usb=()` | coupe les API matérielles inutilisées |
| `Cross-Origin-Opener-Policy`, `-Resource-Policy`, `-Embedder-Policy` | `same-origin`, `same-origin`, `require-corp` | isolation d'origine (atténuation Spectre) |

Également : `server_tokens off` (version de Nginx masquée), `proxy_hide_header X-Powered-By` et `client_max_body_size 16k`.

Il n'y a pas de `'unsafe-inline'` : le build Vite ne produit ni script ni style en ligne. La politique a été testée dans le navigateur (création, bascule et suppression de tâche : aucune violation en console).

Point d'attention : `add_header` n'est pas hérité par une `location` qui possède le sien. Le `Cache-Control` des assets est donc posé par un `map` et non dans `location /assets/`, pour ne pas y perdre la CSP. Vérifié avec `curl -I` sur `/`, `/health` et un fichier de `/assets/`.

Non couvert ici : `Strict-Transport-Security` se pose sur le proxy HTTPS de production, pas sur ce Nginx qui parle HTTP en interne.

## 4. Dépendances

- `api/` : plus aucune vulnérabilité. `body-parser` (dépendance d'exécution) est corrigé, `vitest` et `@vitest/coverage-v8` passent en 5.1.1.
- `front/` : toutes les dépendances sont des `devDependencies` (le livrable est un ensemble de fichiers statiques servis par Nginx). Les alertes concernaient le serveur de développement et les tests, mais elles s'exécutent en CI et sur les postes : `vite` 8.3.8 et `vitest` 5.1.1.
- Image du front : `nginx:1.31-alpine`.

## 5. Registre des exceptions

Chaque exception est étroite (une règle) et justifiée. Un vrai secret ne s'ajoute jamais ici : on le révoque.

| Outil | Règle | Action | Justification | Responsable | Date | Prochaine revue |
|---|---|---|---|---|---|---|
| ZAP | 10049 Storable and Cacheable Content | IGNORE | informatif : les assets Vite (nom avec hash) sont cachés un an volontairement | Marion | 20/11/2026 | montée de version de ZAP |
| ZAP | 10109 Modern Web Application | IGNORE | informatif : signale seulement une application monopage | Marion | 20/11/2026 | montée de version de ZAP |
| ZAP | 10027 Suspicious Comments | IGNORE | mots-clés dans le bundle minifié de Vite, pas dans notre code | Marion | 20/11/2026 | montée de version de Vite |
| ZAP | 10038, 10020, 10021, 10063, 10036, 10037 | FAIL | en-têtes corrigés : toute régression bloque la PR | Marion | 20/11/2026 | sans objet |
| gitleaks | aucune | sans objet | aucune exception : pas de fichier `.gitleaks.toml` | Marion | 20/11/2026 | sans objet |
| Semgrep | aucune | sans objet | aucun résultat sur 182 règles, aucun `nosemgrep` | Marion | 20/11/2026 | sans objet |

## 6. Limites connues

- La baseline ZAP est passive : elle ne teste ni l'authentification, ni les injections (scan actif), ni le contrôle d'accès. Elle n'a parcouru que 5 à 7 URLs du front et n'a pas exploré `/api`. Elle ne remplace ni un scan actif planifié sur staging, ni un test d'intrusion, ni la revue de code.
- Semgrep (règles publiques, sans compte) peut manquer une injection construite dans une autre fonction que l'appel : le SAST complète la revue, il ne la remplace pas.
- `X-Powered-By: Express` est masqué par le proxy du front. Pistes à traiter dans une PR dédiée : `app.disable('x-powered-by')` et `express.json({ limit: '16kb' })` dans `api/src/app.js`.
- TaskFlow n'a volontairement ni authentification ni multi-utilisateurs : les catégories OWASP A01 (contrôle d'accès) et A07 (authentification) ne sont pas couvertes par ce code.

## 7. En cas de secret exposé

1. Révoquer immédiatement le secret (régénérer la clé ou le jeton chez le fournisseur).
2. Le remplacer par une nouvelle valeur, stockée en secret GitHub ou dans un `.env` hors Git.
3. Purger l'historique si nécessaire (`git filter-repo`) et prévenir l'équipe : l'ancien secret reste dans les clones.
4. Ouvrir un post-mortem, comme pour un incident (voir `INCIDENTS.md`).