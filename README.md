# kvm-autofit

Cadrage automatique de l'affichage des **VM Linux sous KVM/QEMU** (virt-manager, virt-viewer,
remote-viewer) : l'écran du guest suit la fenêtre de l'hôte **dès le démarrage, à l'écran de
connexion, à l'ouverture de session et à chaque passage en plein écran** - quel que soit le
gestionnaire de fenêtres (i3, XFCE, ...).

## Le problème

Avec un GPU `virtio` (ou `qxl`), l'hôte transmet la taille de sa fenêtre au guest sous forme de
**mode préféré** du connecteur (`Virtual-1`) et le noyau émet un événement DRM `change`.
**X ne applique jamais ce mode tout seul** : il faut que quelqu'un lance `xrandr --auto`.

D'habitude ce "quelqu'un" est `spice-vdagent`, mais :

- il ne tourne **que dans une session** -> l'écran de connexion (LightDM) reste mal cadré ;
- il démarre **après** X et rate souvent le premier événement -> mauvais cadrage jusqu'à ce qu'on
  se déconnecte/reconnecte ;
- sous i3 (pas d'autostart XDG) il peut ne pas être lancé, ou l'être en double.

## La solution

```
hôte redimensionne -> noyau virtio-gpu -> uevent DRM "change"
                                              |
                    udev 90-kvm-autofit.rules +
                                              v
                     kvm-autofit.service (oneshot, root)
                                              v
       trouve chaque Xorg + son cookie -auth -> xrandr --output ... --auto
                                                 (re-vérifie ~4 s : "settle")

LightDM display-setup / session-setup -> même ajustement au greeter et au login
```

Indépendant de la session et du WM ; `spice-vdagent` reste utile pour le **presse-papier**.
Sous **Wayland** (GNOME/KDE), le compositeur gère déjà le redimensionnement : rien à faire.

## Installation (dans la VM)

```bash
git clone <ce dépôt> ~/kvm-autofit   # ou rsync depuis l'hôte
cd ~/kvm-autofit
sudo ./install.sh            # --dry-run pour voir, --no-lightdm, --uninstall
kvm-autofit doctor           # depuis un terminal de la VM
```

Installe : `/usr/local/libexec/kvm-autofit` (+ lien `/usr/local/bin`), la règle udev, l'unité
systemd et, si LightDM est présent, `/etc/lightdm/lightdm.conf.d/50-kvm-autofit.conf`
(refusé proprement si un autre `display-setup-script` existe déjà). Dépendance : `xrandr`
(installé via apt/dnf/pacman/zypper si absent).

## Côté hôte (à vérifier une fois par VM)

- virt-manager -> **Matériel -> Vidéo -> Modèle : Virtio** (QXL fonctionne aussi).
- **Canal SPICE** `com.redhat.spice.0` présent (presse-papier + vdagent).
- Fenêtre de la VM -> **Affichage -> Mise à l'échelle -> "Redimensionner automatiquement la VM avec
  la fenêtre"** activé.

## Utilisation

| Commande | Rôle |
|---|---|
| `kvm-autofit` | ajuste `$DISPLAY` (utilisateur) |
| `kvm-autofit --settle` | idem, en re-vérifiant ~4 s |
| `sudo kvm-autofit --all` | ajuste tous les serveurs X (ce que fait le service) |
| `kvm-autofit doctor` | diagnostic complet |
| `journalctl -t kvm-autofit -b` | journal des ajustements |

Réglages : `KVM_AUTOFIT_DELAY` (0.25 s) et `KVM_AUTOFIT_ROUNDS` (16) pour le mode settle.

## Limites connues

- X11 uniquement (Wayland n'en a pas besoin).
- Plusieurs écrans : placés de gauche à droite dans l'ordre de `xrandr`.
- GDM/SDDM : la règle udev couvre les redimensionnements ; pour le greeter, appeler
  `kvm-autofit --display-setup` depuis le script `Xsetup` (SDDM) - non automatisé.
- Les fonds d'écran/barres qui ne suivent pas RandR (ex. polybar) peuvent nécessiter un hook
  (voir TODO dans `CLAUDE.md`).
