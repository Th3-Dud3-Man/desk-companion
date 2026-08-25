# Cadence — Système de design

Un cabinet n'est pas un tableau de bord financier. L'identité visuelle vise le
**calme dense** : papier chaud, encre profonde, un seul accent végétal, des filets
plutôt que des ombres, et des chiffres alignés au pixel.

Aucune valeur n'est choisie au hasard : tout provient des échelles ci-dessous.

---

## 1. Couleur

Deux thèmes complets. Les neutres sont **chauds** (teintés vers le jaune/vert) et non
gris-bleus — c'est ce qui donne la sensation « papier » plutôt que « logiciel
administratif ».

### Clair

| Jeton | Hex | Usage |
|---|---|---|
| `canvas` | `#F6F5F1` | fond de la zone de travail (porte la trame de points) |
| `surface` | `#FFFFFF` | cartes, lignes, panneaux |
| `surfaceSunken` | `#EFEEE9` | champs, zones creuses, en-têtes de tableau |
| `surfaceHover` | `#F2F1EC` | survol d'une ligne |
| `hairline` | `#E3E1D9` | séparateurs, bordures de cartes |
| `hairlineStrong` | `#CFCCC2` | bordure de champ au repos |
| `textPrimary` | `#1B1C19` | titres, noms, montants |
| `textSecondary` | `#61625C` | métadonnées, libellés |
| `textTertiary` | `#93948C` | texte désactivé, indices |
| `accent` | `#2E6B57` | actions principales, présence, encaissé |
| `accentHover` | `#265B4A` | survol accent |
| `accentSoft` | `#E3EDE8` | fond de badge accent |
| `warning` | `#8F6414` | en attente, à confirmer |
| `warningSoft` | `#F6EDD9` | fond de badge attente |
| `danger` | `#A34129` | absence, suppression |
| `dangerSoft` | `#F7E4DE` | fond de badge absence |
| `neutralSoft` | `#ECEAE3` | fond de badge neutre (annulé, planifié) |
| `focusRing` | `#2E6B57` @ 45 % | anneau de focus clavier |

### Sombre

| Jeton | Hex |
|---|---|
| `canvas` | `#141513` |
| `surface` | `#1C1E1B` |
| `surfaceSunken` | `#101210` |
| `surfaceHover` | `#232522` |
| `hairline` | `#2D2F2B` |
| `hairlineStrong` | `#3D403A` |
| `textPrimary` | `#EFEEE7` |
| `textSecondary` | `#A1A299` |
| `textTertiary` | `#6D6E66` |
| `accent` | `#63B899` |
| `accentHover` | `#77C7AA` |
| `accentSoft` | `#1D3229` |
| `warning` | `#D5A257` |
| `warningSoft` | `#33291A` |
| `danger` | `#E08268` |
| `dangerSoft` | `#35201C` |
| `neutralSoft` | `#262824` |

**Règle d'accessibilité** : un état n'est jamais signalé par la seule couleur. Présent,
absent et en attente portent chacun **une icône, un libellé et une couleur** — un
utilisateur daltonien lit l'état sans la teinte (§ 34).

---

## 2. Typographie

Police système (SF Pro), aucune police embarquée.

| Rôle | Taille | Graisse | Notes |
|---|---|---|---|
| `display` | 26 | semibold | titre d'écran, une seule occurrence par vue |
| `title` | 19 | semibold | titres de panneaux |
| `heading` | 15 | semibold | titres de section, nom du patient dans une ligne |
| `body` | 13 | regular | texte courant |
| `bodyStrong` | 13 | medium | valeur mise en avant |
| `caption` | 11,5 | regular | métadonnées |
| `label` | 10,5 | semibold | étiquettes de section, majuscules, interlettrage +0,06 em |
| `mono*` | idem | idem | variantes à **chiffres tabulaires** |

**Tout ce qui est chiffre — heure, montant, compteur — utilise les chiffres
tabulaires.** C'est ce qui fait qu'une colonne d'horaires ou de montants reste
alignée et lisible d'un coup d'œil, et c'est la différence la plus visible entre une
interface professionnelle et une interface générique.

---

## 3. Espacement

Base 4, avec deux demi-pas (2 et 6) pour les ajustements optiques fins.

```
xxs 2 · xs 4 · sm 6 · md 8 · lg 12 · xl 16 · xxl 20 · xxxl 24 · huge 32 · giant 40
```

Marges appliquées : intérieur de carte `lg`, gouttière entre cartes `lg`, marge de
contenu d'écran `xxl`, séparation entre sections `huge`.

## 4. Rayons

```
chip 5 · control 7 · card 10 · panel 14 · sheet 18 · pill = hauteur / 2
```

## 5. Profondeur

Le système privilégie les **filets d'1 px** ; l'ombre est réservée à ce qui flotte
réellement au-dessus du contenu.

| Niveau | Usage | Rendu |
|---|---|---|
| 0 | contenu en ligne | rien |
| 1 | carte, ligne | filet `hairline` |
| 2 | élément survolé / sélectionné | filet + ombre `y 2, flou 6, 6 %` |
| 3 | popover, palette ⌘K, feuille | filet + ombre `y 10, flou 30, 16 %` |

## 6. Trame de fond

Le canevas porte une trame de points : pas de 22 pt, rayon 0,8 pt, opacité 3,5 %
(clair) / 5 % (sombre). Elle donne la texture « plan de travail » sans jamais
concurrencer le contenu ; les surfaces posées dessus sont opaques.

## 7. Mouvement

| Jeton | Durée | Courbe | Usage |
|---|---|---|---|
| `instant` | 90 ms | `easeOut` | survol, changement de teinte |
| `quick` | 140 ms | `easeOut` | apparition d'un badge, bascule d'état |
| `standard` | 200 ms | `easeOut` | dépliage de la bande de paiement |
| `entrance` | ressort `0,32 / 0,86` | | palette ⌘K, feuilles |

Aucune animation décorative. **Toutes les durées sont ramenées à 0 lorsque
« Réduire les animations » est activé** dans les réglages d'accessibilité macOS.

## 8. Composants et états

Chaque composant définit explicitement : `repos`, `survol`, `pressé`, `focus
clavier`, `sélectionné`, `désactivé`, `chargement`, `erreur`.

- **Boutons** — `primary` (accent plein), `secondary` (surface + filet),
  `ghost` (transparent, survol teinté), `destructive` (danger). Hauteurs 22 / 28 / 34.
- **Bouton de paiement suggéré** — variante `suggestion` : plus haut (34), montant en
  `heading` mono, moyen de paiement en `caption`, badge « Paiement habituel » attaché,
  indice `⏎` à droite.
- **Champs** — hauteur 28, fond `surfaceSunken`, filet `hairlineStrong`, filet
  `accent` 1,5 px au focus. Message d'erreur en `caption` sous le champ, jamais en
  alerte modale.
- **Chips d'état** — hauteur 18, rayon `chip`, icône 9 pt + libellé `label`.
- **Lignes de consultation** — hauteur 44 au repos, extensible ; survol
  `surfaceHover` ; sélection : filet accent 2 px à gauche + fond `accentSoft`.
- **Toast d'annulation** — bas-centre, `sheet`, niveau 3, disparaît en 6 s, contient
  le libellé de l'action et le raccourci `⌘Z`.
- **États vides** — un pictogramme dessiné (pas d'emoji), une phrase, une action.
  Jamais un écran blanc.

## 9. Iconographie

SF Symbols exclusivement, en graisse `medium`, taille alignée sur la ligne de base du
texte adjacent. Vocabulaire fixe et constant dans toute l'application :

`checkmark.circle.fill` présent · `xmark.circle.fill` absent ·
`clock` en attente · `play.circle` démarrer · `stop.circle` terminer ·
`creditcard` carte · `banknote` espèces · `doc.text` chèque ·
`arrow.left.arrow.right` virement · `ellipsis.circle` autre.

## 10. Densité

Cible : **une journée de 8 rendez-vous visible sans défilement** sur une fenêtre de
1 100 × 720, tout en gardant 44 pt par ligne et des marges respirables. C'est le
compromis mesuré entre « tableur des années 2000 » et « application vide où tout est
à deux clics ».
