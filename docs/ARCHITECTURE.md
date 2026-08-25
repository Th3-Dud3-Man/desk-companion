# Cadence — Architecture

> Poste de travail macOS pour psychologue : agenda, présences, paiements, historique,
> statistiques. Hors-ligne d'abord, local d'abord, zéro coût récurrent.

---

## 1. Vision produit

Une seule application ouverte toute la journée, qui remplace l'agenda + la feuille
d'appel + le registre de paiements + le tableur de suivi.

La boucle centrale doit tenir en **un geste** :

```
J'ouvre l'app  →  ma journée est déjà là  →  [Présent]  →  [70 € · Carte]  →  c'est enregistré
```

Tout le reste de l'application est subordonné à cette boucle. Une fonctionnalité qui
ajoute un clic à ce chemin doit être déplacée hors du chemin, pas ajoutée dessus.

Trois principes non négociables :

1. **Rien de faux.** Un bouton affiché fait ce qu'il annonce. Pas de fausse synchro,
   pas de statistique décorative, pas d'export qui ne produit pas de fichier.
2. **Rien ne se perd.** Chaque écriture est transactionnelle et durable avant que
   l'interface ne confirme quoi que ce soit.
3. **Rien ne sort du Mac.** Aucune donnée patient n'est transmise à un service tiers,
   par défaut et sans exception silencieuse.

---

## 2. Contraintes et ce qu'elles éliminent

| Contrainte | Conséquence architecturale |
|---|---|
| 1 utilisatrice, 1 poste | Pas de multi-tenant, pas d'authentification, pas de serveur |
| Données de santé | Stockage local, pas de cloud, surface réseau minimale |
| Hors-ligne d'abord | La base locale est *la* source de vérité, pas un cache |
| Coût ≈ 0 | Aucun abonnement, aucun runtime payant, aucune dépendance commerciale |
| Utilisée 6 h/jour | Latence perçue nulle : tout est en mémoire, écrit en arrière-plan |
| Vraie app macOS | Bundle `.app`, icône, menus, raccourcis, fenêtre native |

Ces contraintes éliminent d'emblée : Electron (poids, look non natif, dépendances),
un backend (coût + confidentialité + inutile à un poste), Core Data + CloudKit
(synchronisation cloud non souhaitée, modèle opaque), et toute base de données
embarquée tierce.

---

## 3. Stack retenue

**Swift 6 · SwiftUI (+ AppKit ponctuel) · SQLite système · EventKit · zéro dépendance.**

### 3.1 Pourquoi Swift/SwiftUI et pas un hybride

Ce n'est pas un choix par défaut ; c'est le seul qui satisfait simultanément trois
exigences du cahier des charges :

- **EventKit** (§ 3.2) n'est accessible qu'en natif. C'est la fonctionnalité qui
  supprime le plus de friction de toute l'application.
- **Densité + fluidité sur 6 heures d'usage.** Défilement natif, `List` virtualisée,
  typographie SF avec chiffres tabulaires, respect automatique du mode sombre, de
  « Réduire les animations » et des tailles de texte système.
- **Conventions macOS gratuites** : barre de menus réelle, `⌘,` pour les réglages,
  plein écran, restauration de fenêtre, services d'impression → PDF.

Un hybride (Electron/Tauri) aurait imposé de réimplémenter tout cela à la main,
moins bien, et aurait fermé la porte à EventKit.

### 3.2 Pourquoi EventKit couvre Apple *et* Google Calendar

C'est la décision la plus importante du projet.

Sur macOS, un compte Google ajouté dans **Réglages Système → Comptes Internet**
expose ses calendriers via **CalDAV**, et ces calendriers apparaissent dans EventKit
exactement comme les calendriers iCloud ou locaux. Une seule intégration, donc :

| | EventKit | Google Calendar API |
|---|---|---|
| Couvre Apple Calendar | oui | non |
| Couvre Google Calendar | oui (via Comptes Internet) | oui |
| OAuth / écran de consentement | non | oui |
| Secret client dans l'app | non | oui (et non protégeable dans une app de bureau) |
| Fonctionne hors-ligne | oui (cache système) | non |
| Données transitant par un tiers | aucune | requêtes sortantes |
| Coût / quota | aucun | quota projet Google Cloud |
| Code à maintenir | ~1 service | OAuth + refresh + pagination + quotas |

Le choix est sans ambiguïté. Le prix à payer — l'utilisatrice doit avoir ajouté son
compte Google au Mac — est un réglage macOS de trente secondes qu'elle a très
probablement déjà fait, et l'onboarding l'explique avec un lien direct vers le
panneau système.

**Le calendrier reste en lecture seule.** Cadence n'écrit jamais dans l'agenda : le
risque d'abîmer l'agenda réel de l'utilisatrice n'est pas compensé par un gain.

### 3.3 Pourquoi SQLite en direct plutôt que SwiftData/Core Data/GRDB

- **SwiftData** : jeune, comportement d'observation instable selon les versions de
  macOS, migrations peu contrôlables, et impose macOS 14+ sur tout le modèle.
- **Core Data** : lourd, modèle graphique, requêtes analytiques (statistiques)
  pénibles et lentes comparées à du SQL agrégé.
- **GRDB** : excellent, mais c'est une dépendance externe pour ~250 lignes de
  code que l'on maîtrise entièrement.
- **SQLite système** : présent sur tous les Mac, format ouvert et pérenne (le fichier
  reste lisible dans 20 ans avec n'importe quel outil), transactions ACID, WAL,
  agrégations SQL rapides pour les statistiques, et **compilable sur Linux** — ce qui
  permet de tester réellement tout le cœur métier en intégration continue.

Un mince habillage typé (`SQLiteDatabase`, `Statement`, `Row`) suffit ; il est
verrouillé par un `NSRecursiveLock` et ouvert en `SQLITE_OPEN_FULLMUTEX`.

---

## 4. Découpage en modules

```
CadenceCore          ← Foundation pur. Compile et se teste sur Linux ET macOS.
├── Model            Entités, énumérations, Money, plages de dates
├── Storage          Habillage SQLite, migrations, dépôts (repositories)
├── Domain           Moteur d'habitudes, statistiques, rythme, rapprochement, undo
├── Export           CSV (Excel-FR), rapport HTML → PDF
└── Support          Normalisation de texte, distance de chaînes, formatage

Cadence (exécutable) ← macOS uniquement
├── App              @main, AppModel observable, coordination undo, commandes menu
├── Design           Jetons de design et composants réutilisables
├── Views            Aujourd'hui, Agenda, Patients, Finances, Réglages, Palette ⌘K
└── Services         Synchronisation EventKit, génération PDF, sauvegardes
```

La frontière est stricte : **`CadenceCore` n'importe ni SwiftUI, ni AppKit, ni
EventKit.** C'est ce qui rend le cœur testable en CI Linux et ce qui garantit que la
logique métier ne se dissout pas dans les vues.

---

## 5. Modèle de données

Toutes les dates sont stockées en secondes Unix (`INTEGER`), tous les montants en
**centimes** (`INTEGER`) — jamais de flottant pour de l'argent. Les identifiants sont
des UUID en `TEXT`.

```
patient(id, display_name, first_name, last_name, email, phone, colour_seed,
        notes, default_amount_cents, default_method, archived, is_demo,
        created_at, updated_at)

patient_alias(patient_id, alias_normalised)          ← rapprochement calendrier

consultation(id, patient_id?, title, source, external_event_id?,
             external_calendar_id?, external_occurrence_key?,
             scheduled_start, scheduled_end,
             actual_start?, actual_end?,
             status, location, notes, sync_state, is_demo,
             created_at, updated_at)

payment(id, consultation_id?, patient_id, amount_cents, currency, method,
        paid_at, note, is_demo, created_at)

action_log(id, entity_type, entity_id, action, detail, at)   ← historique + audit

calendar_subscription(calendar_id, title, colour_hex, enabled, last_sync_at,
                      last_status, last_message)

setting(key, value)
```

### Statuts de consultation

```
scheduled → confirmed → inProgress → attended
         ↘ absent
         ↘ cancelled
```

`attended` (« Présent ») est atteignable **en un clic depuis n'importe quel état** :
le graphe ci-dessus décrit les transitions naturelles, pas des contraintes imposées à
l'utilisatrice.

### Heures prévues vs. heures réelles

`scheduled_start/end` viennent du calendrier. `actual_start/end` ne sont écrits que
si l'utilisatrice utilise explicitement **Démarrer** / **Terminer**.

Décision : **marquer « Présent » ne fabrique aucune heure réelle.** Si elle pointe
ses présences en fin de journée, inventer une heure d'arrivée produirait un
historique faux. Les statistiques de durée réelle n'utilisent que les consultations
qui ont de vraies heures, et le disent.

---

## 6. Stratégie hors-ligne

La base locale **est** la source de vérité. Il n'y a pas de « mode hors-ligne » :
il y a l'application, et une couche de lecture de calendrier optionnelle par-dessus.

- Fichier : `~/Library/Application Support/Cadence/cadence.sqlite3`
- `journal_mode = WAL` → lectures concurrentes, résistance aux arrêts brutaux
- `synchronous = FULL` → une écriture confirmée à l'écran est une écriture sur disque
- `foreign_keys = ON` → intégrité référentielle garantie par le moteur
- Chaque mutation est encapsulée dans une transaction ; l'interface n'affiche la
  confirmation qu'après le `COMMIT`

Sans réseau, **tout** fonctionne : agenda déjà synchronisé, patients, présences,
paiements, historique, statistiques, exports. Seule la récupération de *nouveaux*
événements de calendrier nécessite que le système ait lui-même rafraîchi ses comptes.

### Sauvegardes

Au premier lancement de chaque jour, un instantané est créé via l'API
`sqlite3_backup` (sûre en WAL, contrairement à une copie de fichier) dans
`.../Cadence/Backups/`. Les 14 derniers sont conservés. Restauration et export
manuels depuis les Réglages.

---

## 7. Stratégie de synchronisation

Unidirectionnelle : **Calendrier → Cadence**. Jamais l'inverse.

- **Fenêtre** : 60 jours en arrière, 180 jours en avant, resynchronisée à
  l'ouverture, au changement de jour, et sur notification `EKEventStoreChanged`.
- **Identité d'une occurrence** : `eventIdentifier + date de début de l'occurrence`.
  EventKit réutilise le même `eventIdentifier` pour toutes les occurrences d'un
  événement récurrent ; sans la date, un rendez-vous hebdomadaire s'écraserait
  lui-même. C'est la principale source de doublons dans ce type d'intégration.
- **Modification** : les horaires sont mis à jour, sauf si la consultation est déjà
  `attended`/`absent` ou porte un paiement → elle est alors marquée `conflict` et
  signalée à l'utilisatrice, qui tranche.
- **Suppression** : si la consultation est intacte (`scheduled`, sans paiement) elle
  est supprimée silencieusement ; sinon elle est marquée `orphaned` et conservée —
  **on ne détruit jamais un paiement enregistré parce qu'un événement a bougé.**
- **État visible** : chaque calendrier affiche `synchronisé · il y a 3 min`,
  `en attente`, `hors ligne` ou `erreur : …`. Jamais d'échec silencieux.

---

## 8. Apprentissage du paiement habituel

Statistique locale, déterministe, explicable. **Pas d'IA** : sur 5 à 20 points de
données par patient, une pondération par récence bat n'importe quel modèle, et
surtout elle est prévisible et justifiable à l'écran.

Pour un patient, sur ses 24 derniers paiements :

```
poids(p)   = 0,5 ^ (âge_en_jours(p) / 90)        demi-vie de 90 jours
groupe(p)  = (montant, moyen de paiement)         couple exact
score(g)   = Σ poids(p) pour p ∈ g
part       = score(meilleur) / Σ score
confiance  = part × (1 − e^(−n_meilleur / 2,5))   amortissement par taille d'échantillon
```

Le badge **« Paiement habituel »** n'apparaît que si `confiance ≥ 0,55` **et**
`n_meilleur ≥ 3`. En dessous : « Dernier paiement » (si au moins un), sinon le tarif
par défaut du cabinet. L'origine de la suggestion est **toujours affichée** —
l'utilisatrice sait pourquoi l'application propose ce montant.

Propriétés voulues :

- 5 × (70 €, carte) → confiance 0,87 → habitude établie.
- 2 × (70 €, carte) → bloqué par le seuil `n ≥ 3` → affiché comme « dernier paiement ».
  L'application ne prétend pas savoir avant d'avoir vu.
- 5 × (70 €, carte) + 1 exception récente (60 €, espèces) → confiance ≈ 0,71 →
  **l'habitude tient.** Une erreur ponctuelle ne redéfinit pas le comportement (§ 10).
- Les alternatives proposées sont les autres groupes réellement observés, puis les
  moyens de paiement configurés — jamais moins de deux choix.

Le montant et le moyen restent modifiables en un clic, à tout moment.

---

## 9. Structure de l'interface

Fenêtre unique, cinq destinations, barre latérale compacte.

```
┌────────────┬──────────────────────────────────────────┬─────────────────┐
│ Aujourd'hui│  Mardi 25 août                           │  Journée        │
│ Agenda     │  Prochain · 14:00 Jean D. dans 12 min    │  encaissé 210 € │
│ Patients   │  ────────────────────────────────────    │  4 / 6 traités  │
│ Finances   │  09:00 ✓ Camille M.      70 € carte      │  espèces  70 €  │
│ Réglages   │  10:00 ✗ Marc L.         absent          │  carte   140 €  │
│            │  ──── maintenant ───────────────────     │                 │
│            │  14:00   Jean Dupont   [Présent][Absent] │  à traiter  2   │
│            │  15:00   Sofia B.                        │                 │
└────────────┴──────────────────────────────────────────┴─────────────────┘
```

**Aujourd'hui** est l'écran par défaut et concentre 90 % de l'usage. Ce n'est pas une
grille horaire à l'échelle (qui gaspille l'espace des trous) mais un **rail
chronologique** : les créneaux se suivent, une ligne « maintenant » les sépare en
passé / à venir, et les trous sont matérialisés discrètement sans consommer de hauteur
proportionnelle.

Après **[Présent]**, la bande de paiement se déplie *dans la ligne* — pas de fenêtre
modale, pas de navigation :

```
  14:00   Jean Dupont   ✓ présent
          ┌ 70 € · Carte ─────────┐  ⏎        Paiement habituel · 6 paiements
          └───────────────────────┘  Espèces   Chèque   Autre…   Plus tard
```

Après **[Absent]** : aucun paiement n'est demandé. Une action secondaire discrète
« Facturer l'absence… » reste disponible dans le menu contextuel pour les cabinets
qui facturent les annulations tardives.

### Décisions UX principales

- **Aucune confirmation sur les actions courantes.** Enregistrer un paiement est
  immédiat. Le filet de sécurité est un **annuler global (⌘Z)** avec pile de 50
  opérations et libellés lisibles (« Annuler : paiement de 70 € · Jean Dupont »).
  Les actions réellement destructives (supprimer un patient) demandent confirmation.
- **⌘K** ouvre une palette de commandes : patients, consultations, paiements,
  actions. Recherche sans accents, sans casse, par sous-chaîne et par initiales.
- **Le clavier suffit** : `↑ ↓` naviguer, `P` présent, `A` absent, `⏎` valider le
  paiement suggéré, `⌥1…4` moyens alternatifs, `⎋` annuler, `⌘Z` revenir en arrière.
- **Densité professionnelle** : chiffres tabulaires, hauteur de ligne 44 pt, filets
  d'1 px plutôt que des ombres, aucune carte flottante inutile.

---

## 10. Confidentialité

- Tout est local. L'application n'ouvre **aucune connexion réseau** — il n'y a aucun
  client HTTP dans le code.
- Le fichier de base vit dans le conteneur de l'application, donc dans la sauvegarde
  Time Machine et dans un volume FileVault si l'utilisatrice l'a activé (c'est le
  mécanisme de chiffrement recommandé ici : chiffrer la base avec une clé stockée à
  côté n'apporterait rien de plus).
- Les Réglages proposent un **verrouillage de la fenêtre** (masquage immédiat du
  contenu) pour les moments où un patient est dans le bureau.
- Le champ « notes » est explicitement présenté comme **non destiné aux notes
  cliniques** — Cadence n'est pas un dossier médical et ne prétend pas l'être.
- Aucune revendication de conformité réglementaire n'est faite : le document
  `docs/DONNEES.md` décrit précisément ce qui est stocké et où, pour que
  l'utilisatrice ou son conseil puisse juger.

---

## 11. Vérification

Le cœur (`CadenceCore`) est compilé et testé **réellement**, sur Linux en
développement et sur macOS en intégration continue :

- les 10 scénarios d'acceptation du cahier des charges, exécutés comme tests ;
- le moteur d'habitudes, y compris les cas limites (échantillon faible, exception
  ponctuelle, changement durable d'habitude) ;
- la persistance : fermeture, réouverture, relecture ;
- la cohérence des statistiques avec les données enregistrées ;
- les migrations de schéma.

L'application complète (SwiftUI + EventKit) est **compilée sur un vrai runner
macOS** en intégration continue, qui produit le bundle `.app` téléchargeable.
