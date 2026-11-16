# unjailer

by deniusgg

unjailer is an all-in-one mediatek xiaomi bootloader unlocker, flasher, and local data recovery toolkit. no mi unlock tool, no xiaomi community quotas, no 168-hour wait timers—just straight hardware-level brom unlocking with automatic imei/nvram backups and a full post-unlock flashing suite.

platform support: available for both linux (`unjailer.sh` / `unjailer.py`) and windows (`unjailer.py` / `windows_unjailer.py`).

## disclaimer

unlocking the bootloader will trigger a full data wipe on your device. the developers of unjailer are not responsible for any bricked devices, lost data, or hardware damages. by running this tool, you accept full responsibility. always back up your data first (you can use the built-in `.unjrc` backup tool before unlocking).

## features

* zero-wait bootloader unlock (`unjail`): bypasses xiaomi's server restrictions using mediatek brom mode.

* full os and region compatibility: supports miui 11, 12, 13, 14 and hyperos 1, 2, 3 (including global, eea, and china (cn) builds via dynamic `jz8pnruf` rpmb lock magic detection and `seccfg` patching).

* automatic critical partition backup: automatically dumps `nvdata`, `nvcfg`, `nvram`, `persist`, `protect1`, `protect2`, `seccfg`, and `rpmb` before touching anything so your imei is always safe.

* `.unjrc` encrypted data recovery system: locally scans and backs up your media, documents, and app/account metadata into an aes-256 encrypted `.unjrc` container bound to your device's hardware signature—100% offline, zero cloud uploads.

* dynamic device detection: auto-detects connected phones across adb, fastboot, and mediatek brom/preloader usb ports and maps known codenames (like redmi 10 `selene`, redmi note 10s `rosemary`, poco m4 pro, etc.).

* complete post-unlock suite:

  * dm-verity fix: patches/flashes avb2.0 `vbmeta` (`--disable-verity --disable-verification`) across single-slot and a/b devices.

  * flasher gui: clean desktop file-picker flasher for `boot`, `recovery`, `vbmeta`, `system` (gsi), `super`, `dtbo`, and custom partitions.

  * flasher tui: full terminal-based image and gsi flasher (handles `fastbootd` logical partition resizing automatically).

  * flasher agui: advanced multi-tool control panel with raw brom partition read/write, a/b slot switching, partition wiping, and reboot controls.

  * status, device info, error scanner, and diagnostics: built-in tools to check lock state, anti-rollback (`anti`), usb 2.0 vs 3.0 port speed warnings, `modemmanager` conflicts, and `udev` rules.

## package and driver requirements

### linux package requirements (debian / ubuntu / linux mint)

* python3

* python3-venv

* python3-pip

* python3-tk

* git

* libusb-1.0-0

* adb

* fastboot

* usbutils

* zenity (for `unjailer.sh`)

* openssl (for `unjailer.sh`)

### windows package and driver requirements

* python 3.10 or newer (with pip and tkinter included)

* usbdk (usb development kit runtime)

* mediatek usb vcom / brom drivers

* google android sdk platform-tools (`adb.exe` and `fastboot.exe` - auto-downloaded by the script if missing)

* git (optional, script falls back to zip download if missing)

### shared python pip packages (auto-installed into the virtual environment on both platforms)

* pip

* wheel

* setuptools

* cryptography

* mtkclient (and its `requirements.txt` dependencies: pyusb, pyserial, keystone-engine, unicorn, capstone, colorama, mock)

## installation and usage

### linux (`unjailer.sh` or `unjailer.py`)

the script automatically installs missing system packages, sets up mediatek `udev` rules, and configures an isolated python virtual environment with `mtkclient`.

1. clone the repository:

   ```
   git clone https://github.com/AnikuHere/UnJailer.git
   cd UnJailer
   
   ```

2. run the bash script or the cross-platform python script:

   ```
   chmod +x unjailer.sh
   ./unjailer.sh
   
   ```

   or:

   ```
   python3 unjailer.py
   
   ```

### windows (`unjailer.py` / `windows_unjailer.py`)

1. install python 3.10+ (check "add python to path" during installation).

2. install mediatek usb vcom / brom drivers and usbdk.

3. clone the repository and run the python script (missing platform-tools and pip libraries are downloaded automatically):

   ```
   git clone https://github.com/AnikuHere/UnJailer.git
   cd UnJailer
   python unjailer.py
   
   ```

## how to enter brom mode

1. power off your phone completely (wait 5 seconds after the screen turns off).

2. use a usb 2.0 port (black) if possible—usb 3.0 ports can sometimes drop brom handshakes.

3. press and hold volume up + volume down at the exact same time.

4. while holding both buttons, plug the usb cable into your phone.

5. keep holding until unjailer detects the handshake and starts dumping partitions.

## about `.unjrc` data recovery files

* what is a `.unjrc` data recovery file?
  a custom local recovery format built for unjailer. it scans your device and backs up your images, videos, documents, and account/app info completely locally—nothing is ever sent to any server.

* what does `.unjrc` store?
  it stores your backed-up files along with an internal mapping manifest specifying exactly where each folder should be restored on your device.

* is `.unjrc` safe?
  yes. it uses aes-256 encryption combined with a hardware verification signature bound to your specific phone, locking the archive until it verifies the matching device environment.

* can i use `.unjrc` in my own projects?
  yes, you can use it in your projects as long as you give credit and keep your `.unjrc` implementation/modifications open source. even if the rest of your app is closed source, any `.unjrc` configuration or code changes must be open source and publicly accessible on a website or git host (such as github or gitlab).

## supported socs (hardware note)

works on xiaomi/redmi/poco devices powered by mediatek socs supported by the brom exploit (e.g., helio g25, g35, g80, g85, g88, g90t, g95, g96 and dimensity 700, 800, 810, 820, 900, 1000+, 1100, 1200). newer brom v6 chips (such as helio g99 and newer) patch brom at the silicon level.

## support the project

if unjailer saved you from xiaomi's unlock wait times, please star and share the repo.