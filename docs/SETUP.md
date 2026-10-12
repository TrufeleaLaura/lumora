# One-time setup (Windows + iPhone)

You only do this once. After that, each new build is: download the `.ipa` (Claude puts it in the
`builds/` folder for you) → drag it into Sideloadly → Start.

## 1. GitHub (for the cloud builds)
1. Create a free account at https://github.com if you don't have one.
2. Log in from this PC when Claude asks (it opens a browser page where you approve the login).
   Claude never sees or types your password.

## 2. Windows: install the sideloading tools
1. Install **iTunes** and **iCloud** for Windows, downloaded from Apple's website
   (Sideloadly needs the Apple-website versions, not the Microsoft Store ones; check the current
   requirements on https://sideloadly.io).
2. Install **Sideloadly** from https://sideloadly.io.

## 3. iPhone
1. Connect the iPhone to the PC with a cable, unlock it and tap **Trust This Computer**.
2. Turn on **Developer Mode**: Settings → Privacy & Security → Developer Mode → On → restart the phone.
   (If the option is missing, it appears after the first sideload attempt.)

## 4. Install Lumora
1. Open Sideloadly, drag `builds/Lumora.ipa` into it.
2. Enter your Apple ID in Sideloadly (tip: a secondary Apple ID works too). You type this yourself.
3. Click **Start**. When it finishes, on the iPhone go to
   Settings → General → VPN & Device Management → your Apple ID → **Trust**.
4. Open Lumora.

## Good to know
- Free Apple ID builds stop opening after **7 days**. Re-install the latest `.ipa` with Sideloadly
  (or enable its auto-refresh) — your photos and edits are not affected.
- A free Apple ID allows **3 sideloaded apps** at a time.
- Updating: installing a newer `Lumora.ipa` over the old one keeps the app's data.
