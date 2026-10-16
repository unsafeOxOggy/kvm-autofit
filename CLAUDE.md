# kvm-autofit - contexte projet (handoff pour Claude Code)

> Relu au démarrage d'une session Claude Code dans ce dépôt. Mettre à jour quand l'état change.

## But

Corriger le cadrage d'affichage des VM Linux KVM (guest X11) : au boot, au greeter, au login et
en plein écran, l'écran doit suivre la fenêtre de l'hôte sans devoir se déco/reconnecter.
Projet **générique** (toutes mes VM Linux KVM), né du problème sur la VM Kali `kali-i3`
(cf. `~/DEV/kali/okoko`). Bash pur, pas de démon, pas de dépendance hors `xrandr`.

## Architecture

- `src/kvm-autofit` - script unique. Modes : `$DISPLAY` (user), `--all` (root : découvre chaque
  `Xorg` via `/proc/<pid>/cmdline`, prend son `-auth`, sinon le `XAUTHORITY` d'un client),
  `--settle` (re-vérifie jusqu'à 3 passes stables, max 16x0.25 s), `--display-setup` (hook
  LightDM : 1 passe + settle en arrière-plan via `setsid -f`), `doctor`.
  Lock `/run/kvm-autofit.lock` (flock) en mode `--all`. Logs : `logger -t kvm-autofit`.
- `dist/udev/90-kvm-autofit.rules` - `ACTION=="change", SUBSYSTEM=="drm"` -> `systemctl --no-block start`.
  `@SYSTEMCTL@` remplacé à l'install.
- `dist/systemd/kvm-autofit.service` - oneshot `--all --settle`, durci (ProtectSystem=strict,
  caps DAC_READ_SEARCH + SYS_PTRACE pour lire cookies/environ).
- `dist/lightdm/50-kvm-autofit.conf` - display-setup + session-setup.
- `install.sh` - `--dry-run --uninstall --no-lightdm` ; refuse d'écraser un setup-script LightDM existant.

## VM de test

- `ssh kali@192.168.100.18` (clé installée). Kali, virtio-gpu, SPICE + GL (`listen none`), LightDM + i3.
- Hôte Fedora 44 : `virsh -c qemu:///system` (domaines : `kali-i3`, `cowrie`, `ELK`).
- Déployer : `rsync -az --exclude=.git ./ kali@192.168.100.18:~/kvm-autofit/`.
- Test sans sudo : `DISPLAY=:0 XAUTHORITY=~/.Xauthority` ; casser avec
  `xrandr --output Virtual-1 --mode 1920x1440` puis `./src/kvm-autofit --settle -v` -> revient au mode préféré.
- **sudo** : je ne saisis pas le mot de passe à la place de l'utilisateur -> c'est lui qui lance
  `sudo ./install.sh` dans la VM.

## État (MAJ 2026-10-16)

- [x] v0.1.0 écrite ; testée sur la VM en utilisateur : cassé 1920x1440 -> recadré 1920x1025 en 1.1 s,
  passe à vide = no-op, découverte X (`:0` + cookie) OK, `doctor` OK.
- [ ] `sudo ./install.sh` sur la VM (action utilisateur) puis valider : greeter au boot, login i3,
  plein écran on/off, `journalctl -t kvm-autofit -b`.
- [x] GitHub : `git@github.com:unsafeOxOggy/kvm-autofit.git` (public, branche master). Push avec la clé `~/.ssh/ssh2`
  (réglée dans `core.sshCommand`) ; auteur = adresse noreply GitHub (ne jamais committer l'e-mail perso).

## TODO

1. Valider le chemin root réel (udev -> service -> `--all`) après install, notamment que le
   durcissement systemd n'empêche pas l'accès à `/tmp/.X11-unix` et aux cookies.
2. Hook optionnel post-resize côté session (`~/.config/kvm-autofit/on-resize`) pour wallpaper/polybar
   (okoko : `okoko-wall restore`, `okoko-bar`) - exécuter en tant qu'utilisateur, jamais en root.
3. Greeters GDM/SDDM (X11) : intégrer `--display-setup` dans `Xsetup`.
4. Tests bats (parseur `outputs_state` sur des sorties xrandr figées).
5. Éventuellement : intégrer dans `okoko/install.sh` quand `detect_virt` = kvm.

## Conventions

- Bash strict (`set -uo pipefail`), `bash -n` + shellcheck (CI). Aucun `eval`, toutes les valeurs
  issues de `/proc` sont validées (`^:[0-9]+$`, chemins absolus lisibles) avant usage.
- Redirections : mettre `2>/dev/null` **avant** `<fichier` pour masquer l'échec d'ouverture.
- Rappels prefs utilisateur : voir `~/.claude/CLAUDE.md` (prévenir pour les actions manuelles,
  checklist finale). Les règles stack web Rust/Supabase ne s'appliquent pas ici.
