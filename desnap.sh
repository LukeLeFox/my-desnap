cat > ~/desnap.sh <<'EOF'
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


# ============================================================
# FUNZIONI
# ============================================================

is_installed() {
    local status

    status="$(
        LC_ALL=C dpkg-query \
            -W \
            -f='${db:Status-Abbrev}' \
            "$1" 2>/dev/null || true
    )"

    [[ "$status" == ii* ]]
}


detect_desktop() {
    local raw="${XDG_CURRENT_DESKTOP:-}:${XDG_SESSION_DESKTOP:-}:${DESKTOP_SESSION:-}"

    raw="${raw,,}"

    case "$raw" in
        *kde*|*plasma*)
            echo "KDE Plasma"
            return
            ;;
        *xubuntu*|*xfce*)
            echo "Xfce"
            return
            ;;
        *lubuntu*|*lxqt*)
            echo "LXQt"
            return
            ;;
        *mate*)
            echo "MATE"
            return
            ;;
        *budgie*)
            echo "Budgie"
            return
            ;;
        *unity*)
            echo "Unity"
            return
            ;;
        *cinnamon*)
            echo "Cinnamon"
            return
            ;;
        *gnome*|*ubuntu*)
            echo "GNOME"
            return
            ;;
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
    if is_installed kubuntu-desktop; then echo "Kubuntu"; return; fi
    if is_installed xubuntu-desktop; then echo "Xubuntu"; return; fi
    if is_installed lubuntu-desktop; then echo "Lubuntu"; return; fi
    if is_installed ubuntu-mate-desktop; then echo "Ubuntu MATE"; return; fi
    if is_installed ubuntu-budgie-desktop; then echo "Ubuntu Budgie"; return; fi
    if is_installed ubuntu-unity-desktop; then echo "Ubuntu Unity"; return; fi
    if is_installed ubuntustudio-desktop; then echo "Ubuntu Studio"; return; fi
    if is_installed edubuntu-desktop; then echo "Edubuntu"; return; fi
    if is_installed ubuntukylin-desktop; then echo "Ubuntu Kylin"; return; fi
    if is_installed ubuntu-desktop; then echo "Ubuntu Desktop"; return; fi

    echo "Ubuntu / flavour non identificato"
}


apt_install() {
    sudo env \
        DEBIAN_FRONTEND=noninteractive \
        NEEDRESTART_MODE=a \
        apt-get install -y "$@"
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
    echo "Questo script supporta Ubuntu e i flavour ufficiali basati direttamente su Ubuntu."
    echo "Sistema rilevato: ${PRETTY_NAME:-${ID:-sconosciuto}}"
    exit 1
fi


DETECTED_DE="$(detect_desktop)"
DETECTED_FLAVOUR="$(detect_flavour)"

VERSION_ID_NOW="${VERSION_ID:-0}"
CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-sconosciuto}}"


# ============================================================
# SNAP PRESENTI
# ============================================================

mapfile -t CURRENT_SNAPS < <(
    if command -v snap >/dev/null 2>&1; then
        LC_ALL=C snap list 2>/dev/null |
            awk 'NR>1 {print $1}' |
            sort -u || true
    fi
)


# ============================================================
# UNICA CONFERMA
# ============================================================

clear 2>/dev/null || true


cat <<INFO

╔══════════════════════════════════════════════════════════════╗
║            💣 DE-SNAP UNIVERSALE UBUNTU 💣                 ║
╚══════════════════════════════════════════════════════════════╝

Host       : $HOST_NAME
Sistema    : ${PRETTY_NAME:-Ubuntu}
Flavour    : $DETECTED_FLAVOUR
Desktop    : $DETECTED_DE
Release    : $VERSION_ID_NOW ($CODENAME)

Dopo questa UNICA conferma lo script farà automaticamente:

  → configurerà il repository APT ufficiale Mozilla
  → verificherà la fingerprint della chiave Mozilla
  → installerà Firefox DEB PRIMA di rimuovere Snap
  → consentirà un eventuale downgrade SOLO per Firefox
  → proverà a installare il language-pack Firefox del sistema
  → salverà e migrerà l'eventuale profilo Firefox Snap

  → rimuoverà TUTTI gli Snap con --purge
  → rimuoverà snapd
  → rimuoverà gli eventuali backend Snap degli store installati
  → eliminerà i residui Snap

  → bloccherà la reinstallazione via APT di snapd
  → bloccherà i backend Snap di Discover/GNOME Software

  → NON eseguirà apt autoremove
  → NON proverà a rimuovere libsnapd-glib / libsnapd-qt
  → simulerà il purge PRIMA di eseguirlo
  → si fermerà se APT tenta di rimuovere componenti critici

ATTENZIONE:

  Tutte le altre applicazioni Snap verranno eliminate e NON
  verranno automaticamente sostituite.

  I dati residui sotto ~/snap e /var/snap verranno eliminati.

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
    s|S|si|SI|sì|SÌ|y|Y|yes|YES)
        ;;
    *)
        echo "Operazione annullata."
        exit 0
        ;;
esac


# Da qui in poi nessun'altra conferma applicativa.
sudo -v


# ============================================================
# 1/9 - PREPARAZIONE
# ============================================================

echo
echo "============================================================"
echo "[1/9] Preparazione APT"
echo "============================================================"


sudo apt-get update


apt_install \
    ca-certificates \
    wget \
    gnupg


# ============================================================
# 2/9 - MOZILLA REPOSITORY
# ============================================================

echo
echo "============================================================"
echo "[2/9] Repository Mozilla"
echo "============================================================"


sudo install -d -m 0755 /etc/apt/keyrings


TMP_KEY="$(mktemp)"


wget -q \
    https://packages.mozilla.org/apt/repo-signing-key.gpg \
    -O "$TMP_KEY"


FPR="$(
    LC_ALL=C gpg \
        --show-keys \
        --with-colons \
        "$TMP_KEY" 2>/dev/null |
    awk -F: '$1=="fpr" {print $10; exit}'
)"


if [[ "$FPR" != "$EXPECTED_FPR" ]]; then
    echo
    echo "❌ Fingerprint Mozilla NON valida."
    echo "Ricevuta: ${FPR:-<vuota>}"
    echo "Attesa  : $EXPECTED_FPR"
    exit 1
fi


echo "✅ Fingerprint Mozilla verificata: $FPR"


sudo install \
    -m 0644 \
    "$TMP_KEY" \
    "$MOZILLA_KEY"


rm -f "$TMP_KEY"
TMP_KEY=""


# Evita duplicati se lo script viene rilanciato.
sudo rm -f \
    "$MOZILLA_LIST" \
    "$MOZILLA_SOURCES"


# Mozilla usa DEB822 da Ubuntu 26.04 Resolute in poi.
if dpkg --compare-versions \
    "$VERSION_ID_NOW" \
    ge \
    "26.04"
then

    sudo tee "$MOZILLA_SOURCES" >/dev/null <<EOF2
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: $MOZILLA_KEY
EOF2

else

    echo \
        "deb [signed-by=$MOZILLA_KEY] https://packages.mozilla.org/apt mozilla main" |
        sudo tee "$MOZILLA_LIST" >/dev/null

fi


# Priorità Mozilla + blocco wrapper Ubuntu/Snap Firefox.
sudo tee "$MOZILLA_PREF" >/dev/null <<'EOF2'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000

Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
EOF2


# Update DOPO aver aggiunto Mozilla.
sudo apt-get update


# ============================================================
# CONTROLLO REPOSITORY MOZILLA
# ============================================================

FIREFOX_POLICY="$(
    LC_ALL=C apt-cache policy firefox
)"


if ! grep -Fq \
    'packages.mozilla.org/apt' \
    <<< "$FIREFOX_POLICY"
then

    echo
    echo "❌ Il repository Mozilla non compare nella policy APT di Firefox."
    echo
    echo "Output di LC_ALL=C apt-cache policy firefox:"
    echo "------------------------------------------------------------"
    echo "$FIREFOX_POLICY"
    echo "------------------------------------------------------------"
    echo
    echo "Snap NON verrà toccato."

    exit 1

fi


FIREFOX_CANDIDATE="$(
    awk \
        '/^[[:space:]]*Candidate:/ {print $2; exit}' \
        <<< "$FIREFOX_POLICY"
)"


if [[ -z "$FIREFOX_CANDIDATE" ||
      "$FIREFOX_CANDIDATE" == "(none)" ]]
then

    echo
    echo "❌ Nessun candidato APT valido per Firefox."
    echo
    echo "$FIREFOX_POLICY"
    echo
    echo "Snap NON verrà toccato."

    exit 1

fi


if ! awk \
    -v candidate="$FIREFOX_CANDIDATE" '
        $1 == candidate {
            seen_candidate = 1
            next
        }

        seen_candidate && /packages\.mozilla\.org\/apt/ {
            found = 1
            exit
        }

        END {
            exit(found ? 0 : 1)
        }
    ' <<< "$FIREFOX_POLICY"
then

    echo
    echo "❌ Firefox ha un candidato, ma non riesco a confermare"
    echo "   che provenga dal repository Mozilla."
    echo
    echo "$FIREFOX_POLICY"
    echo
    echo "Snap NON verrà toccato."

    exit 1

fi


echo "✅ Repository Mozilla rilevato."
echo "✅ Candidate Firefox: $FIREFOX_CANDIDATE"


# ============================================================
# 3/9 - FIREFOX DEB
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


for LANG_PKG in \
    "firefox-l10n-$LOCALE_CODE" \
    "firefox-l10n-$LANG_BASE"
do

    [[ "$LANG_PKG" == "firefox-l10n-" ]] &&
        continue


    if LC_ALL=C apt-cache show \
        "$LANG_PKG" \
        >/dev/null 2>&1
    then

        FIREFOX_PKGS+=("$LANG_PKG")
        break

    fi

done


#
# Ubuntu può avere già installato il pacchetto wrapper/transitional
# firefox con una versione numericamente superiore alla versione
# Mozilla.
#
# Consentiamo il downgrade SOLO per questa installazione mirata.
#

sudo env \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_MODE=a \
    apt-get install \
        -y \
        --allow-downgrades \
        "${FIREFOX_PKGS[@]}"


if ! is_installed firefox; then

    echo
    echo "❌ Firefox DEB non risulta installato."
    echo "Snap NON verrà toccato."

    exit 1

fi


INSTALLED_POLICY="$(
    LC_ALL=C apt-cache policy firefox
)"


INSTALLED_VERSION="$(
    awk \
        '/^[[:space:]]*Installed:/ {print $2; exit}' \
        <<< "$INSTALLED_POLICY"
)"


CANDIDATE_VERSION="$(
    awk \
        '/^[[:space:]]*Candidate:/ {print $2; exit}' \
        <<< "$INSTALLED_POLICY"
)"


if [[ -z "$INSTALLED_VERSION" ||
      "$INSTALLED_VERSION" == "(none)" ]]
then

    echo
    echo "❌ Firefox non risulta installato secondo APT."
    echo "Snap NON verrà toccato."

    exit 1

fi


if [[ "$INSTALLED_VERSION" != "$CANDIDATE_VERSION" ]]; then

    echo
    echo "❌ Firefox installato non coincide con il candidato Mozilla."
    echo "Installed : $INSTALLED_VERSION"
    echo "Candidate : $CANDIDATE_VERSION"
    echo
    echo "Snap NON verrà toccato."

    exit 1

fi


echo "✅ Firefox DEB Mozilla installato: $INSTALLED_VERSION"


if ((${#FIREFOX_PKGS[@]} > 1)); then
    echo "✅ Language pack: ${FIREFOX_PKGS[1]}"
fi


# ============================================================
# 4/9 - BACKUP / MIGRAZIONE FIREFOX SNAP
# ============================================================

echo
echo "============================================================"
echo "[4/9] Backup/migrazione profilo Firefox Snap"
echo "============================================================"


SNAP_FF_PROFILE="$HOME/snap/firefox/common/.mozilla/firefox"


if pgrep \
    -x \
    firefox \
    >/dev/null 2>&1
then

    echo "ℹ️ Firefox è aperto: lo chiudo prima della migrazione..."

    pkill \
        -TERM \
        -x \
        firefox ||
        true

    sleep 2

fi


if [[ -d "$SNAP_FF_PROFILE" ]]; then

    BACKUP_DIR="$HOME/firefox-snap-backup-$(date +%Y%m%d-%H%M%S)"


    mkdir -p \
        "$BACKUP_DIR/firefox"


    cp -a \
        "$SNAP_FF_PROFILE"/. \
        "$BACKUP_DIR/firefox/"


    echo "✅ Backup Firefox Snap:"
    echo "   $BACKUP_DIR/firefox"


    mkdir -p \
        "$HOME/.mozilla/firefox"


    cp -an \
        "$SNAP_FF_PROFILE"/. \
        "$HOME/.mozilla/firefox/"


    echo "✅ Profilo copiato in ~/.mozilla/firefox"
    echo "   senza sovrascrivere file già presenti."

else

    echo "ℹ️ Nessun profilo Firefox Snap trovato."

fi


# ============================================================
# 5/9 - DETONAZIONE SNAP
# ============================================================

echo
echo "============================================================"
echo "[5/9] 💣 Rimozione di tutti gli Snap"
echo "============================================================"


if command -v snap >/dev/null 2>&1 &&
   LC_ALL=C snap list >/dev/null 2>&1
then

    for PASS in {1..10}; do

        mapfile -t SNAPS < <(
            LC_ALL=C snap list 2>/dev/null |
                awk 'NR>1 {print $1}' |
                sort -u ||
                true
        )


        ((${#SNAPS[@]} == 0)) &&
            break


        REMOVED=0


        for S in "${SNAPS[@]}"; do

            echo "Rimozione: $S"


            if sudo snap remove \
                --purge \
                "$S"
            then

                REMOVED=1

            fi

        done


        ((REMOVED == 0)) &&
            break

    done


    mapfile -t LEFT < <(
        LC_ALL=C snap list 2>/dev/null |
            awk 'NR>1 {print $1}' |
            sort -u ||
            true
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
# 6/9 - BACKEND SNAP DEL DESKTOP / STORE
# ============================================================

echo
echo "============================================================"
echo "[6/9] Rilevamento integrazioni Snap del desktop/store"
echo "============================================================"


PURGE_PKGS=()


for P in \
    snapd \
    plasma-discover-backend-snap \
    gnome-software-plugin-snap
do

    if is_installed "$P"; then

        PURGE_PKGS+=("$P")

        echo "  → trovato: $P"

    fi

done


if ((${#PURGE_PKGS[@]} > 0)); then

    sudo systemctl disable \
        --now \
        snapd.socket \
        snapd.service \
        snapd.seeded.service \
        >/dev/null 2>&1 ||
        true


    # ========================================================
    # 7/9 - SIMULAZIONE + PARACADUTE
    # ========================================================

    echo
    echo "============================================================"
    echo "[7/9] Simulazione di sicurezza + purge"
    echo "============================================================"


    SIM="$(
        LC_ALL=C apt-get \
            -s \
            purge \
            "${PURGE_PKGS[@]}" \
            2>&1 ||
        true
    )"


    CRITICAL_RE='^Remv (ubuntu-desktop|ubuntu-desktop-minimal|kubuntu-desktop|xubuntu-desktop|lubuntu-desktop|ubuntu-mate-desktop|ubuntu-budgie-desktop|ubuntu-unity-desktop|ubuntustudio-desktop|edubuntu-desktop|ubuntukylin-desktop|gnome-shell|plasma-desktop|plasma-workspace|xfce4|lxqt|mate-desktop-environment|gdm3|sddm|lightdm|network-manager|[^ ]*pipewire[^ ]*|[^ ]*wireplumber[^ ]*|pulseaudio|cups-daemon)(:| )'


    if grep -Eq \
        "$CRITICAL_RE" \
        <<< "$SIM"
    then

        echo
        echo "🚨 BLOCCO DI SICUREZZA"
        echo
        echo "APT vorrebbe rimuovere componenti critici:"
        echo


        awk \
            '/^Remv / {print}' \
            <<< "$SIM"


        echo
        echo "Nessun purge eseguito."

        exit 1

    fi


    sudo env \
        DEBIAN_FRONTEND=noninteractive \
        NEEDRESTART_MODE=a \
        apt-get purge \
        -y \
        "${PURGE_PKGS[@]}"

else

    echo "ℹ️ Nessun pacchetto APT Snap da purgare."


    echo
    echo "============================================================"
    echo "[7/9] Simulazione di sicurezza + purge"
    echo "============================================================"

    echo "ℹ️ Nulla da purgare via APT."

fi


# ============================================================
# BLOCCO FUTURO SNAP
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
# 8/9 - PULIZIA RESIDUI
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


rm -rf \
    "$HOME/snap"


sudo systemctl daemon-reload

hash -r


# ============================================================
# 9/9 - VERIFICA FINALE
# ============================================================

echo
echo "============================================================"
echo "[9/9] Verifica finale"
echo "============================================================"


FAIL=0


if command -v snap >/dev/null 2>&1; then

    echo "⚠️ comando snap ancora presente:"
    echo "   $(command -v snap)"

    FAIL=1

else

    echo "✅ comando snap: ASSENTE"

fi


if is_installed snapd; then

    echo "⚠️ pacchetto snapd ancora installato"

    FAIL=1

else

    echo "✅ pacchetto snapd: ASSENTE"

fi


echo
echo "Firefox:"


firefox \
    --version \
    2>/dev/null ||
    LC_ALL=C dpkg-query \
        -W \
        -f='${Version}\n' \
        firefox \
        2>/dev/null ||
    true


echo
echo "Sorgente APT Firefox:"


LC_ALL=C apt-cache policy firefox |
    sed -n '1,18p'


echo
echo "Desktop rilevato : $DETECTED_DE"
echo "Flavour rilevato : $DETECTED_FLAVOUR"


echo


if ((FAIL == 0)); then

    echo "============================================================"
    echo " 💀 SNAP MORTO"
    echo " 🦊 FIREFOX DEB INSTALLATO"
    echo " 🐧 ${HOST_NAME} SOPRAVVISSUTO"
    echo "============================================================"

else

    echo "============================================================"
    echo " ⚠️ BONIFICA COMPLETATA CON AVVISI"
    echo " 🐧 ${HOST_NAME} SOPRAVVISSUTO"
    echo "============================================================"

fi
EOF

chmod +x ~/desnap.sh
bash -n ~/desnap.sh && echo "✅ Sintassi OK"
~/desnap.sh
