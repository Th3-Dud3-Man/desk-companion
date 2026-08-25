# Ce que Cadence stocke, et où

Ce document décrit précisément le traitement des données, pour que l'utilisatrice —
ou son conseil — puisse en juger. **Aucune conformité réglementaire n'est
revendiquée ici** : ce texte décrit un comportement technique, il ne constitue pas un
avis juridique.

## Où vivent les données

Un seul fichier, sur le Mac :

```
~/Library/Application Support/Cadence/cadence.sqlite3
~/Library/Application Support/Cadence/cadence.sqlite3-wal     (journal d'écriture)
~/Library/Application Support/Cadence/Backups/                (14 instantanés)
```

C'est tout. Il n'y a pas de compte, pas de serveur, pas de fichier de configuration
ailleurs.

## Ce qui sort du Mac

**Rien.**

Cadence n'ouvre aucune connexion réseau. Le code ne contient aucun client HTTP,
aucune URL de service, aucune clé d'API. La seule bibliothèque système à laquelle
elle parle en dehors du fichier local est EventKit, qui lit les calendriers déjà
présents sur la machine.

Les seules données qui quittent l'application sont celles que l'utilisatrice exporte
elle-même, à l'endroit qu'elle choisit dans la fenêtre d'enregistrement.

## Ce qui est stocké

| Donnée | Détail |
|---|---|
| Patients | nom, e-mail et téléphone si saisis, notes libres, tarif éventuel |
| Consultations | date, horaires prévus, horaires réels si mesurés, statut, lieu, notes |
| Paiements | montant, moyen, date et heure, note éventuelle |
| Journal | horodatage de chaque action, pour l'historique et l'annulation |
| Calendriers | identifiant, nom et compte des calendriers suivis, état de synchronisation |
| Réglages | nom du cabinet, tarifs, moyens de paiement, préférences d'affichage |

Ce qui provient du calendrier se limite au titre de l'événement, à ses horaires, à
son lieu et à ses identifiants. Les invités, les descriptions et les pièces jointes
ne sont ni lus ni conservés.

### Notes

Le champ « notes » est destiné à des informations pratiques (« préfère le matin »,
« règle en fin de mois »). **Cadence n'est pas un dossier patient informatisé** et
n'offre aucune des garanties attendues d'un tel outil. Les notes cliniques n'ont pas
leur place ici.

## Chiffrement

Cadence ne chiffre pas la base elle-même, et le document le dit plutôt que de le
laisser croire. Un chiffrement applicatif dont la clé serait stockée à côté du
fichier, sur la même machine, n'apporterait aucune protection réelle contre les
menaces qui comptent ici.

La protection appropriée sur un Mac est **FileVault**, qui chiffre l'intégralité du
disque avec une clé dérivée du mot de passe de session (Réglages Système ›
Confidentialité et sécurité › FileVault). Avec FileVault actif, la base de Cadence
est chiffrée au repos, comme le reste du Mac.

Deux mesures complémentaires sont prévues dans l'application :

- un réglage qui masque le contenu de la fenêtre lorsque Cadence passe en
  arrière-plan, pour les moments où un patient est dans le bureau ;
- l'absence totale de transmission réseau, qui supprime la question du transit.

## Sauvegardes

Au premier lancement de chaque jour, un instantané est écrit dans `Backups/`. Les 14
derniers sont conservés, les plus anciens sont supprimés. Ils vivent dans le même
dossier que la base : ils protègent d'une erreur de manipulation ou d'un fichier
abîmé, **pas** de la perte du Mac. Time Machine ou une sauvegarde équivalente reste
nécessaire pour cela — et couvre ce dossier comme le reste du disque personnel.

Une restauration remplace la base courante et conserve l'état précédent sous
`cadence-avant-restauration.sqlite3`.

## Suppression

- **Un patient** : la suppression efface ses paiements et détache ses rendez-vous.
  L'archivage, proposé en premier, masque le patient sans rien détruire.
- **Les données de démonstration** : supprimées en une action, sans toucher au reste.
- **Tout** : supprimer le dossier `~/Library/Application Support/Cadence/` efface
  l'intégralité des données de l'application.

## Accès au calendrier

L'autorisation est demandée par macOS, jamais contournée, et peut être retirée à tout
moment dans Réglages Système › Confidentialité et sécurité › Calendriers. Cadence
fonctionne sans : les rendez-vous se saisissent alors à la main.

L'accès est utilisé **en lecture seule**. Cadence n'écrit jamais dans un calendrier,
ne crée ni ne modifie ni ne supprime le moindre événement.
