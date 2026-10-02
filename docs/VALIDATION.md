# Validation interactive

Statut initial : **à effectuer après autorisation d’accessibilité**. Ne pas confondre compilation et compatibilité applicative.

## Vérifications réalisées le 1er octobre 2026

- Compilation Swift release sur Apple Silicon avec les Command Line Tools.
- Vérification du bundle et de sa signature locale ad hoc.
- Lancement de l’application, lecture de l’arbre d’accessibilité et inspection visuelle des réglages.
- État initial sans permission : « Autorisation nécessaire ».
- Interrupteur activé/désactivé puis restauré dans l’interface.
- Ajout de ChatGPT par le sélecteur natif, affichage de l’exclusion, puis retrait vérifiés. Aucune exclusion conservée à la livraison.
- Six contrôles automatiques du moteur réussis via `scripts/test.sh` (file et métadonnées, aucun événement envoyé).
- Hit-test corrigé : `CGEvent.location` est utilisé directement, et l’absence temporaire d’un élément AX dans une page web n’annule plus un clic si la fenêtre reste focalisée.
- Essais interactifs du premier clic, démarrage à la connexion et VoiceOver : non réalisés à ce stade.

## Préparation

### Contrôles automatiques avant les essais interactifs

Exécuter `bash scripts/test.sh`. Les tests de la file sont complétés par des tests
du moteur réel avec un résolveur, une horloge et une sortie simulés, sans event tap
ni clic envoyé. Ils couvrent notamment la saturation et les erreurs de copie
pendant l’activation, les changements de focus ou de fenêtre après stabilisation,
le relâchement du bouton après annulation et les réponses tardives après arrêt ou
expiration. Leur réussite ne valide pas le hit-test AX, l’activation réelle ni la
réception des événements par les applications ci-dessous.

### Configuration de l’essai

Ouvrir le bundle compilé et autoriser ClickThrough. Disposer les quatre applications sur deux écrans. Refaire les essais avec le second écran à gauche, puis au-dessus de l’écran principal (origines négatives). Désactiver temporairement les autres utilitaires de souris pour isoler les résultats.

## Scénarios prioritaires

| Application inactive | Action | Résultat attendu | Statut |
|---|---|---|---|
| ChatGPT | Clic dans la saisie | Curseur prêt à écrire | À tester |
| ChatGPT | Clic sur une conversation | Conversation ouverte une seule fois | À tester |
| Firefox | Clic sur un onglet | Onglet sélectionné | À tester |
| Firefox | Clic sur un lien de test sans effet externe | Navigation unique | À tester |
| Finder | Clic sur un fichier | Sélection, sans ouverture | À tester |
| Finder | Double-clic sur un dossier de test | Une seule ouverture | À tester |
| Finder | Clic sur un dossier de la barre latérale | Dossier affiché | À tester |
| Anytype | Clic sur une page | Page ouverte | À tester |
| Anytype | Clic dans un bloc | Point d’insertion positionné | À tester |

Pour chaque application, tester depuis une autre application puis depuis une autre fenêtre de la même application.

## Non-régressions

- Fenêtre déjà active : clics et doubles-clics habituels.
- Fenêtre inactive : clic rapide, appui maintenu, sélection de texte, glisser-déposer d’un fichier de test.
- Application acceptant déjà le premier clic : une action, jamais deux.
- Clics avec modificateurs : comportement normal, sans correction par ClickThrough.
- Pause, exclusion, puis réactivation : état immédiatement effectif.
- Fermer/réouvrir les réglages ; relancer l’app : préférences conservées.
- Révoquer l’accès : état « Autorisation nécessaire », clics normaux.
- Veille et réveil, changement de session : reprise sans bouton bloqué.
- Activer le lancement à la connexion, vérifier après reconnexion, puis le désactiver.
- Vérifier clavier, VoiceOver, mode sombre et clair dans les réglages.

Si un problème apparaît, mettre en pause via le menu et noter : application/version, action, disposition des écrans, état du compteur, message affiché. Exclure l’application concernée en attendant une correction.
