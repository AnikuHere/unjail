#!/usr/bin/env python3
"""
UnJailer - Cross-Platform MTK Xiaomi Tool (Windows & Linux)
Author: DeniusGG
"""

import os
import sys
import re
import time
import shutil
import zipfile
import tarfile
import hashlib
import platform
import subprocess
import urllib.request
from pathlib import Path
from datetime import datetime

# ANSI Colors (Enable VT100 on Windows 10/11)
if os.name == "nt":
    os.system("")

GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
ORANGE = "\033[0;33m"
RED = "\033[0;31m"
CYAN = "\033[0;36m"
MAGENTA = "\033[0;35m"
NC = "\033[0m"

IS_WINDOWS = platform.system().lower() == "windows"
IS_LINUX = platform.system().lower() == "linux"

WORKDIR = Path.home() / ".unjailer"
VENV_DIR = WORKDIR / "venv"
MTK_DIR = WORKDIR / "mtkclient"
TOOLS_DIR = WORKDIR / "platform-tools"
UNJRC_DIR = WORKDIR / "unjrc_backups"
LOG_FILE = WORKDIR / "unjailer.log"

WORKDIR.mkdir(parents=True, exist_ok=True)
UNJRC_DIR.mkdir(parents=True, exist_ok=True)


class TeeLogger:
    def __init__(self, log_path):
        self.terminal = sys.stdout
        self.log = open(log_path, "a", encoding="utf-8", errors="replace")

    def write(self, message):
        self.terminal.write(message)
        clean = re.sub(r"\033\[[0-9;]*m", "", message)
        self.log.write(clean)
        self.log.flush()

    def flush(self):
        self.terminal.flush()
        self.log.flush()


sys.stdout = TeeLogger(LOG_FILE)
sys.stderr = sys.stdout


def get_venv_python() -> str:
    if IS_WINDOWS:
        py = VENV_DIR / "Scripts" / "python.exe"
    else:
        py = VENV_DIR / "bin" / "python"
    return str(py) if py.exists() else sys.executable


def get_venv_pip() -> str:
    if IS_WINDOWS:
        pip = VENV_DIR / "Scripts" / "pip.exe"
    else:
        pip = VENV_DIR / "bin" / "pip"
    return str(pip)


def get_tool_cmd(tool_name: str) -> str:
    """Resolve adb or fastboot from PATH or local ~/.unjailer/platform-tools."""
    exe = f"{tool_name}.exe" if IS_WINDOWS else tool_name
    local_bin = TOOLS_DIR / exe
    if local_bin.exists():
        return str(local_bin)
    sys_bin = shutil.which(exe)
    return sys_bin if sys_bin else exe


def run_cmd(cmd, capture=True, check=False):
    try:
        res = subprocess.run(
            cmd,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.STDOUT if capture else None,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if check and res.returncode != 0:
            raise subprocess.CalledProcessError(res.returncode, cmd, res.stdout)
        return res
    except FileNotFoundError:
        return subprocess.CompletedProcess(cmd, 127, stdout="Command not found")


def download_and_extract_zip(url: str, dest_dir: Path, strip_top_dir: bool = False):
    tmp_zip = WORKDIR / "temp_download.zip"
    print(f"{YELLOW}[*] Downloading {url}...{NC}")
    urllib.request.urlretrieve(url, tmp_zip)
    with zipfile.ZipFile(tmp_zip, "r") as zf:
        if not strip_top_dir:
            zf.extractall(dest_dir)
        else:
            top_prefix = zf.namelist()[0].split("/")[0] + "/"
            for member in zf.infolist():
                if member.filename.startswith(top_prefix):
                    rel_path = member.filename[len(top_prefix):]
                    if not rel_path:
                        continue
                    target = dest_dir / rel_path
                    if member.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with zf.open(member) as src, open(target, "wb") as dst:
                            shutil.copyfileobj(src, dst)
    tmp_zip.unlink(missing_ok=True)


def install_dependencies():
    print(f"{CYAN}========================================={NC}")
    print(f"{CYAN}  UnJailer - MTK Xiaomi Tool by DeniusGG {NC}")
    print(f"{CYAN}  Platform: {platform.system()} ({platform.machine()}){NC}")
    print(f"{CYAN}========================================={NC}")
    print(f"{YELLOW}[*] Checking and installing dependencies...{NC}")

    if IS_LINUX:
        pkgs = ["python3-venv", "python3-pip", "git", "libusb-1.0-0", "adb", "fastboot", "usbutils", "python3-tk"]
        missing = [p for p in pkgs if run_cmd(["dpkg", "-s", p]).returncode != 0]
        if missing:
            print(f"{YELLOW}[*] Installing missing Linux packages: {' '.join(missing)}{NC}")
            run_cmd(["sudo", "apt-get", "update"], capture=False)
            run_cmd(["sudo", "apt-get", "install", "-y"] + missing, capture=False)

        udev_file = Path("/etc/udev/rules.d/51-mtk-unjailer.rules")
        if not udev_file.exists():
            print(f"{YELLOW}[*] Configuring MediaTek & Xiaomi udev rules...{NC}")
            rules = (
                'SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", MODE="0666", GROUP="plugdev"\n'
                'SUBSYSTEM=="usb", ATTR{idVendor}=="2717", MODE="0666", GROUP="plugdev"\n'
                'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="plugdev"\n'
            )
            subprocess.run(["sudo", "tee", str(udev_file)], input=rules, text=True, stdout=subprocess.DEVNULL)
            run_cmd(["sudo", "udevadm", "control", "--reload-rules"])
            run_cmd(["sudo", "udevadm", "trigger"])

    elif IS_WINDOWS:
        # Auto-download official Google SDK Platform-Tools if adb/fastboot are missing
        if not shutil.which("adb.exe") and not (TOOLS_DIR / "adb.exe").exists():
            print(f"{YELLOW}[*] ADB/Fastboot not found in PATH. Downloading Google Platform-Tools for Windows...{NC}")
            download_and_extract_zip(
                "https://dl.google.com/android/repository/platform-tools-latest-windows.zip",
                WORKDIR,
                strip_top_dir=False,
            )
            print(f"{GREEN}[+] Installed Platform-Tools to {TOOLS_DIR}{NC}")

    # Fetch mtkclient (uses git if available, otherwise downloads GitHub ZIP cleanly on Windows/Linux)
    if not MTK_DIR.exists():
        print(f"{YELLOW}[*] Downloading mtkclient...{NC}")
        if shutil.which("git"):
            res = run_cmd(["git", "clone", "https://github.com/bkerler/mtkclient.git", str(MTK_DIR)], capture=False)
            if res.returncode != 0:
                download_and_extract_zip(
                    "https://github.com/bkerler/mtkclient/archive/refs/heads/main.zip",
                    MTK_DIR,
                    strip_top_dir=True,
                )
        else:
            download_and_extract_zip(
                "https://github.com/bkerler/mtkclient/archive/refs/heads/main.zip",
                MTK_DIR,
                strip_top_dir=True,
            )

    # Setup Python Virtual Environment + cryptography for .unjrc
    if not VENV_DIR.exists():
        print(f"{YELLOW}[*] Creating Python virtual environment and installing mtkclient...{NC}")
        run_cmd([sys.executable, "-m", "venv", str(VENV_DIR)], capture=False, check=True)
        pip_bin = get_venv_pip()
        run_cmd([pip_bin, "install", "--upgrade", "pip", "wheel", "setuptools"], capture=False)
        run_cmd([pip_bin, "install", "cryptography"], capture=False)
        req_file = MTK_DIR / "requirements.txt"
        if req_file.exists():
            run_cmd([pip_bin, "install", "-r", str(req_file)], capture=False)
        run_cmd([pip_bin, "install", str(MTK_DIR)], capture=False)
    else:
        print(f"{GREEN}[+] Python environment and mtkclient ready.{NC}")

    if IS_WINDOWS:
        print(f"{YELLOW}[TIP] On Windows 11, ensure USBDK and MediaTek VCOM drivers are installed for BROM mode.{NC}")


# ==============================================================================
# PURE PYTHON AES-256-CBC HELPERS (Replaces OpenSSL CLI for Cross-Platform .unjrc)
# ==============================================================================

def _derive_key_iv(password: str, salt: bytes):
    dk = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, 100000, dklen=48)
    return dk[:32], dk[32:48]


def encrypt_bytes_openssl_compat(raw_data: bytes, password: str) -> bytes:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives import padding

    salt = os.urandom(8)
    key, iv = _derive_key_iv(password, salt)
    padder = padding.PKCS7(128).padder()
    padded = padder.update(raw_data) + padder.finalize()
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    encryptor = cipher.encryptor()
    ct = encryptor.update(padded) + encryptor.finalize()
    return b"Salted__" + salt + ct


def decrypt_bytes_openssl_compat(enc_data: bytes, password: str) -> bytes:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives import padding

    if not enc_data.startswith(b"Salted__") or len(enc_data) < 16:
        raise ValueError("Invalid encrypted header")
    salt = enc_data[8:16]
    ct = enc_data[16:]
    key, iv = _derive_key_iv(password, salt)
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
    decryptor = cipher.decryptor()
    padded = decryptor.update(ct) + decryptor.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    return unpadder.update(padded) + unpadder.finalize()


# ==============================================================================
# .UNJRC DATA RECOVERY MODULE
# ==============================================================================

def show_unjrc_help():
    print(f"\n{CYAN}====================================================={NC}")
    print(f"{CYAN}               .unjrc Data Recovery Guide            {NC}")
    print(f"{CYAN}====================================================={NC}")
    print(f"\n{YELLOW}- What is .unjrc data recovery file?{NC}")
    print("  A custom encrypted backup file for UnJailer. It scans device metadata and pulls user media locally.")
    print(f"\n{YELLOW}- Cross-Platform Compatibility:{NC}")
    print("  Uses OpenSSL-compatible PBKDF2 + AES-256-CBC inside Python so .unjrc files created on Windows work on Linux and vice versa.")
    print(f"{CYAN}====================================================={NC}")
    input("Press [Enter] to return...")


def get_adb_devices():
    adb = get_tool_cmd("adb")
    res = run_cmd([adb, "devices"])
    devs = []
    for line in res.stdout.splitlines()[1:]:
        parts = line.strip().split()
        if len(parts) >= 2 and parts[1] == "device":
            devs.append(parts[0])
    return devs


def get_fastboot_devices():
    fb = get_tool_cmd("fastboot")
    res = run_cmd([fb, "devices"])
    devs = []
    for line in res.stdout.splitlines():
        parts = line.strip().split()
        if len(parts) >= 2:
            devs.append(parts[0])
    return devs


def create_unjrc_file():
    import getpass

    adb = get_tool_cmd("adb")
    print(f"\n{CYAN}=== Create a .unjrc Data Recovery File ==={NC}")
    print(f"{YELLOW}[*] Make sure your phone is booted into Android with USB Debugging enabled.{NC}")
    print(f"{YELLOW}[*] Waiting for ADB device connection...{NC}")

    while not get_adb_devices():
        time.sleep(1)

    serial = get_adb_devices()[0]
    codename = run_cmd([adb, "-s", serial, "shell", "getprop", "ro.product.device"]).stdout.strip()
    model = run_cmd([adb, "-s", serial, "shell", "getprop", "ro.product.model"]).stdout.strip()
    android_id = run_cmd([adb, "-s", serial, "shell", "settings", "get", "secure", "android_id"]).stdout.strip()

    print(f"{GREEN}[+] Connected: {model} ({codename}) [Serial: {serial}]{NC}")

    verify_hash = hashlib.sha256(f"{serial}:{codename}:{android_id}".encode()).hexdigest()
    run_cmd([adb, "-s", serial, "shell", f"mkdir -p /sdcard/.unjailer_verify && echo '{verify_hash}' > /sdcard/.unjailer_verify/token.sig"])

    pw1 = getpass.getpass("Create an encryption password for this .unjrc file: ")
    pw2 = getpass.getpass("Confirm password: ")
    if not pw1 or pw1 != pw2:
        print(f"{RED}[!] Passwords do not match or cannot be empty.{NC}")
        return

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stage_dir = WORKDIR / f"tmp_unjrc_{ts}"
    files_dir = stage_dir / "files"
    meta_dir = stage_dir / "meta"
    files_dir.mkdir(parents=True, exist_ok=True)
    meta_dir.mkdir(parents=True, exist_ok=True)
    out_file = UNJRC_DIR / f"{codename}_{ts}.unjrc"

    print(f"{YELLOW}[*] Scanning device metadata locally...{NC}")
    accts = run_cmd([adb, "-s", serial, "shell", "dumpsys", "account"]).stdout
    (meta_dir / "accounts.txt").write_text("\n".join([l for l in accts.splitlines() if "Account {" in l]), encoding="utf-8")
    (meta_dir / "user_apps.txt").write_text(run_cmd([adb, "-s", serial, "shell", "pm", "list", "packages", "-3"]).stdout, encoding="utf-8")
    (meta_dir / "device_props.txt").write_text(run_cmd([adb, "-s", serial, "shell", "getprop"]).stdout, encoding="utf-8")
    (meta_dir / "apply_map.txt").write_text(
        "DCIM|/sdcard/DCIM\nPictures|/sdcard/Pictures\nMovies|/sdcard/Movies\nDownload|/sdcard/Download\nDocuments|/sdcard/Documents\n",
        encoding="utf-8",
    )

    for folder in ["DCIM", "Pictures", "Movies", "Download", "Documents"]:
        chk = run_cmd([adb, "-s", serial, "shell", f"[ -d /sdcard/{folder} ] && echo YES"]).stdout.strip()
        if chk == "YES":
            print(f"    -> Pulling /sdcard/{folder}...")
            run_cmd([adb, "-s", serial, "pull", f"/sdcard/{folder}", str(files_dir)])

    tar_path = stage_dir / "payload.tar.gz"
    with tarfile.open(tar_path, "w:gz") as tar:
        tar.add(files_dir, arcname="files")
        tar.add(meta_dir, arcname="meta")

    enc_bytes = encrypt_bytes_openssl_compat(tar_path.read_bytes(), f"{pw1}:{verify_hash}")
    header = (
        f"UNJRC_V1\n"
        f"CREATED={ts}\n"
        f"DEVICE={codename}\n"
        f"VERIFY_SIG={verify_hash}\n"
        f"---PAYLOAD---\n"
    ).encode("utf-8")
    out_file.write_bytes(header + enc_bytes)
    shutil.rmtree(stage_dir, ignore_errors=True)

    print(f"{GREEN}[+] .unjrc Data Recovery File saved to: {CYAN}{out_file}{NC}")
    input("Press [Enter] to continue...")


def restore_unjrc_file():
    import getpass

    adb = get_tool_cmd("adb")
    print(f"\n{CYAN}=== Restore from .unjrc Data Recovery File ==={NC}")
    unjrc_files = sorted(UNJRC_DIR.glob("*.unjrc"))
    if not unjrc_files:
        print(f"{RED}[!] No .unjrc files found in {UNJRC_DIR}{NC}")
        return
    for f in unjrc_files:
        print(f"  - {f}")

    in_path = Path(input("Enter full path to .unjrc file: ").strip().strip('"').strip("'"))
    if not in_path.exists():
        print(f"{RED}[!] File not found.{NC}")
        return

    print(f"{YELLOW}[*] Connect your phone via ADB (with USB Debugging enabled)...{NC}")
    while not get_adb_devices():
        time.sleep(1)
    serial = get_adb_devices()[0]

    raw = in_path.read_bytes()
    marker = b"---PAYLOAD---\n"
    if marker not in raw:
        marker = b"---PAYLOAD---\r\n"
    hdr_bytes, payload_enc = raw.split(marker, 1)
    hdr_lines = hdr_bytes.decode("utf-8", errors="replace").splitlines()
    expected_sig = next((l.split("=", 1)[1] for l in hdr_lines if l.startswith("VERIFY_SIG=")), "")

    phone_sig = run_cmd([adb, "-s", serial, "shell", "cat /sdcard/.unjailer_verify/token.sig 2>/dev/null"]).stdout.strip()
    if not phone_sig:
        codename = run_cmd([adb, "-s", serial, "shell", "getprop", "ro.product.device"]).stdout.strip()
        android_id = run_cmd([adb, "-s", serial, "shell", "settings", "get", "secure", "android_id"]).stdout.strip()
        phone_sig = hashlib.sha256(f"{serial}:{codename}:{android_id}".encode()).hexdigest()

    if expected_sig != phone_sig:
        print(f"{RED}[!] Verification lock mismatch! Device signature does not match .unjrc file.{NC}")
        return

    dec_pass = getpass.getpass("Enter .unjrc decryption password: ")
    try:
        tar_bytes = decrypt_bytes_openssl_compat(payload_enc, f"{dec_pass}:{expected_sig}")
    except Exception:
        print(f"{RED}[!] Decryption failed. Incorrect password or corrupted .unjrc file.{NC}")
        return

    restore_stage = WORKDIR / f"tmp_restore_{int(time.time())}"
    restore_stage.mkdir(parents=True, exist_ok=True)
    tar_path = restore_stage / "payload.tar.gz"
    tar_path.write_bytes(tar_bytes)
    with tarfile.open(tar_path, "r:gz") as tar:
        tar.extractall(restore_stage)

    apply_map = restore_stage / "meta" / "apply_map.txt"
    if apply_map.exists():
        for line in apply_map.read_text(encoding="utf-8").splitlines():
            if "|" in line:
                src_name, dest_path = line.split("|", 1)
                src_dir = restore_stage / "files" / src_name
                if src_dir.exists():
                    print(f"    -> Restoring {src_name} to {dest_path}...")
                    run_cmd([adb, "-s", serial, "push", f"{src_dir}/.", f"{dest_path}/"])

    last_meta = UNJRC_DIR / "last_meta"
    last_meta.mkdir(parents=True, exist_ok=True)
    for mfile in (restore_stage / "meta").glob("*"):
        shutil.copy2(mfile, last_meta / mfile.name)
    shutil.rmtree(restore_stage, ignore_errors=True)
    print(f"{GREEN}[+] .unjrc recovery complete! Metadata saved in {last_meta}{NC}")


def startup_menu():
    while True:
        print(f"\n{CYAN}========================================={NC}")
        print(f"{CYAN}         UnJailer Startup Menu           {NC}")
        print(f"{CYAN}========================================={NC}")
        print("1) Create a .unjrc data recovery file (Requires booted Android + ADB)")
        print("2) See help for .unjrc")
        print("3) Continue to UnJailer (Select OS & Device)")
        print("4) Exit")
        opt = input("Select an option [1-4]: ").strip()
        if opt == "1":
            create_unjrc_file()
        elif opt == "2":
            show_unjrc_help()
        elif opt == "3":
            break
        elif opt == "4":
            sys.exit(0)
        else:
            print(f"{RED}[!] Invalid option. Please enter 1-4.{NC}")


# ==============================================================================
# DEVICE & OS SELECTION
# ==============================================================================

DEVICE_MAP = {
    "selene": "Redmi 10 / 10 Prime (selene - Helio G88)",
    "eos": "Redmi 10 / 10 Prime (selene - Helio G88)",
    "merlin": "Redmi Note 9 / Redmi 10X 4G (merlin - Helio G85)",
    "merlinnfc": "Redmi Note 9 / Redmi 10X 4G (merlin - Helio G85)",
    "lancelot": "Redmi 9 / POCO M2 (lancelot - Helio G80)",
    "dandelion": "Redmi 9A / 9i / 10A (dandelion - Helio G25)",
    "angelica": "Redmi 9C / POCO C3 (angelica - Helio G35)",
    "cattail": "Redmi 9C / POCO C3 (angelica - Helio G35)",
    "camellia": "Redmi Note 10 5G / POCO M3 Pro 5G (camellia - Dimensity 700)",
    "camellian": "Redmi Note 10 5G / POCO M3 Pro 5G (camellia - Dimensity 700)",
    "rosemary": "Redmi Note 10S / POCO M5s (rosemary - Helio G95)",
    "maltose": "Redmi Note 10S / POCO M5s (rosemary - Helio G95)",
    "secret": "Redmi Note 10S / POCO M5s (rosemary - Helio G95)",
    "fleur": "Redmi Note 11S / POCO M4 Pro 4G (fleur - Helio G96)",
    "miel": "Redmi Note 11S / POCO M4 Pro 4G (fleur - Helio G96)",
    "evergreen": "POCO M4 Pro 5G / Redmi Note 11 5G (evergreen - Dimensity 810)",
    "evergo": "POCO M4 Pro 5G / Redmi Note 11 5G (evergreen - Dimensity 810)",
    "begonia": "Redmi Note 8 Pro (begonia - Helio G90T)",
    "begoniain": "Redmi Note 8 Pro (begonia - Helio G90T)",
    "atom": "Redmi 10X 5G / 10X Pro (atom/bomb - Dimensity 820)",
    "bomb": "Redmi 10X 5G / 10X Pro (atom/bomb - Dimensity 820)",
    "cezanne": "Redmi K30 Ultra (cezanne - Dimensity 1000+)",
    "ares": "Redmi K40 Gaming / POCO F3 GT (ares - Dimensity 1200)",
    "aresin": "Redmi K40 Gaming / POCO F3 GT (ares - Dimensity 1200)",
    "chopin": "Redmi Note 10 Pro CN / POCO X3 GT (chopin - Dimensity 1100)",
}


def map_device_name(codename: str) -> str:
    return DEVICE_MAP.get(codename.lower(), f"Xiaomi MediaTek Device ({codename})")


def select_os_version() -> str:
    print(f"\n{ORANGE}Please select your OS version group (MIUI / HyperOS - Global & CN):{NC}")
    print("1) Legacy MIUI (MIUI 11 / 12 / 13 / Early 14.0.1-14.0.2) [Global & CN]")
    print("2) Modern MIUI & HyperOS (MIUI 14.0.3+ / HyperOS 1 / 2 / 3) [Global & CN]")
    choice = input("Enter OS version choice [1-2]: ").strip()
    if choice == "1":
        print(f"{GREEN}[+] OS Profile: MIUI 11-13 (Legacy seccfg){NC}")
        return "legacy"
    elif choice == "2":
        print(f"{GREEN}[+] OS Profile: MIUI 14+ / HyperOS 1-3 (RPMB + seccfg){NC}")
        return "hyperos"
    else:
        print(f"{RED}[!] Invalid OS selection.{NC}")
        sys.exit(1)


def scan_usb_mtk():
    found = []
    if IS_LINUX:
        res = run_cmd(["lsusb"])
        for line in res.stdout.splitlines():
            if "0e8d:" in line or "2717:" in line:
                found.append(line.strip())
    elif IS_WINDOWS:
        ps = run_cmd([
            "powershell", "-NoProfile", "-Command",
            "Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match 'VID_0E8D|VID_2717|VID_18D1' } | Select-Object -ExpandProperty FriendlyName"
        ])
        for line in ps.stdout.splitlines():
            if line.strip():
                found.append(line.strip())
    return found


def select_device() -> str:
    adb = get_tool_cmd("adb")
    fb = get_tool_cmd("fastboot")
    print(f"\n{CYAN}Scanning for connected phones (ADB / Fastboot / MediaTek USB)...{NC}")

    targets = []
    labels = []

    for serial in get_adb_devices():
        codename = run_cmd([adb, "-s", serial, "shell", "getprop", "ro.product.device"]).stdout.strip()
        region = run_cmd([adb, "-s", serial, "shell", "getprop", "ro.miui.region"]).stdout.strip() or "Unknown"
        targets.append(f"ADB:{serial}")
        labels.append(f"{map_device_name(codename)} [ADB: {serial} | Region: {region}]")

    for fb_serial in get_fastboot_devices():
        out = run_cmd([fb, "-s", fb_serial, "getvar", "product"]).stdout
        m = re.search(r"product:\s*(\S+)", out)
        prod = m.group(1) if m else "unknown"
        targets.append(f"FASTBOOT:{fb_serial}")
        labels.append(f"{map_device_name(prod)} [Fastboot: {fb_serial}]")

    for usb_desc in scan_usb_mtk():
        targets.append("USB_DETECTED")
        labels.append(f"USB Device: {usb_desc}")

    targets.append("MANUAL_BROM")
    labels.append("Wait for Phone in BROM Mode (Redmi 10 selene / Any Supported MTK)")

    print(f"\n{CYAN}Select target device:{NC}")
    for idx, lbl in enumerate(labels, 1):
        print(f"{idx}) {lbl}")

    raw_choice = input(f"Enter choice [1-{len(labels)}]: ").strip()
    if not raw_choice.isdigit() or not (1 <= int(raw_choice) <= len(labels)):
        print(f"{RED}[!] Invalid selection.{NC}")
        sys.exit(1)

    idx = int(raw_choice) - 1
    print(f"{GREEN}[+] Selected: {labels[idx]}{NC}")
    return targets[idx]


# ==============================================================================
# CORE UNJAIL & POST-UNJAIL MODULES
# ==============================================================================

def run_unjail(mode: str, selected_target: str):
    print(f"\n{RED}WARNING: Unlocking the bootloader will wipe user data. Continue at your own risk.{NC}")

    if selected_target.startswith("ADB:"):
        serial = selected_target.split(":", 1)[1]
        print(f"{YELLOW}[*] Sending shutdown command to ADB device ({serial})...{NC}")
        run_cmd([get_tool_cmd("adb"), "-s", serial, "shell", "reboot", "-p"])
        time.sleep(3)

    restore_mm = False
    if IS_LINUX:
        if run_cmd(["systemctl", "is-active", "--quiet", "ModemManager"]).returncode == 0:
            print(f"{YELLOW}[*] Temporarily stopping ModemManager to prevent USB port conflicts...{NC}")
            run_cmd(["sudo", "systemctl", "stop", "ModemManager"])
            restore_mm = True

    print(f"{YELLOW}[*] Put your phone into BROM mode now:{NC}")
    print("    1. Ensure the phone is completely powered OFF (or hold Power + Vol+ + Vol- from Fastboot, releasing Power the instant the screen turns black).")
    print("    2. Keep holding BOTH Volume Up + Volume Down buttons.")
    print("    3. Plug the USB data cable into the PC.\n")

    backup_dir = WORKDIR / "backups" / datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir.mkdir(parents=True, exist_ok=True)
    mtk_cmd = [get_venv_python(), str(MTK_DIR / "mtk.py")]

    try:
        print(f"{YELLOW}[*] Step 1/4: Backing up NV/IMEI & security partitions to {backup_dir}...{NC}")
        parts = "nvdata,nvcfg,nvram,persist,protect1,protect2,seccfg"
        files = ",".join(str(backup_dir / f"{p}.bin") for p in parts.split(","))
        run_cmd(mtk_cmd + ["r", parts, files], capture=False)

        if mode == "hyperos":
            print(f"{YELLOW}[*] Step 2/4: Dumping RPMB to locate HyperOS/CN lock magic...{NC}")
            rpmb_file = backup_dir / "rpmb_backup.bin"
            run_cmd(mtk_cmd + ["da", "rpmb", "r", str(rpmb_file)], capture=False)
            if rpmb_file.exists():
                rpmb_data = rpmb_file.read_bytes()
                offset = rpmb_data.find(b"Jz8PNRUF")
                if offset != -1:
                    sector = offset // 256
                    print(f"{GREEN}[+] Found HyperOS/MIUI14+ RPMB lock magic at byte {offset} (Sector {sector}).{NC}")
                    print(f"{YELLOW}[*] Step 3/4: Clearing 4 RPMB sectors starting at sector {sector}...{NC}")
                    run_cmd(mtk_cmd + ["da", "rpmb", "e", "--sector", str(sector), "--sectors", "4"], capture=False)
                else:
                    print(f"{YELLOW}[!] RPMB lock magic not present. Skipping RPMB erase.{NC}")
        else:
            print(f"{YELLOW}[*] Step 2/4 & 3/4: Skipping RPMB erase (Legacy MIUI selected)...{NC}")

        print(f"{YELLOW}[*] Step 4/4: Writing unlock flag to seccfg...{NC}")
        run_cmd(mtk_cmd + ["da", "seccfg", "unlock"], capture=False)
    finally:
        if restore_mm:
            run_cmd(["sudo", "systemctl", "start", "ModemManager"])

    print(f"\n{GREEN}========================================={NC}")
    print(f"{GREEN}      Successfully unjailed, enjoy.      {NC}")
    print(f"{GREEN}========================================={NC}")
    print(f"IMEI/NV backups stored at: {CYAN}{backup_dir}{NC}")
    print("Unplug your device and hold Power for ~10 seconds to reboot.")


def wait_for_fastboot():
    print(f"{YELLOW}[*] Waiting for Fastboot device...{NC}")
    while not get_fastboot_devices():
        time.sleep(1)
    print(f"{GREEN}[+] Fastboot device connected: {get_fastboot_devices()[0]}{NC}")


def fastboot_flash_vbmeta(partition: str, img_path: Path):
    fb = get_tool_cmd("fastboot")
    res = run_cmd([fb, "--disable-verity", "--disable-verification", "flash", partition, str(img_path)])
    if "unknown option" in res.stdout.lower():
        # Fallback for older fastboot binaries (flag 0x03 is already embedded in generated vbmeta)
        res = run_cmd([fb, "flash", partition, str(img_path)])
    print(res.stdout.strip())


def dm_verity_fix():
    fb = get_tool_cmd("fastboot")
    print(f"\n{CYAN}=== Dm-Verity & AVB Corruption Fix ==={NC}")
    input("Boot into FASTBOOT (Vol Down + Power), connect USB, and press [Enter]...")
    wait_for_fastboot()

    patched_vb = WORKDIR / "vbmeta_disabled.img"
    buf = bytearray(4096)
    buf[0:4] = b"AVB0"
    buf[7] = 2
    buf[123] = 3
    patched_vb.write_bytes(buf)

    use_stock = input("Do you have a stock vbmeta.img to flash instead? (y/N): ").strip().lower()
    target_vb = patched_vb
    if use_stock == "y":
        p = Path(input("Enter full path to stock vbmeta.img: ").strip().strip('"').strip("'"))
        if p.exists():
            target_vb = p
        else:
            print(f"{RED}[!] File not found, using generated AVB2 disabled vbmeta.{NC}")

    slot_out = run_cmd([fb, "getvar", "current-slot"]).stdout
    m = re.search(r"current-slot:\s*([ab])", slot_out)
    if m:
        print(f"{YELLOW}[*] A/B device detected (active slot: {m.group(1)}). Flashing both slots...{NC}")
        for part in ["vbmeta_a", "vbmeta_b", "vbmeta_system_a", "vbmeta_system_b"]:
            fastboot_flash_vbmeta(part, target_vb)
    else:
        print(f"{YELLOW}[*] Single-slot device detected. Flashing vbmeta...{NC}")
        fastboot_flash_vbmeta("vbmeta", target_vb)

    if input("Erase /metadata to clear old encryption state? [y/N]: ").strip().lower() == "y":
        run_cmd([fb, "erase", "metadata"], capture=False)

    print(f"{GREEN}[+] Dm-Verity disabled! Rebooting device...{NC}")
    run_cmd([fb, "reboot"], capture=False)


def flasher_tui():
    fb = get_tool_cmd("fastboot")
    print(f"\n{CYAN}=== UnJailer Flasher TUI ==={NC}")
    img_path = Path(input("Enter full path to .img / .bin file: ").strip().strip('"').strip("'"))
    if not img_path.exists():
        print(f"{RED}[!] File does not exist: {img_path}{NC}")
        return

    print("1) boot   2) recovery   3) vbmeta   4) GSI (FastbootD)   5) super   6) Custom partition")
    choice = input("Choice [1-6]: ").strip()
    wait_for_fastboot()

    if choice == "1":
        run_cmd([fb, "flash", "boot", str(img_path)], capture=False)
    elif choice == "2":
        run_cmd([fb, "flash", "recovery", str(img_path)], capture=False)
    elif choice == "3":
        fastboot_flash_vbmeta("vbmeta", img_path)
    elif choice == "4":
        run_cmd([fb, "reboot", "fastboot"], capture=False)
        time.sleep(5)
        wait_for_fastboot()
        run_cmd([fb, "delete-logical-partition", "product_a"])
        run_cmd([fb, "delete-logical-partition", "product_b"])
        run_cmd([fb, "flash", "system", str(img_path)], capture=False)
        run_cmd([fb, "-w"], capture=False)
    elif choice == "5":
        run_cmd([fb, "flash", "super", str(img_path)], capture=False)
    elif choice == "6":
        part = input("Enter exact partition name: ").strip()
        run_cmd([fb, "flash", part, str(img_path)], capture=False)
    else:
        print(f"{RED}[!] Invalid option.{NC}")
        return

    if input("Reboot device now? (y/N): ").strip().lower() == "y":
        run_cmd([fb, "reboot"], capture=False)


def flasher_gui(agui_mode: bool = False):
    try:
        import tkinter as tk
        from tkinter import filedialog, messagebox, simpledialog
    except ImportError:
        print(f"{RED}[!] Tkinter GUI library not available. Use Flasher TUI instead.{NC}")
        return

    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)

    fb = get_tool_cmd("fastboot")
    mtk_cmd = [get_venv_python(), str(MTK_DIR / "mtk.py")]

    if not agui_mode:
        img = filedialog.askopenfilename(title="Select Image (.img / .bin)", filetypes=[("Android Images", "*.img *.bin"), ("All Files", "*.*")])
        if not img:
            root.destroy()
            return
        part = simpledialog.askstring("Target Partition", "Enter partition (boot, recovery, vbmeta, system, super, dtbo):")
        if not part:
            root.destroy()
            return
        if messagebox.askyesno("Confirm Flash", f"Flash {Path(img).name} to [{part}]?"):
            wait_for_fastboot()
            if part == "vbmeta":
                fastboot_flash_vbmeta("vbmeta", Path(img))
            else:
                run_cmd([fb, "flash", part, img], capture=False)
            messagebox.showinfo("UnJailer GUI", f"Successfully flashed {part}!")
        root.destroy()
        return

    # Cross-Platform AGUI Window
    win = tk.Toplevel(root)
    win.title("UnJailer AGUI - Cross-Platform Control Suite")
    win.geometry("520x380")

    tk.Label(win, text="Select an Advanced Flashing or Partition Operation:", font=("Segoe UI", 10, "bold")).pack(pady=10)

    def do_fb_flash():
        img = filedialog.askopenfilename(title="Select Image")
        if img:
            part = simpledialog.askstring("Partition", "Target partition (boot, recovery, dtbo, vbmeta):")
            if part:
                wait_for_fastboot()
                if part == "vbmeta":
                    fastboot_flash_vbmeta("vbmeta", Path(img))
                else:
                    run_cmd([fb, "flash", part, img], capture=False)
                messagebox.showinfo("AGUI", f"Flashed {part}!")

    def do_gsi():
        img = filedialog.askopenfilename(title="Select GSI System Image", filetypes=[("IMG", "*.img")])
        if img and messagebox.askyesno("GSI Warning", "Reboot FastbootD, delete product_a/b, flash GSI, and wipe userdata?"):
            wait_for_fastboot()
            run_cmd([fb, "reboot", "fastboot"], capture=False)
            time.sleep(5)
            wait_for_fastboot()
            run_cmd([fb, "delete-logical-partition", "product_a"])
            run_cmd([fb, "delete-logical-partition", "product_b"])
            run_cmd([fb, "flash", "system", img], capture=False)
            run_cmd([fb, "-w"], capture=False)
            messagebox.showinfo("AGUI", "GSI Installation Complete!")

    def do_brom_write():
        img = filedialog.askopenfilename(title="Select Raw Image for BROM Write")
        if img:
            part = simpledialog.askstring("BROM Partition", "Target partition (lk, boot, recovery, vbmeta):")
            if part:
                messagebox.showinfo("Enter BROM", "Power off phone completely, hold Vol+ & Vol-, and plug in USB now. Click OK.")
                run_cmd(mtk_cmd + ["w", part, img], capture=False)
                messagebox.showinfo("AGUI", f"BROM write to {part} finished!")

    def do_brom_dump():
        part = simpledialog.askstring("BROM Dump", "Partition to dump (boot, lk, vbmeta, seccfg):")
        if part:
            out_dump = WORKDIR / "backups" / f"{part}_{int(time.time())}.bin"
            out_dump.parent.mkdir(parents=True, exist_ok=True)
            messagebox.showinfo("Enter BROM", "Power off phone completely, hold Vol+ & Vol-, and plug in USB now. Click OK.")
            run_cmd(mtk_cmd + ["r", part, str(out_dump)], capture=False)
            messagebox.showinfo("AGUI", f"Saved dump to:\n{out_dump}")

    def do_slot():
        slot = simpledialog.askstring("Slot Switcher", "Enter target slot (a or b):")
        if slot in ("a", "b"):
            wait_for_fastboot()
            run_cmd([fb, f"--set-active={slot}"], capture=False)
            messagebox.showinfo("AGUI", f"Active slot set to {slot}")

    def do_reboot():
        mode = simpledialog.askstring("Reboot", "Target (system, recovery, bootloader, fastboot):")
        if mode:
            wait_for_fastboot()
            run_cmd([fb, "reboot"] if mode == "system" else [fb, "reboot", mode], capture=False)

    buttons = [
        ("1. Standard Fastboot Flash", do_fb_flash),
        ("2. GSI / Treble Full Installer (FastbootD)", do_gsi),
        ("3. BROM Raw Partition Write (MTKClient)", do_brom_write),
        ("4. BROM Partition Backup (MTKClient)", do_brom_dump),
        ("5. A/B Slot Switcher", do_slot),
        ("6. Reboot Controller", do_reboot),
        ("7. Close AGUI", win.destroy),
    ]
    for text, cmd in buttons:
        tk.Button(win, text=text, width=45, command=cmd).pack(pady=4)

    win.wait_window()
    root.destroy()


def check_status():
    adb = get_tool_cmd("adb")
    fb = get_tool_cmd("fastboot")
    print(f"\n{CYAN}=== Checking Bootloader & Security Status ==={NC}")
    if get_fastboot_devices():
        for var in ["unlocked", "secure", "current-slot", "anti"]:
            out = run_cmd([fb, "getvar", var]).stdout
            for line in out.splitlines():
                if f"{var}:" in line:
                    print(line.strip())
    elif get_adb_devices():
        for label, prop in [
            ("Bootloader Locked", "ro.boot.flash.locked"),
            ("Verified Boot", "ro.boot.verifiedbootstate"),
            ("Verity Mode", "ro.boot.veritymode"),
            ("Active Slot", "ro.boot.slot_suffix"),
        ]:
            val = run_cmd([adb, "shell", "getprop", prop]).stdout.strip()
            print(f"{label}: {val}")
    else:
        print(f"{YELLOW}[!] No phone detected in ADB or Fastboot.{NC}")


def check_device_info():
    adb = get_tool_cmd("adb")
    fb = get_tool_cmd("fastboot")
    print(f"\n{CYAN}=== Device Hardware & Firmware Info ==={NC}")
    if get_fastboot_devices():
        out = run_cmd([fb, "getvar", "all"]).stdout
        for line in out.splitlines():
            if any(k in line for k in ["product", "variant", "serialno", "version-bootloader", "max-download-size"]):
                print(line.strip())
    elif get_adb_devices():
        for label, prop in [
            ("Model", "ro.product.model"),
            ("Codename", "ro.product.device"),
            ("SoC", "ro.board.platform"),
            ("MIUI/HyperOS", "ro.miui.ui.version.name"),
            ("Android", "ro.build.version.release"),
            ("Region", "ro.miui.region"),
        ]:
            print(f"{label}: {run_cmd([adb, 'shell', 'getprop', prop]).stdout.strip()}")
    else:
        print(f"{YELLOW}[!] Connect device in ADB or Fastboot first.{NC}")


def run_diagnostics():
    print(f"\n{CYAN}=== UnJailer Cross-Platform Diagnostics ==={NC}")
    mtk_ok = run_cmd([get_venv_python(), str(MTK_DIR / "mtk.py"), "--help"]).returncode == 0
    print(f"1. Python Venv & MTKClient: {GREEN + 'PASS' + NC if mtk_ok else RED + 'FAIL' + NC}")

    adb_ok = run_cmd([get_tool_cmd("adb"), "version"]).returncode == 0
    fb_ok = run_cmd([get_tool_cmd("fastboot"), "--version"]).returncode == 0
    print(f"2. ADB & Fastboot:          {GREEN + 'PASS' + NC if (adb_ok and fb_ok) else RED + 'FAIL' + NC}")

    usb_devs = scan_usb_mtk()
    print(f"3. Detected MTK/Android USB: {usb_devs if usb_devs else 'None currently plugged in'}")
    backups = len(list((WORKDIR / "backups").glob("*"))) if (WORKDIR / "backups").exists() else 0
    unjrcs = len(list(UNJRC_DIR.glob("*.unjrc")))
    print(f"4. Saved NVRAM Backups:     {backups}")
    print(f"5. Saved .unjrc Files:      {unjrcs}")


def post_unjail_menu(mode: str, selected_target: str):
    fb = get_tool_cmd("fastboot")
    mtk_cmd = [get_venv_python(), str(MTK_DIR / "mtk.py")]

    while True:
        print(f"\n{MAGENTA}====================================================={NC}")
        print(f"{MAGENTA}      UnJailer Post-Unlock & Flashing Suite          {NC}")
        print(f"{MAGENTA}====================================================={NC}")
        print("1)  Unjail (Backup Critical Data & Unlock Bootloader)")
        print("2)  Dm-Verity fix (Disable AVB/Verity via Fastboot)")
        print("3)  Flasher GUI (Cross-Platform Image & GSI Flasher)")
        print("4)  Flasher TUI (Terminal Image & GSI Flasher)")
        print("5)  Flasher AGUI (Advanced Multi-Tool GUI Suite)")
        print("6)  Check status (Bootloader, Verity, Slot & Anti-Rollback)")
        print("7)  Check device info (Hardware, SoC & Firmware Props)")
        print("8)  Run diagnostics (Environment & USB Health Check)")
        print("9)  Reboot Manager (System / Recovery / Bootloader / FastbootD)")
        print("10) Restore NVRAM / IMEI Backup (BROM Mode)")
        print("11) Restore from .unjrc Data Recovery File (ADB)")
        print("12) Relock Bootloader (Stock Firmware Only!)")
        print("13) Done, exit the program")
        print(f"{MAGENTA}-----------------------------------------------------{NC}")
        opt = input("Select an option [1-13]: ").strip()

        if opt == "1":
            run_unjail(mode, selected_target)
        elif opt == "2":
            dm_verity_fix()
        elif opt == "3":
            flasher_gui(agui_mode=False)
        elif opt == "4":
            flasher_tui()
        elif opt == "5":
            flasher_gui(agui_mode=True)
        elif opt == "6":
            check_status()
        elif opt == "7":
            check_device_info()
        elif opt == "8":
            run_diagnostics()
        elif opt == "9":
            r = input("Reboot target: 1) System  2) Recovery  3) Bootloader  4) FastbootD: ").strip()
            wait_for_fastboot()
            mapping = {"1": [], "2": ["recovery"], "3": ["bootloader"], "4": ["fastboot"]}
            if r in mapping:
                run_cmd([fb, "reboot"] + mapping[r], capture=False)
        elif opt == "10":
            b_root = WORKDIR / "backups"
            if b_root.exists():
                for d in sorted(b_root.iterdir()):
                    print(" -", d.name)
            folder = input("Enter backup folder name: ").strip()
            b_path = b_root / folder
            if b_path.is_dir():
                print(f"{YELLOW}[*] Boot phone into BROM mode now (Vol+ & Vol- + USB)...{NC}")
                parts = "nvdata,nvcfg,nvram,persist,protect1,protect2"
                files = ",".join(str(b_path / f"{p}.bin") for p in parts.split(","))
                run_cmd(mtk_cmd + ["w", parts, files], capture=False)
                print(f"{GREEN}[+] NV/IMEI partitions restored!{NC}")
            else:
                print(f"{RED}[!] Backup folder not found.{NC}")
        elif opt == "11":
            restore_unjrc_file()
        elif opt == "12":
            print(f"{RED}WARNING: Relocking on custom ROMs, root, or disabled dm-verity WILL hard-brick your phone!{NC}")
            if input("Type RELOCK to confirm: ").strip() == "RELOCK":
                print(f"{YELLOW}[*] Boot phone into BROM mode now (Vol+ & Vol- + USB)...{NC}")
                run_cmd(mtk_cmd + ["da", "seccfg", "lock"], capture=False)
        elif opt == "13":
            print(f"{GREEN}Done! Exiting UnJailer.{NC}")
            sys.exit(0)
        else:
            print(f"{RED}[!] Invalid selection.{NC}")


if __name__ == "__main__":
    install_dependencies()
    startup_menu()
    os_mode = select_os_version()
    target = select_device()
    post_unjail_menu(os_mode, target)
