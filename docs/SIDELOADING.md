# Installing Vieo TV on an Android TV without the Play Store

Everything below is verified against the APK this repo actually builds.

| | |
|---|---|
| Package | `com.vieo.vieo_tv` |
| Version | `1.0.0` (versionCode `1`) |
| minSdk / targetSdk | 24 / 36 |
| ABIs in the APK | `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| TV launcher entry | present (`leanback-launchable-activity`) |
| Touchscreen / mic | both declared not required |

`adb` lives at `$ANDROID_HOME/platform-tools/adb` — on this machine
`/home/arthur/.android-sdk/platform-tools/adb`. Add it to `PATH` or call it by full path.

## 0. The short way: download it on the TV

Every push to `main` builds the APKs in CI and attaches them to a release, so
there is usually nothing to build:

1. On the TV, allow installs from whichever app you will download with —
   **Settings → Apps → Security & restrictions → Unknown sources**.
2. Open a browser or downloader app on the TV and go to **arthurkay.github.io/tv**.
3. Choose **Download the APK**, open the file, confirm.

Direct link, if your downloader wants a URL rather than a page:

```
https://github.com/arthurkay/tv/releases/latest/download/vieo-tv-arm64-v8a.apk
```

Older or budget hardware needs `vieo-tv-armeabi-v7a.apk` from the same release.

The rest of this document is the developer path: building locally and installing
over adb, which is what you want while changing the app.

## 1. Build the APK

```bash
flutter build apk --debug      # build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release    # build/app/outputs/flutter-apk/app-release.apk
```

**The debug APK is ~209 MB** — it carries libmpv for three ABIs. For anything but a
quick test, build one APK per architecture instead:

```bash
flutter build apk --release --split-per-abi
```

Then pick the one your device needs:

- `arm64-v8a` (29 MB) — Chromecast with Google TV, NVIDIA Shield, essentially every TV or box from 2019 on.
- `armeabi-v7a` (26 MB) — older or budget sticks.
- `x86_64` (33 MB) — emulators only.

Unsure? `adb shell getprop ro.product.cpu.abi` tells you.

> **Release builds are still signed with the debug keystore** (the Flutter template TODO in
> `android/app/build.gradle.kts`). That installs fine on your own devices, but it is not
> distributable, and debug keystores differ per machine — an APK built on another machine
> will not upgrade over yours.

## 2. Put the TV into developer mode

1. **Settings → System → About**
2. Scroll to **Build** (on Google TV: **Android TV OS build**) and click it **7 times** until
   it says you are a developer.
3. Back out to **Settings → System → Developer options** and enable **USB debugging**.
   If the device offers **Wireless debugging**, enable that too.

Many TVs reset debugging on reboot — if a connection is refused later, check this first.

## 3. Connect over the network

TVs rarely expose USB device mode, so network adb is the normal route. Find the address under
**Settings → Network & Internet → (your network) → IP address**, then:

```bash
adb connect 192.168.1.50:5555      # accept the prompt that appears on the TV
adb devices -l                      # confirm it is listed as "device"
```

On Android 11+ / TV 12+ using **Wireless debugging**, pair first with the code the TV shows:

```bash
adb pair 192.168.1.50:41234        # port and 6-digit code come from the TV screen
adb connect 192.168.1.50:37000     # the "IP & port" shown under Wireless debugging
```

Ethernet is dramatically faster than Wi-Fi for pushing a large APK.

## 4. Install

```bash
adb install -r build/app/outputs/flutter-apk/app-release-arm64-v8a.apk
```

Or let Flutter pick the device:

```bash
flutter devices
flutter install -d <deviceId>
flutter run     -d <deviceId>     # development, with hot reload
```

## 5. Launch it

It appears in the launcher's **Apps** row. From the terminal:

```bash
adb shell am start -n com.vieo.vieo_tv/.MainActivity
```

## 6. Drive it without touching the remote

Handy for exercising the D-pad paths:

```bash
adb shell input keyevent 19   # up            23  OK / select
adb shell input keyevent 20   # down           4  back
adb shell input keyevent 21   # left          84  search
adb shell input keyevent 22   # right         85  play / pause
adb shell input keyevent 166  # channel up   167  channel down
```

Assistant handoff, without speaking to the TV:

```bash
adb shell am start -a android.media.action.MEDIA_PLAY_FROM_SEARCH \
  -e query "bondi vet" -n com.vieo.vieo_tv/.MainActivity

adb shell am start -a com.google.android.gms.actions.SEARCH_ACTION \
  -e query "news" -n com.vieo.vieo_tv/.MainActivity
```

The first should start playing the best match; the second should land in search results.

## 7. Read the logs

The thumbnail pipeline narrates itself, which is how to tell whether frame capture works on
real hardware:

```bash
adb logcat -s flutter:V
adb logcat | grep -i thumbnail
```

Expect one line per stage — `opened, waiting for video`, `video is 1920x1080`,
`attempt 0 -> 148213 bytes`, `scaled to 41027 bytes` — or an explicit reason it gave up
(`no video within 30s`, `screenshot timed out`, `capture abandoned`).

Cached frames on a debug build:

```bash
adb shell run-as com.vieo.vieo_tv ls -la cache/channel_thumbnails
```

## 8. Installing with no computer at all

1. **Settings → Apps → Security & restrictions → Unknown sources**, and allow the app you
   will install *from* (a file manager or downloader).
2. Put the APK on a USB stick, or host it on your LAN and fetch it on the device.
3. Open it with that file manager and confirm.

Most Google TV devices ship without a file manager, so you need to install one from the Play
Store first. At ~209 MB the debug APK is painful this way — use a `--split-per-abi` release
build.

## 9. When it goes wrong

| Symptom | Cause and fix |
|---|---|
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Signature mismatch — switching between debug and release, or an APK from another machine. `adb uninstall com.vieo.vieo_tv` first. |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | Common on 8 GB sticks with the ~209 MB debug APK. Use a split release build. |
| `adb connect` → connection refused | Debugging switched itself off after a reboot. Re-enable it in Developer options. |
| `unauthorized` in `adb devices` | The allow-debugging prompt on the TV was missed or dismissed. Reconnect and accept it. |
| App missing from the launcher | Check the install actually succeeded; the leanback entry is present in the manifest, so a successful install always shows in the Apps row. |
| No streams play, but the UI works | The release manifest needs `INTERNET`. It is present now — if you are testing an older APK, that was the bug. |

```bash
adb uninstall com.vieo.vieo_tv
```
