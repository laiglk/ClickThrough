# ClickThrough

Utilitaire natif macOS pour activer une fenêtre et effectuer l’action visée avec un seul clic gauche. Swift, AppKit et SwiftUI, sans dépendances externes. macOS 13 minimum.

**Préversion expérimentale.** Le premier téléchargement est destiné aux Mac **Apple Silicon (M1 et suivants)**. Le code peut être compilé localement pour l’architecture du Mac. L’interface est en français.

## Télécharger et essayer

1. Ouvrir les [versions téléchargeables](https://github.com/laiglk/ClickThrough/releases) et télécharger `ClickThrough-0.1.0-arm64.zip` dans les pièces jointes de la préversion (pas les archives « Source code »).
2. Décompresser l’archive puis déplacer `ClickThrough.app` dans **Applications** avant de l’ouvrir.
3. Dans l’application, ouvrir les réglages d’accessibilité et autoriser **ClickThrough**. Quitter puis relancer la même copie si l’autorisation n’est pas détectée.
4. Cliquer dans une fenêtre inactive. Le menu de ClickThrough permet de mettre le moteur en pause ou d’exclure une application en cas de problème.

Cette préversion possède une signature locale ad hoc et **n’est pas notarisée par Apple**. macOS peut bloquer son premier lancement. Après avoir tenté de l’ouvrir, consulter **Réglages Système → Confidentialité et sécurité → Ouvrir quand même**, si cette option est proposée pour ClickThrough. Il n’est pas nécessaire de désactiver Gatekeeper. Il est aussi possible de compiler le code localement avec les instructions ci-dessous.

Voir les [explications d’Apple sur l’ouverture d’une application provenant d’un développeur inconnu](https://support.apple.com/fr-fr/guide/mac-help/-mh40616/mac).

Le fichier `SHA256SUMS.txt` joint à la version permet de vérifier l’intégrité du ZIP :

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Le compteur et le clic sur les tweets dans Firefox ont fait l’objet de corrections, mais leur bon fonctionnement en conditions réelles n’est pas encore confirmé. Merci d’indiquer la version de macOS, l’application concernée et les étapes de reproduction dans un [rapport de bug](https://github.com/laiglk/ClickThrough/issues/new?template=bug_report.md).

## Démarrer

Pour compiler depuis le code source, installer Xcode ou les Command Line Tools (`xcode-select --install`), avec Swift 5.9 ou ultérieur. Aucune dépendance tierce n’est téléchargée.

```sh
bash scripts/build.sh
open ClickThrough.app
```

Le script place désormais le bundle directement à la racine du projet, dans `ClickThrough.app`, et conserve une copie dans `dist/`. Avant un usage quotidien, déplace **cette même copie** dans `/Applications` ou `~/Applications`, puis ouvre-la depuis ce nouvel emplacement. Garder un emplacement stable : macOS associe l’autorisation d’accessibilité à la copie installée.

Dans les réglages de l’application, ouvrir les réglages d’accessibilité et autoriser **la copie actuellement lancée**, dont le chemin est affiché dans l’app. Si nécessaire, retirer les anciennes entrées ClickThrough puis utiliser le bouton + pour ajouter ce bundle précis. Après l’ajout, cliquer sur « Vérifier l’autorisation maintenant ». Aucun accès au clavier, enregistrement d’écran, compte ou réseau n’est demandé par le code. La permission d’accessibilité est toutefois une permission système étendue.

Si l’interrupteur est bleu mais que ClickThrough affiche encore « Autorisation nécessaire », désactiver puis supprimer l’entrée existante avec « − », ajouter à nouveau le bundle affiché avec « + », l’activer, quitter ClickThrough et relancer exactement cette copie. C’est nécessaire avec une signature locale ad hoc, car macOS peut conserver un ancien enregistrement après une recompilation.

Une icône de curseur apparaît dans la barre de menus : activation/pause, exclusion de l’application au premier plan, réglages, quitter. Fermer les réglages laisse l’utilitaire fonctionner.

## Fonctionnalités

- Interception du premier clic gauche sans touche modificatrice.
- Activation de l’application et de la fenêtre, y compris entre deux fenêtres d’une application.
- Coordonnées globales de `CGEvent.location`, utilisées directement pour le hit-test Accessibilité, sans inversion supplémentaire de l’écran principal.
- Conservation des événements d’origine, de leurs positions, horodatages et compteurs de clics.
- Mise en file des mouvements, relâchements et autres événements souris pendant l’activation.
- Exclusions persistantes par identifiant d’application.
- Lancement à la connexion via `SMAppService`.
- Interface française native, thème système, contrôles accessibles au clavier.
- Arrêt du moteur à la veille/changement de session et reprise ensuite.

## Statut et limites

**Prototype 0.1, pas une garantie de compatibilité universelle.** Les tests automatiques valident la file d’événements et les transactions du moteur avec un résolveur et une horloge simulés ; ils ne remplacent pas les essais interactifs avec l’autorisation d’accessibilité. Voir [la matrice de validation](docs/VALIDATION.md).

Les clics droits, les clics avec ⌘/⌃/⌥/⇧, les clics multiples déjà identifiés comme tels, le bureau, les fenêtres non standard, les boutons de contrôle des fenêtres et les fenêtres avec feuilles modales gardent leur comportement macOS. Les réglages système sont également exclus. Mission Control, les changements de Spaces, plein écran et fenêtres privilégiées ne font pas partie des scénarios garantis. Aucun focus au survol.

Le système cherche la fenêtre via l’API d’accessibilité. Les applications ne publiant pas une fenêtre standard exploitable conservent leur comportement normal. Le premier clic est retenu au maximum 250 ms. Si la recherche de fenêtre expire avant l’activation, il est transmis normalement. Si l’activation a commencé mais ne se confirme pas, ou si la fenêtre sous le point cliqué change, le geste gauche est annulé pour ne pas agir dans une autre fenêtre. Une application lente peut donc encore demander un deuxième clic. Le compteur des réglages mesure les transmissions après activation, pas une confirmation de l’action par l’application destinataire.

La saturation de la file et les erreurs de copie suivent la même règle : transmission normale avant le début de l’activation, annulation du geste gauche après. Les autres événements souris sont conservés. Le focus et la fenêtre visée sont revérifiés après le délai de stabilisation, juste avant la transmission ; cette vérification n’est pas atomique avec les changements de fenêtre du système.

La version locale utilise une signature ad hoc. Une recompilation peut nécessiter de retirer puis réajouter l’application dans les permissions. Pour distribuer l’application, prévoir une signature Developer ID et une notarisation. `SIGN_IDENTITY` permet de fournir une identité au script de compilation. Les identités de signature et la notarisation ne sont pas configurées dans ce dépôt.

## Préparer une archive

```sh
bash scripts/package.sh
```

Le script exécute les tests, compile l’application, puis crée dans `dist/release/` un ZIP avec le bundle `.app` et son empreinte SHA-256. Le nom de l’archive indique la version et l’architecture du binaire. La publication GitHub se fait séparément.

## Architecture

- `ClickThroughEngine` : module du moteur, partagé entre l’application et ses tests ; dépendances système injectables pour les tests.
- `ClickEngine` : event tap de session, file bornée, délai maximal, réinjection marquée pour éviter la récursion.
- `WindowResolver` : identification et activation des fenêtres par AX, sur une file dédiée. Aucun appel AX synchrone dans le callback du tap.
- `EventBuffer` : transactions identifiées pour ignorer les résultats AX arrivés après expiration.
- `AppModel` : permissions, préférences, exclusions et démarrage automatique.
- `SettingsView` et `AppDelegate` : fenêtre de réglages et menu macOS.

Le clic initial est supprimé du flux pendant l’activation, puis réinjecté une seule fois. Il n’y a pas de clic supplémentaire ajouté à un clic déjà transmis et pas d’injection de code dans les autres applications.

## Tests

```sh
bash scripts/test.sh
```

Le lanceur de tests fonctionne avec les seuls Command Line Tools, sans XCTest. Il exécute les contrôles de `ClickThroughCore` puis ceux de `ClickThroughEngine`. Ces derniers parcourent le moteur réel avec un résolveur, un ordonnanceur et une sortie simulés : ordre et unicité, saturation et erreurs de copie pendant l’activation, changements de focus ou de fenêtre pendant la stabilisation, relâchement après annulation, arrêt et résultats tardifs. Les métadonnées de vrais `CGEvent` sont également vérifiées. Aucun event tap n’est installé, aucune application n’est activée et aucun événement n’est envoyé.

Le package s’ouvre aussi avec Xcode via `Package.swift`. Pour les permissions et `SMAppService`, utiliser le bundle `.app` généré plutôt que `swift run`.

## Licence

[MIT](LICENSE), réutilisation autorisée en conservant la notice de copyright et la licence.
