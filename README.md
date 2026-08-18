# my-desnap

Small Bash utility to remove Snap from Ubuntu and official Ubuntu flavours while replacing the Ubuntu Firefox Snap wrapper with the official Mozilla APT package.

## What it does

- Detects the current Ubuntu flavour / desktop environment when possible.
- Shows the installed Snap packages and asks for one initial confirmation.
- Adds Mozilla's official APT repository and verifies its signing-key fingerprint.
- Installs the Mozilla Firefox `.deb` before touching Snap.
- Migrates and backs up the Firefox Snap profile when present.
- Removes installed Snaps, `snapd`, and known Snap store backends for GNOME Software and KDE Discover.
- Simulates the APT purge first and stops if critical desktop, audio, network, printing, or display-manager packages would be removed.
- Blocks future APT installation of `snapd` and the known Snap store backends.
- Does **not** run `apt autoremove` automatically.

## Usage

Clone the repository and run the script as your normal user:

```bash
git clone https://github.com/LukeLeFox/my-desnap.git
cd my-desnap
chmod +x desnap.sh
./desnap.sh
```

Do **not** launch the script with `sudo`; it requests elevated privileges itself when required.

## Important warning

This script removes **all installed Snap applications and their Snap data**. Applications other than Firefox are not automatically replaced.

Before confirming, review the list of installed Snaps shown by the script and make sure you have backups of anything important.

The script intentionally leaves libraries such as `libsnapd-glib` alone when they are required by desktop components.

## Firefox

Firefox is installed from Mozilla's official APT repository. The script verifies the Mozilla repository key fingerprint before installing it and checks that the selected Firefox version actually comes from `packages.mozilla.org`.

If an existing Ubuntu Firefox transitional package has a numerically higher version, `--allow-downgrades` is used **only for the Firefox installation step** so that APT can replace it with Mozilla's real `.deb` package.

## Compatibility

Designed for Ubuntu and official Ubuntu flavours such as Ubuntu Desktop, Kubuntu, Xubuntu, Lubuntu, Ubuntu MATE, Ubuntu Budgie, Ubuntu Unity, Ubuntu Studio, Edubuntu and Ubuntu Kylin.

The current version has been validated on Ubuntu/Kubuntu 26.04. Handling for earlier Ubuntu releases is included, but those releases may need additional testing.

## Safety choices

The script deliberately does not run `apt autoremove`. After it finishes, review any packages APT reports as no longer required before removing them manually.

Use at your own risk and review the script before running it on an important system.
