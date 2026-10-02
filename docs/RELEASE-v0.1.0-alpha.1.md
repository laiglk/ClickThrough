# ClickThrough 0.1.0, première préversion publique

Petit utilitaire natif macOS qui tente d’activer une fenêtre et d’effectuer l’action visée avec un seul clic gauche.

## Installation

- Télécharger **ClickThrough-0.1.0-arm64.zip** ci-dessous. Il contient l’application prête à ouvrir, pour **Mac Apple Silicon, macOS 13 ou ultérieur**.
- Décompresser, déplacer `ClickThrough.app` dans **Applications**, puis ouvrir l’application.
- Accorder l’autorisation **Accessibilité** depuis le bouton des réglages de ClickThrough.
- Le menu dans la barre de menus permet de mettre en pause et de gérer les exclusions.

Cette préversion est signée localement (ad hoc), mais **n’est pas notarisée par Apple**. macOS peut bloquer le premier lancement. L’option « Ouvrir quand même » peut être proposée dans Réglages Système → Confidentialité et sécurité après une tentative d’ouverture. Le code et les instructions de compilation sont disponibles dans le dépôt.

## Fonctionnalités

- Traitement du premier clic gauche, fenêtre par fenêtre, avec prise en charge des coordonnées de plusieurs écrans.
- Pause, exclusions par application et lancement à la connexion en option.
- Interface française, traitement local, aucun compte ni connexion réseau nécessaire.

## État des tests

Compilation release, signature locale, contrôles d’interface et six tests automatiques de la file d’événements réussis. Ces tests ne valident pas les interactions réelles dans toutes les applications.

Le compteur mesure les clics transmis après activation, sans confirmer que l’application cible a exécuté l’action. Le compteur et les clics sur des tweets dans Firefox restent à revalider après les dernières corrections. La compatibilité universelle n’est pas garantie. Les clics modifiés, fenêtres non standard et certains cas de plein écran conservent le comportement natif.

Signaler les problèmes dans les Issues avec la version de macOS, l’application et les étapes de reproduction. L’empreinte du ZIP est jointe dans `SHA256SUMS.txt`.
