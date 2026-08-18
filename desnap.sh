#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_FPR="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"

MOZILLA_KEY="/etc/apt/keyrings/packages.mozilla.org.asc"
MOZILLA_LIST="/etc/apt/sources.list.d/mozilla.list"
MOZILLA_SOURCES="/etc/apt/sources.list.d/mozilla.sources"
MOZILLA_PREF="/etc/apt/preferences.d/mozilla"
NOSNAP_PREF="/etc/apt/preferences.d/nosnap.pref"

HOST_NAME="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo 'Sistema')"
TMP_KEY=""

cleanup() {
    [[ -n "${TMP_KEY:-}" ]] && rm -f "$TMP_KEY" 2>/dev/null || true
}

on_error() {
    local rc=$?
    cleanup
    printf '\n[ERRORE] Operazione interrotta alla riga %s (exit code %s).\n' "$1" "$rc" >&2
    exit "$rc"
}

trap 'on_error "$LINENO"' ERR
trap cleanup EXIT

is_installed() {
    local status
    status="$(LC_ALL=C dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null || true)"
    [[ "$status" == ii* ]]
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

detect_desktop() {
    local raw="${XDG_CURRENT_DESKTOP:-}:${XDG_SESSION_DESKTOP:-}:${DESKTOP_SESSION:-}"
    raw="${raw,,}"

    case "$raw" in
        *kde*|*plasma*) echo "KDE Plasma"; return ;;
        *xubuntu*|*xfce*) echo "Xfce"; return ;;
        *lubuntu*|*lxqt*) echo "LXQt"; return ;;
        *mate*) echo "MATE"; return ;;
        *budgie*) echo "Budgie"; return ;;
        *unity*) echo "Unity"; return ;;
        *cinnamon*) echo "Cinnamon"; return ;;
        *gnome*|*ubuntu*) echo "GNOME"; return ;;
    esac

    if is_installed kubuntu-desktop; then echo "KDE Plasma"; return; fi
    if is_installed xubuntu-desktop; then echo "Xfce"; return; fi
    if is_installed lubuntu-desktop; then echo "LXQt"; return; fi
    if is_installed ubuntu-mate-desktop; then echo "MATE"; return; fi
    if is_installed ubuntu-budgie-desktop; then echo "Budgie"; return; fi
    if is_installed ubuntu-unity-desktop; then echo "Unity"; return; fi
    if is_installed ubuntustudio-desktop; then echo "KDE Plasma (Ubuntu Studio)"; return; fi
    if is_installed edubuntu-desktop; then echo "GNOME (Edubuntu)"; return; fi
    if is_installed ubuntu-desktop; then echo "GNOME"; return; fi

    echo "Non rilevato"
}

detect_flavour() {
    local flavours=()
    local result=""
    local f

    is_installed ubuntu-desktop        && flavours+=("Ubuntu Desktop")
    is_installed kubuntu-desktop       && flavours+=("Kubuntu")
    is_installed xubuntu-desktop       && flavours+=("Xubuntu")
    is_installed lubuntu-desktop       && flavours+=("Lubuntu")
    is_installed ubuntu-mate-desktop   && flavours+=("Ubuntu MATE")
    is_installed ubuntu-budgie-desktop && flavours+=("Ubuntu Budgie")
    is_installed ubuntu-unity-desktop  && flavours+=("Ubuntu Unity")
    is_installed ubuntustudio-desktop  && flavours+=("Ubuntu Studio")
    is_installed edubuntu-desktop      && flavours+=("Edubuntu")
    is_installed ubuntukylin-desktop   && flavours+=("Ubuntu Kylin")

    if ((${#flavours[@]} == 0)); then
        echo "Ubuntu / flavour non identificato"
        return
    fi

    for f in "${flavours[@]}"; do
        [[ -n "$result" ]] && result+=" + "
        result+="$f"
    done

    echo "$result"
}

apt_install() {
    sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y "$@"
}

firefox_policy() {
    LC_ALL=C apt-cache policy firefox
}

get_firefox_candidate() {
    local policy
    policy="$(firefox_policy)"
    awk '$1=="Candidate:" {print $2; exit}' <<< "$policy"
}

get_firefox_installed() {
    local policy
    policy="$(firefox_policy)"
    awk '$1=="Installed:" {print $2; exit}' <<< "$policy"
}

mozilla_has_version() {
    local wanted="$1"
    local madison pkg version repo

    madison="$(LC_ALL=C apt-cache madison firefox 2>/dev/null || true)"

    while IFS='|' read -r pkg version repo; do
        version="$(trim "${version:-}")"
        repo="$(trim "${repo:-}")"

        if [[ "$version" == "$wanted" && "$repo" == *"packages.mozilla.org/apt"* ]]; then
            return 0
        fi
    done <<< "$madison"

    return 1
}

# ============================================================
# CONTROLLI INIZIALI
# ============================================================

if [[ $EUID -eq 0 ]]; then
    echo "Esegui lo script come utente normale, NON con sudo."
    echo "Lo script userà sudo automaticamente dove necessario."
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "/etc/os-release non trovato."
    exit 1
fi

source /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "Questo script supporta Ubuntu e i flavour ufficiali."
    echo "Sistema rilevato: ${PRETTY_NAME:-${ID:-sconosciuto}}"
    exit 1
fi

DETECTED_DE="$(detect_desktop)"
DETECTED_FLAVOUR="$(detect_flavour)"
VERSION_ID_NOW="${VERSION_ID:-0}"
CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-sconosciuto}}"

mapfile -t CURRENT_SNAPS < <(
    if command -v snap >/dev/null 2>&1; then
        LC_ALL=C snap list 2>/dev/null | awk 'NR>1 {print $1}' | sort -u || true
    fi
)

clear 2>/dev/null || true

cat <<INFO

╔══════════════════════════════════════════════════════════════╗
║           💣 DE-SNAP UNIVERSALE UBUNTU v4.2 💣             ║
╚══════════════════════════════════════════════════════════════╝

Host       : $HOST_NAME
Sistema    : ${PRETTY_NAME:-Ubuntu}
Flavour    : $DETECTED_FLAVOUR
Desktop    : $DETECTED_DE
Release    : $VERSION_ID_NOW ($CODENAME)

Dopo questa UNICA conferma:

  → configura il repository APT ufficiale Mozilla
  → verifica fingerprint e provenienza del Firefox DEB
  → installa/verifica Firefox DEB prima di toccare Snap
  → salva l'eventuale profilo Firefox Snap
  → rimuove tutti gli Snap
  → purga snapd e i backend Snap degli store conosciuti
  → blocca la reinstallazione futura via APT
  → pulisce i residui Snap

NON esegue apt autoremove.
NON tenta di rimuovere libsnapd-glib / libsnapd-qt.
Il purge viene simulato e bloccato se coinvolge componenti critici.

INFO

if ((${#CURRENT_SNAPS[@]} > 0)); then
    echo "Snap attualmente installati:"
    printf '  - %s\n' "${CURRENT_SNAPS[@]}"
else
    echo "Snap attualmente installati: nessuno rilevato"
fi

echo
read -r -p "💥 DETONARE SNAP SU ${HOST_NAME}? [s/N] " ANSWER

case "$ANSWER" in
    s|S|si|SI|sì|SÌ|y|Y|yes|YES) ;;
    *)
        echo "Operazione annullata."
        exit 0
        ;;
esac

sudo -v

# ============================================================
# 1/9 - PREPARAZIONE
# ============================================================

echo
echo "============================================================"
echo "[1/9] Preparazione APT"
echo "============================================================"

sudo apt-get update
apt_install ca-certificates wget gnupg

# ============================================================
# 2/9 - MOZILLA
# ============================================================

echo
echo "============================================================"
echo "[2/9] Repository Mozilla"
echo "============================================================"

sudo install -d -m 0755 /etc/apt/keyrings
TMP_KEY="$(mktemp)"

wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O "$TMP_KEY"

GPG_INFO="$(LC_ALL=C gpg --show-keys --with-colons "$TMP_KEY" 2>/dev/null)"
FPR="$(awk -F: '$1=="fpr" {print $10; exit}' <<< "$GPG_INFO")"

if [[ "$FPR" != "$EXPECTED_FPR" ]]; then
    echo
    echo "❌ Fingerprint Mozilla NON valida."
    echo "Ricevuta: ${FPR:-<vuota>}"
    echo "Attesa  : $EXPECTED_FPR"
    exit 1
fi

echo "✅ Fingerprint Mozilla verificata:"
echo "   $FPR"

sudo install -m 0644 "$TMP_KEY" "$MOZILLA_KEY"
rm -f "$TMP_KEY"
TMP_KEY=""

sudo rm -f "$MOZILLA_LIST" "$MOZILLA_SOURCES"

if dpkg --compare-versions "$VERSION_ID_NOW" ge "26.04"; then
    sudo tee "$MOZILLA_SOURCES" >/dev/null <<EOF2
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: $MOZILLA_KEY
EOF2
else
    echo "deb [signed-by=$MOZILLA_KEY] https://packages.mozilla.org/apt mozilla main" | \
        sudo tee "$MOZILLA_LIST" >/dev/null
fi

sudo tee "$MOZILLA_PREF" >/dev/null <<'EOF2'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000

Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
EOF2

sudo apt-get update

FIREFOX_CANDIDATE="$(get_firefox_candidate)"

if [[ -z "$FIREFOX_CANDIDATE" || "$FIREFOX_CANDIDATE" == "(none)" ]]; then
    echo
    echo "❌ Nessun candidato APT valido per Firefox."
    echo
    firefox_policy
    echo
    echo "Snap NON verrà toccato."
    exit 1
fi

if ! mozilla_has_version "$FIREFOX_CANDIDATE"; then
    echo
    echo "❌ Il candidato Firefox non risulta provenire da Mozilla."
    echo
    echo "Candidate:"
    echo "   $FIREFOX_CANDIDATE"
    echo
    echo "Policy:"
    firefox_policy
    echo
    echo "Madison:"
    LC_ALL=C apt-cache madison firefox || true
    echo
    echo "Snap NON verrà toccato."
    exit 1
fi

echo "✅ Candidate Firefox: $FIREFOX_CANDIDATE"
echo "✅ Candidate presente nel repository Mozilla."

# ============================================================
# 3/9 - FIREFOX
# ============================================================

echo
echo "============================================================"
echo "[3/9] Firefox DEB ufficiale Mozilla"
echo "============================================================"

FIREFOX_PKGS=(firefox)
RAW_LOCALE="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
LOCALE_CODE="${RAW_LOCALE%%.*}"
LOCALE_CODE="${LOCALE_CODE%%@*}"
LOCALE_CODE="${LOCALE_CODE//_/-}"
LOCALE_CODE="${LOCALE_CODE,,}"
LANG_BASE="${LOCALE_CODE%%-*}"

for LANG_PKG in "firefox-l10n-$LOCALE_CODE" "firefox-l10n-$LANG_BASE"; do
    [[ "$LANG_PKG" == "firefox-l10n-" ]] && continue

    if LC_ALL=C apt-cache show "$LANG_PKG" >/dev/null 2>&1; then
        FIREFOX_PKGS+=("$LANG_PKG")
        break
    fi
done

sudo env \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_MODE=a \
    apt-get install -y --allow-downgrades "${FIREFOX_PKGS[@]}"

INSTALLED_VERSION="$(get_firefox_installed)"
CANDIDATE_VERSION="$(get_firefox_candidate)"

if [[ -z "$INSTALLED_VERSION" || "$INSTALLED_VERSION" == "(none)" ]]; then
    echo
    echo "❌ Firefox non risulta installato."
    echo "Snap NON verrà toccato."
    exit 1
fi

if [[ "$INSTALLED_VERSION" != "$CANDIDATE_VERSION" ]]; then
    echo
    echo "❌ Installed e Candidate Firefox non coincidono."
    echo "Installed : $INSTALLED_VERSION"
    echo "Candidate : $CANDIDATE_VERSION"
    echo "Snap NON verrà toccato."
    exit 1
fi

if ! mozilla_has_version "$INSTALLED_VERSION"; then
    echo
    echo "❌ La versione Firefox installata non risulta provenire da Mozilla."
    echo "Snap NON verrà toccato."
    exit 1
fi

echo "✅ Firefox DEB Mozilla installato:"
echo "   $INSTALLED_VERSION"

if ((${#FIREFOX_PKGS[@]} > 1)); then
    echo "✅ Language pack: ${FIREFOX_PKGS[1]}"
fi

# ============================================================
# 4/9 - PROFILO FIREFOX
# ============================================================

echo
echo "============================================================"
echo "[4/9] Backup/migrazione profilo Firefox Snap"
echo "============================================================"

SNAP_FF_PROFILE="$HOME/snap/firefox/common/.mozilla/firefox"

if pgrep -x firefox >/dev/null 2>&1; then
    echo "ℹ️ Firefox è aperto: chiusura prima della migrazione..."
    pkill -TERM -x firefox || true
    sleep 2
fi

if [[ -d "$SNAP_FF_PROFILE" ]]; then
    BACKUP_DIR="$HOME/firefox-snap-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR/firefox"
    cp -a "$SNAP_FF_PROFILE"/. "$BACKUP_DIR/firefox/"

    echo "✅ Backup:"
    echo "   $BACKUP_DIR/firefox"

    mkdir -p "$HOME/.mozilla/firefox"
    cp -an "$SNAP_FF_PROFILE"/. "$HOME/.mozilla/firefox/"

    echo "✅ Profilo copiato in ~/.mozilla/firefox"
    echo "   senza sovrascrivere file esistenti."
else
    echo "ℹ️ Nessun profilo Firefox Snap trovato."
fi

# ============================================================
# 5/9 - SNAP
# ============================================================

echo
echo "============================================================"
echo "[5/9] 💣 Rimozione di tutti gli Snap"
echo "============================================================"

if command -v snap >/dev/null 2>&1 && LC_ALL=C snap list >/dev/null 2>&1; then
    for PASS in {1..10}; do
        mapfile -t SNAPS < <(
            LC_ALL=C snap list 2>/dev/null | awk 'NR>1 {print $1}' | sort -u || true
        )

        ((${#SNAPS[@]} == 0)) && break
        REMOVED=0

        for S in "${SNAPS[@]}"; do
            echo "Rimozione: $S"
            if sudo snap remove --purge "$S"; then
                REMOVED=1
            fi
        done

        ((REMOVED == 0)) && break
    done

    mapfile -t LEFT < <(
        LC_ALL=C snap list 2>/dev/null | awk 'NR>1 {print $1}' | sort -u || true
    )

    if ((${#LEFT[@]} > 0)); then
        echo
        echo "❌ Alcuni Snap non sono stati rimossi:"
        printf '   %s\n' "${LEFT[@]}"
        echo
        echo "snapd NON verrà purgato."
        exit 1
    fi
else
    echo "ℹ️ snap non disponibile oppure snapd già assente."
fi

# ============================================================
# 6/9 - SNAPD / STORE BACKENDS
# ============================================================

echo
echo "============================================================"
echo "[6/9] Rilevamento integrazioni Snap"
echo "============================================================"

PURGE_PKGS=()

for P in snapd plasma-discover-backend-snap gnome-software-plugin-snap; do
    if is_installed "$P"; then
        PURGE_PKGS+=("$P")
        echo "  → trovato: $P"
    fi
done

if ((${#PURGE_PKGS[@]} > 0)); then
    sudo systemctl disable --now \
        snapd.socket \
        snapd.service \
        snapd.seeded.service \
        >/dev/null 2>&1 || true

    # ========================================================
    # 7/9 - SICUREZZA
    # ========================================================

    echo
    echo "============================================================"
    echo "[7/9] Simulazione di sicurezza + purge"
    echo "============================================================"

    SIM="$(LC_ALL=C apt-get -s purge "${PURGE_PKGS[@]}" 2>&1 || true)"

    CRITICAL_RE='^Remv (ubuntu-desktop|ubuntu-desktop-minimal|kubuntu-desktop|xubuntu-desktop|lubuntu-desktop|ubuntu-mate-desktop|ubuntu-budgie-desktop|ubuntu-unity-desktop|ubuntustudio-desktop|edubuntu-desktop|ubuntukylin-desktop|gnome-shell|plasma-desktop|plasma-workspace|xfce4|lxqt|mate-desktop-environment|gdm3|sddm|lightdm|network-manager|[^ ]*pipewire[^ ]*|[^ ]*wireplumber[^ ]*|pulseaudio|cups-daemon)(:| )'

    if grep -Eq "$CRITICAL_RE" <<< "$SIM"; then
        echo
        echo "🚨 BLOCCO DI SICUREZZA"
        echo
        echo "APT vorrebbe rimuovere componenti critici:"
        echo
        awk '/^Remv / {print}' <<< "$SIM"
        echo
        echo "Nessun purge eseguito."
        exit 1
    fi

    sudo env \
        DEBIAN_FRONTEND=noninteractive \
        NEEDRESTART_MODE=a \
        apt-get purge -y "${PURGE_PKGS[@]}"
else
    echo "ℹ️ Nessun pacchetto APT Snap da purgare."

    echo
    echo "============================================================"
    echo "[7/9] Simulazione di sicurezza + purge"
    echo "============================================================"
    echo "ℹ️ Nulla da purgare."
fi

# ============================================================
# BLOCCO SNAP FUTURO
# ============================================================

sudo tee "$NOSNAP_PREF" >/dev/null <<'EOF2'
Package: snapd
Pin: version *
Pin-Priority: -1

Package: plasma-discover-backend-snap
Pin: version *
Pin-Priority: -1

Package: gnome-software-plugin-snap
Pin: version *
Pin-Priority: -1
EOF2

# ============================================================
# 8/9 - PULIZIA
# ============================================================

echo
echo "============================================================"
echo "[8/9] Pulizia residui Snap"
echo "============================================================"

sudo rm -rf \
    /var/cache/snapd \
    /var/lib/snapd \
    /var/snap \
    /snap \
    /root/snap

rm -rf "$HOME/snap"
sudo systemctl daemon-reload
hash -r

# ============================================================
# 9/9 - AUDIT
# ============================================================

echo
echo "============================================================"
echo "[9/9] Audit finale"
echo "============================================================"

FAIL=0

if command -v snap >/dev/null 2>&1; then
    echo "❌ comando snap ancora presente:"
    echo "   $(command -v snap)"
    FAIL=1
else
    echo "✅ comando snap: ASSENTE"
fi

if is_installed snapd; then
    echo "❌ pacchetto snapd ancora installato"
    FAIL=1
else
    echo "✅ pacchetto snapd: ASSENTE"
fi

FINAL_INSTALLED="$(get_firefox_installed)"
FINAL_CANDIDATE="$(get_firefox_candidate)"

echo
echo "Firefox:"
echo "  Installed : $FINAL_INSTALLED"
echo "  Candidate : $FINAL_CANDIDATE"

if [[ "$FINAL_INSTALLED" == "$FINAL_CANDIDATE" ]] && mozilla_has_version "$FINAL_INSTALLED"; then
    echo "✅ Firefox DEB Mozilla verificato"
else
    echo "⚠️ Firefox richiede verifica manuale"
    FAIL=1
fi

echo
echo "Policy snapd:"
LC_ALL=C apt-cache policy snapd | sed -n '1,12p'

echo
echo "Desktop rilevato : $DETECTED_DE"
echo "Flavour rilevato : $DETECTED_FLAVOUR"

echo

if ((FAIL == 0)); then
    echo "============================================================"
    echo " 💀 SNAP MORTO"
    echo " 🦊 FIREFOX DEB MOZILLA"
    echo " 🐧 ${HOST_NAME} SOPRAVVISSUTO"
    echo "============================================================"
else
    echo "============================================================"
    echo " ⚠️ BONIFICA COMPLETATA CON AVVISI"
    echo " 🐧 ${HOST_NAME} SOPRAVVISSUTO"
    echo "============================================================"
fi
