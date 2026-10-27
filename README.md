# WinUtil TR

**Chris Titus Tech's Windows Utility with a Turkish interface.** An unofficial Turkish edition of [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil). **[Türkçe açıklama ↓](#türkçe)**

[![Version](https://img.shields.io/github/v/release/celaldrg/winutil-tr?color=%230567ff&label=Latest%20Release&style=for-the-badge)](https://github.com/celaldrg/winutil-tr/releases/latest)
![Downloads](https://img.shields.io/github/downloads/celaldrg/winutil-tr/winutil.ps1?label=Total%20Downloads&style=for-the-badge)
[![Tests](https://img.shields.io/github/actions/workflow/status/celaldrg/winutil-tr/unittests.yaml?branch=main&label=Tests&style=for-the-badge)](https://github.com/celaldrg/winutil-tr/actions/workflows/unittests.yaml)

WinUtil is a curated set of Windows system tasks: streamline **installs**, debloat with **tweaks**, troubleshoot with **config**, and configure **Windows updates**. This edition shows all of it in Turkish: navigation, buttons, tooltips, the descriptions of tweaks, features and apps, dialogs, and progress messages. It does the same things as WinUtil. Run it with `-Language en` to get the original English interface.

> Based on [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) (MIT License). This is an independent community edition, not affiliated with or endorsed by Chris Titus Tech.

![Title Screen](docs/src/assets/branding/title-screen.png)

---

## Türkçe

**WinUtil TR**, Chris Titus Tech'in [Windows Utility](https://github.com/ChrisTitusTech/winutil) aracının resmî olmayan Türkçe sürümüdür. Uygulama yükleme, ince ayarlar, yapılandırma ve Windows Update ayarları ana projeyle aynıdır. Menüler, düğmeler, ipuçları, ince ayar ve uygulama açıklamaları, iletişim kutuları ve ilerleme iletileri Türkçedir.

PowerShell'i ya da Terminal'i **yönetici olarak** açın ve şunu çalıştırın:

```ps1
irm https://github.com/celaldrg/winutil-tr/releases/latest/download/winutil.ps1 | iex
```

İngilizce arayüz için:

```ps1
$env:WINUTIL_LANG = 'en'; irm https://github.com/celaldrg/winutil-tr/releases/latest/download/winutil.ps1 | iex
```

- **Çeviriler:** [`lang/`](lang/) klasöründe, düz JSON çiftleri olarak durur. Düzeltme önerilerinizi bekliyoruz.
- **İngilizce kalanlar:** Kayıt (log) dosyaları ve `-Preset` ya da `-Config` ile arayüzsüz yapılan çalıştırmalar İngilizcedir.
- **Sorun bildirme:** Türkçe sürümle ilgili sorunları [bu depoya](https://github.com/celaldrg/winutil-tr/issues), WinUtil'in kendisiyle ilgili sorunları [ana projeye](https://github.com/ChrisTitusTech/winutil/issues) bildirin.
- **Lisans:** Bu sürüm, MIT lisanslı ChrisTitusTech/winutil üzerine kuruludur. Chris Titus Tech ile bir bağı yoktur ve onun onayını taşımaz.

---

## Quick Start

> **WinUtil must be run as Administrator** because it performs system-wide changes.

Open PowerShell or Terminal as admin, then run:

**Turkish (default)**
```ps1
irm https://github.com/celaldrg/winutil-tr/releases/latest/download/winutil.ps1 | iex
```

**English interface**
```ps1
$env:WINUTIL_LANG = 'en'; irm https://github.com/celaldrg/winutil-tr/releases/latest/download/winutil.ps1 | iex
```

### How to open an admin terminal

- **Start menu:** Right-click Start → *Windows PowerShell (Admin)* or *Terminal (Admin)*
- **Search:** Press the `Windows key`, and type `PowerShell` or `Terminal`, then `Ctrl + Shift + Enter`

---

## Automation / Presets

Apply a predefined configuration without manual selection:

```powershell
& ([ScriptBlock]::Create((irm https://github.com/celaldrg/winutil-tr/releases/latest/download/winutil.ps1))) -Preset Standard
```

| Preset | Description |
|--------|-------------|
| `Standard` | Balanced defaults for most users |
| `Minimal` | Minimal changes to suit every user |
| `Advanced` | Deep tweaks for power users |

To view exactly what each preset does, see [config/preset.json](config/preset.json).

---

## Language

| Setting | Interface |
|---|---|
| none (default) | Turkish |
| `-Language en` | English, exactly as upstream |
| `$env:WINUTIL_LANG = 'en'` | English, same as `-Language en` |

The translations are plain JSON pairs in [`lang/`](lang/).
- The compiled script embeds them as ASCII.
- When a translation is missing or no longer matches the English source, WinUtil shows the original English text.
- Logs, and headless `-Preset` or `-Config` runs, stay in English.
- After an upstream sync, `tools/Test-WinUtilTranslation.ps1 -Strict` reports missing, stale and conflicting translations.

---

## Build & Develop

See [CONTRIBUTING.md](.github/CONTRIBUTING.md).

---

## Resources

- [Official WinUtil Documentation](https://winutil.christitus.com/)
- [YouTube Tutorial](https://www.youtube.com/watch?v=6UQZ5oQg8XA)
- [ChrisTitus.com Article](https://christitus.com/windows-tool/)
- [Known Issues](https://winutil.christitus.com/knownissues/)
- Report a problem with the Turkish edition [here](https://github.com/celaldrg/winutil-tr/issues), and a problem with WinUtil itself [upstream](https://github.com/ChrisTitusTech/winutil/issues)

---

## Support

- Leave a ⭐ here and on [the original project](https://github.com/ChrisTitusTech/winutil)!
- Faster Dotnet Implementation for sale here: https://www.cttstore.com/windows-toolbox

## Sponsors

These are the sponsors that help keep the original project alive with monthly contributions.

<!-- sponsors --><a href="https://github.com/dwelfusius"><img src="https:&#x2F;&#x2F;github.com&#x2F;dwelfusius.png" width="60px" alt="User avatar: " /></a><a href="https://github.com/mews-se"><img src="https:&#x2F;&#x2F;github.com&#x2F;mews-se.png" width="60px" alt="User avatar: Martin" /></a><a href="https://github.com/jdiegmueller"><img src="https:&#x2F;&#x2F;github.com&#x2F;jdiegmueller.png" width="60px" alt="User avatar: Jason A. Diegmueller" /></a><a href="https://github.com/robertsandrock"><img src="https:&#x2F;&#x2F;github.com&#x2F;robertsandrock.png" width="60px" alt="User avatar: RMS" /></a><a href="https://github.com/paulsheets"><img src="https:&#x2F;&#x2F;github.com&#x2F;paulsheets.png" width="60px" alt="User avatar: Paul" /></a><a href="https://github.com/djones369"><img src="https:&#x2F;&#x2F;github.com&#x2F;djones369.png" width="60px" alt="User avatar: Dave J  (WhamGeek)" /></a><a href="https://github.com/anthonymendez"><img src="https:&#x2F;&#x2F;github.com&#x2F;anthonymendez.png" width="60px" alt="User avatar: Anthony Mendez" /></a><a href="https://github.com/FatBastard0"><img src="https:&#x2F;&#x2F;github.com&#x2F;FatBastard0.png" width="60px" alt="User avatar: " /></a><a href="https://github.com/DursleyGuy"><img src="https:&#x2F;&#x2F;github.com&#x2F;DursleyGuy.png" width="60px" alt="User avatar: DursleyGuy" /></a><a href="https://github.com/DwayneTheRockLobster1"><img src="https:&#x2F;&#x2F;github.com&#x2F;DwayneTheRockLobster1.png" width="60px" alt="User avatar: " /></a><a href="https://github.com/KieraKujisawa"><img src="https:&#x2F;&#x2F;github.com&#x2F;KieraKujisawa.png" width="60px" alt="User avatar: Kiera Meredith" /></a><a href="https://github.com/seanh1995"><img src="https:&#x2F;&#x2F;github.com&#x2F;seanh1995.png" width="60px" alt="User avatar: Sean (ANGRYxScotsman)" /></a><a href="https://github.com/josencarnacao"><img src="https:&#x2F;&#x2F;github.com&#x2F;josencarnacao.png" width="60px" alt="User avatar: José Encarnação" /></a><a href="https://github.com/tomandesMSH"><img src="https:&#x2F;&#x2F;github.com&#x2F;tomandesMSH.png" width="60px" alt="User avatar: TomandesMSH" /></a><!-- sponsors -->

*<sub>Sponsors with a recurring subscription also get access to the .NET alternative.</sub>

---

## Contributors

[![Contributors](https://contrib.rocks/image?repo=ChrisTitusTech/winutil)](https://github.com/ChrisTitusTech/winutil/graphs/contributors)

Thanks to everyone who has contributed time and effort to WinUtil. Keep rocking 🍻
