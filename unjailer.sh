#!/usr/bin/env bash

set -e

WORKDIR="$HOME/.unjailer"
VENV_DIR="$WORKDIR/venv"
MTK_DIR="$WORKDIR/mtkclient"
UNJRC_DIR="$WORKDIR/unjrc_backups"
LOG_FILE="$WORKDIR/unjailer.log"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

mkdir -p "$WORKDIR" "$UNJRC_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo -e "${CYAN}=========================================${NC}"
echo -e "${CYAN}  UnJailer - MTK Xiaomi Tool by DeniusGG ${NC}"
echo -e "${CYAN}=========================================${NC}"

install_dependencies() {
    echo -e "${YELLOW}[*] Checking and installing system dependencies...${NC}"
    
    MISSING_PKGS=()
    for pkg in python3 python3-venv python3-pip git libusb-1.0-0 adb fastboot usbutils zenity openssl; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            MISSING_PKGS+=("$pkg")
        fi
    done

    if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
        echo -e "${YELLOW}[*] Installing missing packages: ${MISSING_PKGS[*]}${NC}"
        sudo apt-get update
        sudo apt-get install -y "${MISSING_PKGS[@]}"
    else
        echo -e "${GREEN}[+] all needed packages are installed, no additional installations needed${NC}"
    fi

    # Set up udev rules for MediaTek & Xiaomi devices
    if [ ! -f /etc/udev/rules.d/51-mtk-unjailer.rules ]; then
        echo -e "${YELLOW}[*] Configuring MediaTek udev rules, pls wait${NC}"
        cat << 'EOF' | sudo tee /etc/udev/rules.d/51-mtk-unjailer.rules >/dev/null
SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="2717", MODE="0666", GROUP="plugdev"
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"
EOF
        sudo udevadm control --reload-rules
        sudo udevadm trigger
    fi

    # Clone mtkclient
    if [ ! -d "$MTK_DIR" ]; then
        echo -e "${YELLOW}[*] Cloning mtkclient, pls wait${NC}"
        git clone https://github.com/bkerler/mtkclient.git "$MTK_DIR"
    fi

    # Setup Python Virtual Environment
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${YELLOW}[*] Creating Python virtual environment, pls wait${NC}"
        python3 -m venv "$VENV_DIR"
        "$VENV_DIR/bin/pip" install --upgrade pip wheel setuptools
        "$VENV_DIR/bin/pip" install -r "$MTK_DIR/requirements.txt"
        "$VENV_DIR/bin/pip" install "$MTK_DIR"
    else
        echo -e "${GREEN}[+] Python environment and mtkclient ready${NC}"
    fi
}

# ==============================================================================
# .UNJRC DATA RECOVERY & HELP MODULE
# ==============================================================================

show_unjrc_help() {
    echo ""
    echo -e "${CYAN}=====================================================${NC}"
    echo -e "${CYAN}               .unjrc Data Recovery Guide            ${NC}"
    echo -e "${CYAN}=====================================================${NC}"
    echo ""
    echo -e "${YELLOW}- What is .unjrc data recovery file?${NC}"
    echo "  A custom file for unjailer program. it scans the device data and information and backs up information like account, images, video, ect. it is all done locally, we do not receive any of your data, everything is done locally on your device!!"
    echo ""
    echo -e "${YELLOW}- What does unjrc file store?${NC}"
    echo "  It stores the files itself and where to apply them ."
    echo ""
    echo -e "${YELLOW}- Is unjrc safe?${NC}"
    echo "  It has encryption and a person cannot obtain all of your data via Unjrc. The file doesnt store all of your data and it locks itself until it sees the verification tool installed on your phone in a specific way without being replicated while creating the Unjrc file."
    echo ""
    echo -e "${YELLOW}- Can i use unjrc files in my projects?${NC}"
    echo "  Yes, you can but you have to give credit and you cannot change the Unjrc for your project and make the modification closed source. Even if your entire app is closed source, the specific config/change of unjrc in your project should be open source and easily accesible on a custom website or a Git website, eg. GitHub or lab."
    echo ""
    echo -e "${CYAN}=====================================================${NC}"
    read -rp "Press [Enter] to return..."
}

create_unjrc_file() {
    echo ""
    echo -e "${CYAN}=== Create a .unjrc Data Recovery File ===${NC}"
    echo -e "${YELLOW}[*] Make sure your phone is booted into Android with USB Debugging enabled.${NC}"
    echo -e "${YELLOW}[*] Waiting for ADB device connection...${NC}"

    while [ -z "$(adb devices | tail -n +2 | grep -w 'device')" ]; do
        sleep 1
    done

    SERIAL=$(adb devices | tail -n +2 | grep -w 'device' | head -n 1 | awk '{print $1}')
    CODENAME=$(adb -s "$SERIAL" shell getprop ro.product.device 2>/dev/null | tr -d '\r')
    MODEL=$(adb -s "$SERIAL" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    ANDROID_ID=$(adb -s "$SERIAL" shell settings get secure android_id 2>/dev/null | tr -d '\r')

    echo -e "${GREEN}[+] Connected: $MODEL ($CODENAME) [Serial: $SERIAL]${NC}"

    # Verify/bind hardware verification signature
    VERIFY_HASH=$(printf "%s:%s:%s" "$SERIAL" "$CODENAME" "$ANDROID_ID" | sha256sum | awk '{print $1}')
    adb -s "$SERIAL" shell "mkdir -p /sdcard/.unjailer_verify && echo '$VERIFY_HASH' > /sdcard/.unjailer_verify/token.sig" 2>/dev/null || true

    read -rsp "Create an encryption password for this .unjrc file: " UNJRC_PASS
    echo ""
    read -rsp "Confirm password: " UNJRC_PASS_CONFIRM
    echo ""

    if [ "$UNJRC_PASS" != "$UNJRC_PASS_CONFIRM" ] || [ -z "$UNJRC_PASS" ]; then
        echo -e "${RED}[!] Passwords do not match or cannot be empty.${NC}"
        return
    fi

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    STAGE_DIR="$WORKDIR/tmp_unjrc_$TIMESTAMP"
    OUT_FILE="$UNJRC_DIR/${CODENAME}_${TIMESTAMP}.unjrc"
    mkdir -p "$STAGE_DIR/files" "$STAGE_DIR/meta"

    echo -e "${YELLOW}[*] Scanning device information & account metadata locally...${NC}"
    adb -s "$SERIAL" shell dumpsys account | grep -E "Account {" > "$STAGE_DIR/meta/accounts.txt" 2>/dev/null || true
    adb -s "$SERIAL" shell pm list packages -3 > "$STAGE_DIR/meta/user_apps.txt" 2>/dev/null || true
    adb -s "$SERIAL" shell getprop > "$STAGE_DIR/meta/device_props.txt" 2>/dev/null || true

    # Create path mapping manifest (stores where to apply each directory)
    cat << 'EOF' > "$STAGE_DIR/meta/apply_map.txt"
DCIM|/sdcard/DCIM
Pictures|/sdcard/Pictures
Movies|/sdcard/Movies
Download|/sdcard/Download
Documents|/sdcard/Documents
EOF

    echo -e "${YELLOW}[*] Pulling user media & files locally (DCIM, Pictures, Movies, Download, Documents)...${NC}"
    for FOLDER in DCIM Pictures Movies Download Documents; do
        if adb -s "$SERIAL" shell "[ -d /sdcard/$FOLDER ]" 2>/dev/null; then
            echo "    -> Backing up /sdcard/$FOLDER..."
            adb -s "$SERIAL" pull "/sdcard/$FOLDER" "$STAGE_DIR/files/" >/dev/null 2>&1 || true
        fi
    done

    echo -e "${YELLOW}[*] Packing and encrypting .unjrc archive locally (AES-256-CBC)...${NC}"
    # Derive combined key from user password + device hardware verification signature
    COMBINED_KEY="${UNJRC_PASS}:${VERIFY_HASH}"

    tar -czf "$STAGE_DIR/payload.tar.gz" -C "$STAGE_DIR" files meta
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
        -in "$STAGE_DIR/payload.tar.gz" \
        -out "$STAGE_DIR/payload.enc" \
        -pass pass:"$COMBINED_KEY"

    # Write .unjrc container header + encrypted payload
    {
        echo "UNJRC_V1"
        echo "CREATED=$TIMESTAMP"
        echo "DEVICE=$CODENAME"
        echo "VERIFY_SIG=$VERIFY_HASH"
        echo "---PAYLOAD---"
        cat "$STAGE_DIR/payload.enc"
    } > "$OUT_FILE"

    rm -rf "$STAGE_DIR"

    echo ""
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN}[+] .unjrc Data Recovery File created successfully!${NC}"
    echo -e "${GREEN}    Saved to: ${CYAN}$OUT_FILE${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    read -rp "Press [Enter] to continue..."
}

restore_unjrc_file() {
    echo ""
    echo -e "${CYAN}=== Restore from .unjrc Data Recovery File ===${NC}"
    ls -1 "$UNJRC_DIR"/*.unjrc 2>/dev/null || { echo -e "${RED}[!] No .unjrc files found in $UNJRC_DIR${NC}"; return; }

    read -rp "Enter full path to .unjrc file: " IN_UNJRC
    IN_UNJRC="${IN_UNJRC%\"}"
    IN_UNJRC="${IN_UNJRC#\"}"
    if [ ! -f "$IN_UNJRC" ]; then
        echo -e "${RED}[!] File not found.${NC}"
        return
    fi

    echo -e "${YELLOW}[*] Connect your phone via ADB (with USB Debugging enabled)...${NC}"
    while [ -z "$(adb devices | tail -n +2 | grep -w 'device')" ]; do
        sleep 1
    done
    SERIAL=$(adb devices | tail -n +2 | grep -w 'device' | head -n 1 | awk '{print $1}')

    EXPECTED_SIG=$(head -n 5 "$IN_UNJRC" | grep "^VERIFY_SIG=" | cut -d'=' -f2)
    PHONE_SIG=$(adb -s "$SERIAL" shell "cat /sdcard/.unjailer_verify/token.sig 2>/dev/null" | tr -d '\r')

    if [ -z "$PHONE_SIG" ]; then
        echo -e "${YELLOW}[!] Verification token missing on wiped storage. Re-binding device hardware signature...${NC}"
        CODENAME=$(adb -s "$SERIAL" shell getprop ro.product.device 2>/dev/null | tr -d '\r')
        ANDROID_ID=$(adb -s "$SERIAL" shell settings get secure android_id 2>/dev/null | tr -d '\r')
        PHONE_SIG=$(printf "%s:%s:%s" "$SERIAL" "$CODENAME" "$ANDROID_ID" | sha256sum | awk '{print $1}')
    fi

    if [ "$EXPECTED_SIG" != "$PHONE_SIG" ]; then
        echo -e "${RED}[!] Verification lock mismatch! This .unjrc file belongs to another device or unverified environment.${NC}"
        return
    fi

    read -rsp "Enter .unjrc decryption password: " DEC_PASS
    echo ""

    RESTORE_STAGE="$WORKDIR/tmp_restore_$(date +%s)"
    mkdir -p "$RESTORE_STAGE"

    # Extract encrypted binary payload after ---PAYLOAD--- marker
    awk 'found{print} /^---PAYLOAD---$/{found=1}' "$IN_UNJRC" > "$RESTORE_STAGE/payload.enc"

    if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
        -in "$RESTORE_STAGE/payload.enc" \
        -out "$RESTORE_STAGE/payload.tar.gz" \
        -pass pass:"${DEC_PASS}:${EXPECTED_SIG}" 2>/dev/null; then
        echo -e "${RED}[!] Decryption failed. Incorrect password or corrupted .unjrc file.${NC}"
        rm -rf "$RESTORE_STAGE"
        return
    fi

    tar -xzf "$RESTORE_STAGE/payload.tar.gz" -C "$RESTORE_STAGE"

    echo -e "${YELLOW}[*] Applying files to mapped device directories...${NC}"
    while IFS='|' read -r SRC_NAME DEST_PATH; do
        if [ -d "$RESTORE_STAGE/files/$SRC_NAME" ]; then
            echo "    -> Restoring $SRC_NAME to $DEST_PATH..."
            adb -s "$SERIAL" push "$RESTORE_STAGE/files/$SRC_NAME/." "$DEST_PATH/" >/dev/null 2>&1 || true
        fi
    done < "$RESTORE_STAGE/meta/apply_map.txt"

    echo -e "${GREEN}[+] .unjrc recovery complete! Accounts & app list saved for reference in $UNJRC_DIR/last_meta/${NC}"
    mkdir -p "$UNJRC_DIR/last_meta"
    cp -r "$RESTORE_STAGE/meta/"* "$UNJRC_DIR/last_meta/" 2>/dev/null || true
    rm -rf "$RESTORE_STAGE"
}

startup_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}=========================================${NC}"
        echo -e "${CYAN}         UnJailer Startup Menu           ${NC}"
        echo -e "${CYAN}=========================================${NC}"
        echo "1) Create a .unjrc data recovery file"
        echo "2) See help for .unjrc"
        echo "3) Continue to UnJailer (Select OS & Device)"
        echo "4) Exit"
        read -rp "Select an option [1-4]: " START_OPT

        case $START_OPT in
            1) create_unjrc_file ;;
            2) show_unjrc_help ;;
            3) break ;;
            4) echo "Exiting UnJailer."; exit 0 ;;
            *) echo -e "${RED}[!] Invalid option. Please enter 1-4.${NC}" ;;
        esac
    done
}

# ==============================================================================
# DEVICE & OS SELECTION
# ==============================================================================

map_device_name() {
    local codename="$1"
    case "$codename" in
        selene|eos) echo "Redmi 10 / 10 Prime (selene - Helio G88)" ;;
        merlin|merlinnfc) echo "Redmi Note 9 / Redmi 10X 4G (merlin - Helio G85)" ;;
        lancelot) echo "Redmi 9 / POCO M2 (lancelot - Helio G80)" ;;
        dandelion) echo "Redmi 9A / 9i / 10A (dandelion - Helio G25)" ;;
        angelica|cattail) echo "Redmi 9C / POCO C3 (angelica - Helio G35)" ;;
        camellia|camellian) echo "Redmi Note 10 5G / POCO M3 Pro 5G (camellia - Dimensity 700)" ;;
        rosemary|maltose|secret) echo "Redmi Note 10S / POCO M5s (rosemary - Helio G95)" ;;
        fleur|miel) echo "Redmi Note 11S / POCO M4 Pro 4G (fleur - Helio G96)" ;;
        evergreen|evergo) echo "POCO M4 Pro 5G / Redmi Note 11 5G (evergreen - Dimensity 810)" ;;
        begonia|begoniain) echo "Redmi Note 8 Pro (begonia - Helio G90T)" ;;
        atom|bomb) echo "Redmi 10X 5G / 10X Pro (atom/bomb - Dimensity 820)" ;;
        cezanne) echo "Redmi K30 Ultra (cezanne - Dimensity 1000+)" ;;
        ares|aresin) echo "Redmi K40 Gaming / POCO F3 GT (ares - Dimensity 1200)" ;;
        chopin) echo "Redmi Note 10 Pro CN / POCO X3 GT (chopin - Dimensity 1100)" ;;
        *) echo "Xiaomi MediaTek Device ($codename)" ;;
    esac
}

select_os_version() {
    echo ""
    echo -e "${ORANGE}Please select your OS version group (MIUI / HyperOS - Global & CN):${NC}"
    echo "1) Legacy MIUI (MIUI 11 / 12 / 13 / Early 14.0.1-14.0.2) [Global & CN]"
    echo "2) Modern MIUI & HyperOS (MIUI 14.0.3+ / HyperOS 1 / 2 / 3) [Global & CN]"
    read -rp "Enter OS version choice [1-2]: " OS_CHOICE

    case $OS_CHOICE in
        1) MODE="legacy"; OS_LABEL="MIUI 11-13 (Legacy seccfg)" ;;
        2) MODE="hyperos"; OS_LABEL="MIUI 14+ / HyperOS 1-3 (RPMB + seccfg)" ;;
        *) echo -e "${RED}[!] Invalid OS selection.${NC}"; exit 1 ;;
    esac
    echo -e "${GREEN}[+] OS Profile: $OS_LABEL${NC}"
}

select_device() {
    echo ""
    echo -e "${CYAN}Scanning for connected phones (ADB / Fastboot / MediaTek BROM)...${NC}"
    
    DEVICES=()
    DEVICE_LABELS=()

    # 1. Check ADB connected devices
    if command -v adb >/dev/null 2>&1; then
        while IFS= read -r line; do
            SERIAL=$(echo "$line" | awk '{print $1}')
            STATE=$(echo "$line" | awk '{print $2}')
            if [ -n "$SERIAL" ] && [ "$STATE" == "device" ]; then
                CODENAME=$(adb -s "$SERIAL" shell getprop ro.product.device 2>/dev/null | tr -d '\r')
                REGION=$(adb -s "$SERIAL" shell getprop ro.miui.region 2>/dev/null | tr -d '\r')
                FRIENDLY=$(map_device_name "$CODENAME")
                DEVICES+=("ADB:$SERIAL")
                DEVICE_LABELS+=("$FRIENDLY [ADB: $SERIAL | Region: ${REGION:-Unknown}]")
            fi
        done < <(adb devices | tail -n +2)
    fi

    # 2. Check Fastboot connected devices
    if command -v fastboot >/dev/null 2>&1; then
        while IFS= read -r fb_line; do
            FB_SERIAL=$(echo "$fb_line" | awk '{print $1}')
            if [ -n "$FB_SERIAL" ]; then
                FB_PROD=$(fastboot -s "$FB_SERIAL" getvar product 2>&1 | grep "product:" | awk '{print $2}' | tr -d '\r')
                FRIENDLY=$(map_device_name "${FB_PROD:-unknown}")
                DEVICES+=("FASTBOOT:$FB_SERIAL")
                DEVICE_LABELS+=("$FRIENDLY [Fastboot: $FB_SERIAL]")
            fi
        done < <(fastboot devices)
    fi

    # 3. Check USB bus for MediaTek BROM/Preloader (0e8d) & Xiaomi USB (2717)
    while IFS= read -r usb_line; do
        BUS=$(echo "$usb_line" | awk '{print $2}')
        DEV=$(echo "$usb_line" | awk '{print $4}' | tr -d ':')
        ID=$(echo "$usb_line" | awk '{print $6}')
        DESC=$(echo "$usb_line" | cut -d' ' -f7-)

        if [[ "$ID" == 0e8d:* ]]; then
            DEVICES+=("USB:$BUS:$DEV")
            DEVICE_LABELS+=("Connected MediaTek BROM/Preloader ($DESC) [Bus $BUS Dev $DEV]")
        elif [[ "$ID" == 2717:* ]]; then
            DEVICES+=("USB:$BUS:$DEV")
            DEVICE_LABELS+=("Connected Xiaomi Phone ($DESC) [Bus $BUS Dev $DEV]")
        fi
    done < <(lsusb)

    # Always provide manual/waiting fallback option
    DEVICES+=("MANUAL_BROM")
    DEVICE_LABELS+=("Wait for Phone in BROM Mode (Redmi 10 selene / Any Supported MTK)")

    echo ""
    echo -e "${CYAN}Select target device:${NC}"
    for i in "${!DEVICE_LABELS[@]}"; do
        echo "$((i+1))) ${DEVICE_LABELS[$i]}"
    done

    read -rp "Enter choice [1-${#DEVICE_LABELS[@]}]: " DEV_CHOICE

    if ! [[ "$DEV_CHOICE" =~ ^[0-9]+$ ]] || [ "$DEV_CHOICE" -lt 1 ] || [ "$DEV_CHOICE" -gt "${#DEVICE_LABELS[@]}" ]; then
        echo -e "${RED}[!] Invalid selection.${NC}"
        exit 1
    fi

    SELECTED_TARGET="${DEVICES[$((DEV_CHOICE-1))]}"
    DEVICE_NAME="${DEVICE_LABELS[$((DEV_CHOICE-1))]}"
    echo -e "${GREEN}[+] Selected: $DEVICE_NAME${NC}"
}

run_unjail() {
    echo ""
    echo -e "${RED}warning, unlocking the bootloader will cause a full data wipe. the developers of the tool are not responsible for any kinds of damages, and by continuing you agree to these terms.${NC}"

    if [[ "$SELECTED_TARGET" == ADB:* ]]; then
        SERIAL="${SELECTED_TARGET#ADB:}"
        echo -e "${YELLOW}[*] Sending shutdown command to ADB device ($SERIAL)...${NC}"
        adb -s "$SERIAL" shell reboot -p || true
        sleep 3
    fi

    if systemctl is-active --quiet ModemManager; then
        echo -e "${YELLOW}[*] Temporarily stopping ModemManager to prevent USB port conflicts...${NC}"
        sudo systemctl stop ModemManager
        RESTORE_MM=1
    fi

    echo -e "${YELLOW}[*] Put your phone into BROM mode now:${NC}"
    echo "    1. Ensure the phone is completely powered OFF."
    echo "    2. Hold BOTH Volume Up + Volume Down buttons."
    echo "    3. While holding them, plug the USB cable into a USB 2.0 (black) port."
    echo ""

    BACKUP_DIR="$WORKDIR/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    MTK_BIN="$VENV_DIR/bin/python $MTK_DIR/mtk.py"

    echo -e "${YELLOW}[*] Waiting for device in BROM mode, check that ur device is in Brom${NC}"
    echo -e "${YELLOW}[*] Step 1/4: Backing up NV/IMEI & security partitions to $BACKUP_DIR...${NC}"
    $MTK_BIN r nvdata,nvcfg,nvram,persist,protect1,protect2,seccfg \
        "$BACKUP_DIR/nvdata.bin","$BACKUP_DIR/nvcfg.bin","$BACKUP_DIR/nvram.bin","$BACKUP_DIR/persist.bin","$BACKUP_DIR/protect1.bin","$BACKUP_DIR/protect2.bin","$BACKUP_DIR/seccfg.bin"

    if [ "$MODE" == "hyperos" ]; then
        echo -e "${YELLOW}[*] Step 2/4: Dumping RPMB to locate HyperOS/CN lock magic...${NC}"
        $MTK_BIN da rpmb r "$BACKUP_DIR/rpmb_backup.bin"

        MAGIC_OFFSET=$(grep -boa "Jz8PNRUF" "$BACKUP_DIR/rpmb_backup.bin" | head -n 1 | cut -d':' -f1 || true)

        if [ -n "$MAGIC_OFFSET" ]; then
            TARGET_SECTOR=$((MAGIC_OFFSET / 256))
            echo -e "${GREEN}[+] Found HyperOS/MIUI14+ RPMB lock magic at byte $MAGIC_OFFSET (Sector $TARGET_SECTOR).${NC}"
            echo -e "${YELLOW}[*] Step 3/4: Clearing 4 RPMB sectors starting at sector $TARGET_SECTOR...${NC}"
            $MTK_BIN da rpmb e --sector "$TARGET_SECTOR" --sectors 4
        else
            echo -e "${YELLOW}[!] RPMB lock magic not present (already cleared or older LK). Skipping RPMB erase.${NC}"
        fi
    else
        echo -e "${YELLOW}[*] Step 2/4 & 3/4: Skipping RPMB erase (Legacy MIUI selected)...${NC}"
    fi

    echo -e "${YELLOW}[*] Step 4/4: Writing unlock flag to seccfg...${NC}"
    $MTK_BIN da seccfg unlock

    if [ "${RESTORE_MM:-0}" -eq 1 ]; then
        sudo systemctl start ModemManager || true
    fi

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}      Successfully unjailed, enjoy.      ${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}      Please star and share the repo     ${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "Your critical IMEI/NV backups are stored at: ${CYAN}$BACKUP_DIR${NC}"
    echo "Unplug your device and hold Power for ~10 seconds to reboot."
}

# ==============================================================================
# POST-UNJAIL MODULES
# ==============================================================================

wait_for_fastboot() {
    echo -e "${YELLOW}[*] Waiting for Fastboot device...${NC}"
    while [ -z "$(fastboot devices)" ]; do
        sleep 1
    done
    echo -e "${GREEN}[+] Fastboot device connected: $(fastboot devices | awk '{print $1}')${NC}"
}

dm_verity_fix() {
    echo ""
    echo -e "${CYAN}=== Dm-Verity & AVB Corruption Fix ===${NC}"
    echo -e "${YELLOW}Boot into fastboot via Volume Down and Power, then press Enter to continue.${NC}"
    read -rp "Press [Enter] once your phone is on the FASTBOOT screen..."

    wait_for_fastboot

    PATCHED_VBMETA="$WORKDIR/vbmeta_disabled.img"
    if [ ! -f "$PATCHED_VBMETA" ]; then
        dd if=/dev/zero of="$PATCHED_VBMETA" bs=4096 count=1 status=none
        printf "AVB0" | dd of="$PATCHED_VBMETA" bs=1 seek=0 conv=notrunc status=none
        printf "\x03" | dd of="$PATCHED_VBMETA" bs=1 seek=123 conv=notrunc status=none
    fi

    read -rp "Do you have a stock vbmeta.img to patch/flash instead of blank AVB2 header? (y/N): " USE_STOCK
    if [[ "$USE_STOCK" =~ ^[Yy]$ ]]; then
        read -rp "Enter full path to stock vbmeta.img: " STOCK_VB
        if [ -f "$STOCK_VB" ]; then
            TARGET_VB="$STOCK_VB"
        else
            echo -e "${RED}[!] File not found, falling back to generated AVB2 disabled vbmeta.${NC}"
            TARGET_VB="$PATCHED_VBMETA"
        fi
    else
        TARGET_VB="$PATCHED_VBMETA"
    fi

    SLOT=$(fastboot getvar current-slot 2>&1 | grep "current-slot:" | awk '{print $2}' | tr -d '\r')
    if [ "$SLOT" == "a" ] || [ "$SLOT" == "b" ]; then
        echo -e "${YELLOW}[*] A/B device detected (active slot: $SLOT). Disabling verity on both slots...${NC}"
        fastboot --disable-verity --disable-verification flash vbmeta_a "$TARGET_VB" || true
        fastboot --disable-verity --disable-verification flash vbmeta_b "$TARGET_VB" || true
        fastboot --disable-verity --disable-verification flash vbmeta_system_a "$TARGET_VB" 2>/dev/null || true
        fastboot --disable-verity --disable-verification flash vbmeta_system_b "$TARGET_VB" 2>/dev/null || true
    else
        echo -e "${YELLOW}[*] Single-slot device detected. Flashing vbmeta with verity disabled...${NC}"
        fastboot --disable-verity --disable-verification flash vbmeta "$TARGET_VB"
    fi

    read -rp "Erase /metadata to clear old encryption state? (Recommended if bootlooping) [y/N]: " WIPE_META
    if [[ "$WIPE_META" =~ ^[Yy]$ ]]; then
        fastboot erase metadata || true
    fi

    echo -e "${GREEN}[+] Dm-Verity disabled! Rebooting device...${NC}"
    fastboot reboot
}

flasher_gui() {
    if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        echo -e "${RED}[!] No graphical display detected. Use Flasher TUI instead.${NC}"
        return
    fi

    IMG_FILE=$(zenity --file-selection --title="UnJailer Flasher GUI - Select Image or GSI (.img)" --file-filter="Android Images (*.img *.bin) | *.img *.bin" --file-filter="All Files | *" 2>/dev/null) || return

    PARTITION=$(zenity --list --title="UnJailer Flasher GUI - Target Partition" \
        --text="Select the target partition for:\n$(basename "$IMG_FILE")" \
        --column="Partition" --column="Description" \
        "boot" "Kernel / Magisk Patched Boot Image" \
        "recovery" "Custom Recovery (TWRP / OrangeFox / PitchBlack)" \
        "vbmeta" "Android Verified Boot (Auto --disable-verity)" \
        "system" "GSI System Image (Standard / FastbootD)" \
        "super" "Super / Dynamic GSI Image" \
        "dtbo" "Device Tree Blob Overlay" \
        "vendor_boot" "Vendor Boot Image" \
        "CUSTOM" "Enter Custom Partition Name..." 2>/dev/null) || return

    if [ "$PARTITION" == "CUSTOM" ]; then
        PARTITION=$(zenity --entry --title="Custom Partition" --text="Enter exact partition name (e.g., boot_a, lk, logo):" 2>/dev/null) || return
    fi

    zenity --question --title="Confirm Flash" --text="Flash $(basename "$IMG_FILE") to [$PARTITION]?\n\nMake sure your phone is in Fastboot / FastbootD mode." 2>/dev/null || return

    wait_for_fastboot
    if [ "$PARTITION" == "vbmeta" ]; then
        fastboot --disable-verity --disable-verification flash vbmeta "$IMG_FILE"
    else
        fastboot flash "$PARTITION" "$IMG_FILE"
    fi

    zenity --info --title="UnJailer Flasher GUI" --text="Successfully flashed $(basename "$IMG_FILE") to $PARTITION!" 2>/dev/null || true
}

flasher_tui() {
    echo ""
    echo -e "${CYAN}=== UnJailer Flasher TUI (Terminal Image & GSI Flasher) ===${NC}"
    read -rp "Enter full path to .img / .bin file: " IMG_PATH
    IMG_PATH="${IMG_PATH%\"}"
    IMG_PATH="${IMG_PATH#\"}"
    IMG_PATH="${IMG_PATH%\'}"
    IMG_PATH="${IMG_PATH#\'}"

    if [ ! -f "$IMG_PATH" ]; then
        echo -e "${RED}[!] File does not exist: $IMG_PATH${NC}"
        return
    fi

    echo ""
    echo "Select Target Partition / Mode:"
    echo "1) boot (Kernel / Magisk Root)"
    echo "2) recovery (TWRP / OrangeFox)"
    echo "3) vbmeta (With --disable-verity --disable-verification)"
    echo "4) GSI Flash (Reboots to FastbootD, resizes logical system, flashes GSI)"
    echo "5) super (Full super.img)"
    echo "6) Custom partition name"
    read -rp "Choice [1-6]: " P_CHOICE

    wait_for_fastboot

    case $P_CHOICE in
        1) fastboot flash boot "$IMG_PATH" ;;
        2) fastboot flash recovery "$IMG_PATH" ;;
        3) fastboot --disable-verity --disable-verification flash vbmeta "$IMG_PATH" ;;
        4)
            echo -e "${YELLOW}[*] Rebooting into FastbootD for GSI flashing...${NC}"
            fastboot reboot fastboot
            sleep 5
            wait_for_fastboot
            echo -e "${YELLOW}[*] Preparing logical partitions...${NC}"
            fastboot delete-logical-partition product_a 2>/dev/null || true
            fastboot delete-logical-partition product_b 2>/dev/null || true
            fastboot flash system "$IMG_PATH"
            echo -e "${YELLOW}[*] Formatting userdata (required for GSI boot)...${NC}"
            fastboot -w
            ;;
        5) fastboot flash super "$IMG_PATH" ;;
        6)
            read -rp "Enter exact partition name: " CUST_PART
            fastboot flash "$CUST_PART" "$IMG_PATH"
            ;;
        *) echo -e "${RED}[!] Invalid option.${NC}"; return ;;
    esac

    echo -e "${GREEN}[+] TUI Flash operation completed!${NC}"
    read -rp "Reboot device now? (y/N): " REB
    [[ "$REB" =~ ^[Yy]$ ]] && fastboot reboot
}

flasher_agui() {
    if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        echo -e "${RED}[!] No graphical display detected. Use Flasher TUI instead.${NC}"
        return
    fi

    while true; do
        AGUI_ACTION=$(zenity --list --width=620 --height=420 \
            --title="UnJailer AGUI - Advanced MediaTek & Fastboot Control Suite" \
            --text="Select an Advanced Flashing or Partition Management Operation:" \
            --column="Action" --column="Technical Description" \
            "1. Standard Fastboot Flash" "Flash any .img to boot, recovery, dtbo, vendor_boot, etc." \
            "2. GSI / Treble Full Installer" "Reboot FastbootD, delete product partition, flash GSI + format data" \
            "3. BROM Raw Partition Write" "Write raw .bin/.img directly via MTKClient BROM (unbrick / bypass)" \
            "4. BROM Partition Backup" "Dump specific partition (boot, lk, nvram, super) via MTKClient" \
            "5. Slot Manager (A/B)" "Switch active boot slot between _a and _b" \
            "6. Erase / Format Partition" "Wipe userdata, cache, metadata, or dalvik" \
            "7. Reboot Controller" "Reboot to System, Recovery, Bootloader, or FastbootD" \
            "8. Close AGUI" "Return to UnJailer Main Menu" 2>/dev/null) || break

        case "$AGUI_ACTION" in
            "1."*)
                flasher_gui
                ;;
            "2."*)
                GSI_IMG=$(zenity --file-selection --title="Select GSI System Image (.img)" --file-filter="*.img" 2>/dev/null) || continue
                zenity --question --title="GSI Warning" --text="This will reboot to FastbootD, resize dynamic partitions, flash $(basename "$GSI_IMG"), and wipe userdata. Continue?" 2>/dev/null || continue
                wait_for_fastboot
                fastboot reboot fastboot
                sleep 5
                wait_for_fastboot
                fastboot delete-logical-partition product_a 2>/dev/null || true
                fastboot delete-logical-partition product_b 2>/dev/null || true
                fastboot flash system "$GSI_IMG"
                fastboot -w
                zenity --info --title="AGUI" --text="GSI installation complete!" 2>/dev/null || true
                ;;
            "3."*)
                BROM_IMG=$(zenity --file-selection --title="Select Raw Image for BROM Write" 2>/dev/null) || continue
                BROM_PART=$(zenity --entry --title="BROM Target Partition" --text="Enter target partition name (e.g., lk, boot, recovery, preloader):" 2>/dev/null) || continue
                zenity --info --title="Enter BROM" --text="Power off phone completely, hold Vol+ & Vol-, and plug in USB now. Click OK to start." 2>/dev/null || continue
                "$VENV_DIR/bin/python" "$MTK_DIR/mtk.py" w "$BROM_PART" "$BROM_IMG"
                zenity --info --title="AGUI" --text="BROM write to $BROM_PART complete!" 2>/dev/null || true
                ;;
            "4."*)
                DUMP_PART=$(zenity --entry --title="BROM Partition Dump" --text="Enter partition name to dump (e.g., boot, lk, vbmeta, seccfg):" 2>/dev/null) || continue
                OUT_DUMP="$WORKDIR/backups/${DUMP_PART}_$(date +%s).bin"
                zenity --info --title="Enter BROM" --text="Power off phone completely, hold Vol+ & Vol-, and plug in USB now. Click OK to dump." 2>/dev/null || continue
                "$VENV_DIR/bin/python" "$MTK_DIR/mtk.py" r "$DUMP_PART" "$OUT_DUMP"
                zenity --info --title="AGUI" --text="Saved dump to:\n$OUT_DUMP" 2>/dev/null || true
                ;;
            "5."*)
                TARGET_SLOT=$(zenity --list --title="A/B Slot Switcher" --column="Slot" "a" "b" 2>/dev/null) || continue
                wait_for_fastboot
                fastboot --set-active="$TARGET_SLOT"
                zenity --info --title="AGUI" --text="Active slot set to: $TARGET_SLOT" 2>/dev/null || true
                ;;
            "6."*)
                WIPE_TARGET=$(zenity --list --title="Erase Partition" --column="Target" "userdata" "metadata" "cache" 2>/dev/null) || continue
                zenity --question --title="Confirm Wipe" --text="Are you sure you want to erase [$WIPE_TARGET]?" 2>/dev/null || continue
                wait_for_fastboot
                fastboot erase "$WIPE_TARGET"
                zenity --info --title="AGUI" --text="Erased $WIPE_TARGET successfully." 2>/dev/null || true
                ;;
            "7."*)
                REB_MODE=$(zenity --list --title="Reboot Controller" --column="Mode" "system" "bootloader" "recovery" "fastboot" 2>/dev/null) || continue
                wait_for_fastboot
                if [ "$REB_MODE" == "system" ]; then
                    fastboot reboot
                else
                    fastboot reboot "$REB_MODE"
                fi
                ;;
            *)
                break
                ;;
        esac
    done
}

check_status() {
    echo ""
    echo -e "${CYAN}=== Checking Bootloader & Security Status ===${NC}"
    if [ -n "$(fastboot devices)" ]; then
        echo -e "${GREEN}[+] Fastboot Device Detected:${NC}"
        fastboot getvar unlocked 2>&1 | grep -v "Finished" || true
        fastboot getvar secure 2>&1 | grep -v "Finished" || true
        fastboot getvar current-slot 2>&1 | grep -v "Finished" || true
        fastboot getvar anti 2>&1 | grep -v "Finished" || true
    elif [ -n "$(adb devices | tail -n +2 | grep device)" ]; then
        echo -e "${GREEN}[+] ADB Device Detected:${NC}"
        echo "Bootloader Flash Locked: $(adb shell getprop ro.boot.flash.locked | tr -d '\r')"
        echo "Verified Boot State:     $(adb shell getprop ro.boot.verifiedbootstate | tr -d '\r')"
        echo "Verity Mode:             $(adb shell getprop ro.boot.veritymode | tr -d '\r')"
        echo "Active Slot:             $(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
    else
        echo -e "${YELLOW}[!] No phone detected in ADB or Fastboot. Connect your phone in Fastboot (Vol Down + Power) or ADB to read live status.${NC}"
    fi
}

check_device_info() {
    echo ""
    echo -e "${CYAN}=== Device Hardware & Firmware Info ===${NC}"
    if [ -n "$(fastboot devices)" ]; then
        fastboot getvar all 2>&1 | grep -E "product|variant|serialno|hw-revision|version-bootloader|version-baseband|max-download-size|partition-type" || true
    elif [ -n "$(adb devices | tail -n +2 | grep device)" ]; then
        echo "Model:          $(adb shell getprop ro.product.model | tr -d '\r')"
        echo "Codename:       $(adb shell getprop ro.product.device | tr -d '\r')"
        echo "SoC / Platform: $(adb shell getprop ro.board.platform | tr -d '\r')"
        echo "MIUI / HyperOS: $(adb shell getprop ro.miui.ui.version.name | tr -d '\r') ($(adb shell getprop ro.build.version.incremental | tr -d '\r'))"
        echo "Android Ver:    $(adb shell getprop ro.build.version.release | tr -d '\r')"
        echo "Region:         $(adb shell getprop ro.miui.region | tr -d '\r')"
    else
        echo -e "${YELLOW}[!] Connect device in ADB or Fastboot first.${NC}"
    fi
}

check_errors() {
    echo ""
    echo -e "${CYAN}=== Scanning for System, USB & Flashing Errors ===${NC}"
    ERRORS_FOUND=0

    if [ ! -f /etc/udev/rules.d/51-mtk-unjailer.rules ]; then
        echo -e "${RED}[ERROR] MediaTek udev rules missing (/etc/udev/rules.d/51-mtk-unjailer.rules).${NC}"
        ERRORS_FOUND=$((ERRORS_FOUND+1))
    else
        echo -e "${GREEN}[OK] udev rules present.${NC}"
    fi

    if systemctl is-active --quiet ModemManager; then
        echo -e "${YELLOW}[WARNING] ModemManager is currently running (can hijack MediaTek BROM ports if not stopped).${NC}"
        ERRORS_FOUND=$((ERRORS_FOUND+1))
    else
        echo -e "${GREEN}[OK] ModemManager is inactive.${NC}"
    fi

    USB_ERRS=$(dmesg 2>/dev/null | grep -iE "0e8d|mtk|usb.*error|unable to enumerate" | tail -n 5 || true)
    if [ -n "$USB_ERRS" ]; then
        echo -e "${YELLOW}[WARNING] Recent USB/MediaTek kernel messages found:${NC}"
        echo "$USB_ERRS"
    else
        echo -e "${GREEN}[OK] No kernel USB enumeration errors detected.${NC}"
    fi

    if grep -qiE "Traceback|Error:|LIBUSB_ERROR" "$LOG_FILE" 2>/dev/null; then
        echo -e "${RED}[ERROR] Previous execution errors found in $LOG_FILE:${NC}"
        grep -iE "Error:|LIBUSB_ERROR" "$LOG_FILE" | tail -n 5
        ERRORS_FOUND=$((ERRORS_FOUND+1))
    else
        echo -e "${GREEN}[OK] No Python/libusb exceptions recorded in session log.${NC}"
    fi

    echo -e "${CYAN}Total issues flagged: $ERRORS_FOUND${NC}"
}

run_diagnostics() {
    echo ""
    echo -e "${CYAN}=== Running Full UnJailer Environment & Hardware Diagnostics ===${NC}"
    
    echo -n "1. Python VirtualEnv & MTKClient: "
    if "$VENV_DIR/bin/python" "$MTK_DIR/mtk.py" --help >/dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${RED}FAIL (Re-run dependency installer)${NC}"
    fi

    echo -n "2. ADB & Fastboot Binaries:       "
    if command -v adb >/dev/null 2>&1 && command -v fastboot >/dev/null 2>&1; then
        echo -e "${GREEN}PASS ($(fastboot --version | head -n 1))${NC}"
    else
        echo -e "${RED}FAIL${NC}"
    fi

    echo -n "3. Zenity GUI Subsystem:          "
    if command -v zenity >/dev/null 2>&1 && [ -n "$DISPLAY$WAYLAND_DISPLAY" ]; then
        echo -e "${GREEN}PASS${NC}"
    else
        echo -e "${YELLOW}HEADLESS / NO DISPLAY (Use TUI mode)${NC}"
    fi

    echo "4. USB Host Controllers:"
    lsusb -t | grep -E "Class=root_hub" || true
    if lsusb -t | grep -q "5000M\|10000M"; then
        echo -e "   ${YELLOW}[TIP] USB 3.0 (5000M+) hubs detected. Ensure your cable is plugged into a USB 2.0 (480M / black) port for reliable BROM handshakes.${NC}"
    fi

    BACKUP_COUNT=$(find "$WORKDIR/backups" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    UNJRC_COUNT=$(find "$UNJRC_DIR" -maxdepth 1 -name "*.unjrc" 2>/dev/null | wc -l)
    echo -e "5. Saved NVRAM/IMEI Backups:      ${GREEN}$BACKUP_COUNT backup set(s)${NC}"
    echo -e "6. Saved .unjrc Recovery Files:   ${GREEN}$UNJRC_COUNT file(s) in $UNJRC_DIR${NC}"
}

post_unjail_menu() {
    while true; do
        echo ""
        echo -e "${MAGENTA}=====================================================${NC}"
        echo -e "${MAGENTA}      UnJailer Post-Unlock & Flashing Suite          ${NC}"
        echo -e "${MAGENTA}=====================================================${NC}"
        echo "1)  Unjail (Backup Critical Data & Unlock Bootloader)"
        echo "2)  Dm-Verity fix (Disable AVB/Verity via Fastboot)"
        echo "3)  Flasher GUI (Desktop Image & GSI Flasher)"
        echo "4)  Flasher TUI (Terminal Image & GSI Flasher)"
        echo "5)  Flasher AGUI (Advanced Multi-Tool GUI Suite)"
        echo "6)  Check status (Bootloader, Verity, Slot & Anti-Rollback)"
        echo "7)  Check device info (Hardware, SoC & Firmware Props)"
        echo "8)  Check for any errors (USB, udev, ModemManager & Logs)"
        echo "9)  Run diagnostics (Full Environment & Port Health Check)"
        echo "10) Reboot Manager (System / Recovery / Bootloader / FastbootD)"
        echo "11) Restore NVRAM / IMEI Backup (BROM Mode)"
        echo "12) Restore from .unjrc Data Recovery File (ADB)"
        echo "13) Relock Bootloader (Stock Firmware Only!)"
        echo "14) Done, exit the program"
        echo -e "${MAGENTA}-----------------------------------------------------${NC}"
        read -rp "Select an option [1-14]: " MENU_OPT

        case $MENU_OPT in
            1) run_unjail ;;
            2) dm_verity_fix ;;
            3) flasher_gui ;;
            4) flasher_tui ;;
            5) flasher_agui ;;
            6) check_status ;;
            7) check_device_info ;;
            8) check_errors ;;
            9) run_diagnostics ;;
            10)
                echo "Reboot target: 1) System  2) Recovery  3) Bootloader  4) FastbootD"
                read -rp "Choice [1-4]: " R_OPT
                wait_for_fastboot
                case $R_OPT in
                    1) fastboot reboot ;;
                    2) fastboot reboot recovery ;;
                    3) fastboot reboot bootloader ;;
                    4) fastboot reboot fastboot ;;
                esac
                ;;
            11)
                echo -e "${CYAN}Available backups:${NC}"
                ls -1 "$WORKDIR/backups" 2>/dev/null || echo "None found."
                read -rp "Enter backup folder name (e.g. 20261116_183000): " B_FOLDER
                B_PATH="$WORKDIR/backups/$B_FOLDER"
                if [ -d "$B_PATH" ]; then
                    echo -e "${YELLOW}[*] Boot phone into BROM mode now (Vol+ & Vol- + USB)...${NC}"
                    "$VENV_DIR/bin/python" "$MTK_DIR/mtk.py" w nvdata,nvcfg,nvram,persist,protect1,protect2 \
                        "$B_PATH/nvdata.bin","$B_PATH/nvcfg.bin","$B_PATH/nvram.bin","$B_PATH/persist.bin","$B_PATH/protect1.bin","$B_PATH/protect2.bin"
                    echo -e "${GREEN}[+] NV/IMEI partitions restored!${NC}"
                else
                    echo -e "${RED}[!] Backup folder not found.${NC}"
                fi
                ;;
            12) restore_unjrc_file ;;
            13)
                echo -e "${RED}WARNING: Relocking on custom ROMs, root, or disabled dm-verity WILL hard-brick your phone!${NC}"
                read -rp "Type RELOCK to confirm: " CONFIRM_RELOCK
                if [ "$CONFIRM_RELOCK" == "RELOCK" ]; then
                    echo -e "${YELLOW}[*] Boot phone into BROM mode now (Vol+ & Vol- + USB)...${NC}"
                    "$VENV_DIR/bin/python" "$MTK_DIR/mtk.py" da seccfg lock
                    echo -e "${GREEN}[+] Bootloader relocked.${NC}"
                fi
                ;;
            14)
                echo -e "${GREEN}Done! Exiting UnJailer. Star and share the repo!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[!] Invalid selection. Choose 1-14.${NC}"
                ;;
        esac
    done
}

# Execution Flow
install_dependencies
startup_menu
select_os_version
select_device
post_unjail_menu