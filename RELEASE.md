# Release Preset Suara QRIS

Runbook rilis & rollback file preset (tanpa rebuild APK).

## Arsitektur

```
repo jagatoqo/suara-qris (branch main)
├── presets.json          ← data provider (disajikan per TAG, immutable)
├── presets-beta.json     ← data provider channel beta
├── latest.json           ← POINTER rilis → menunjuk @vX.Y.Z/presets.json
├── latest-beta.json      ← POINTER beta   → menunjuk @vX.Y.Z/presets-beta.json
└── release.ps1           ← script otomasi (tag + pointer + purge + verify)
```

- App membaca URL **stabil** `@main/latest.json` (di-build sekali di `PRESET_URL`).
- Rilis preset baru = **buat tag baru + update pointer** → app sync tanpa rebuild APK.
- Tag = versi terkunci. `latest.json` = satu-satunya file mutable di `main`.

## Setup sekali

```powershell
git clone https://github.com/jagatoqo/suara-qris.git
cd suara-qris
```

Salin `latest.json`, `latest-beta.json`, `release.ps1` dari folder `presets/` proyek ke
**root repo clone** (di samping `presets.json`), lalu:

```powershell
git add latest.json latest-beta.json release.ps1
git commit -m "Add preset pointer files + release script"
git push origin main
```

> Sebelum `latest.json` ada di repo, sync app akan gagal (`pointer_unreachable`).
> Aman — preset lokal terakhir tetap dipakai.

## Alur rilis manual (opsi tanpa script)

### 1. Edit data preset (`presets.json` + `presets-beta.json`)
- Tambah/ubah blok provider. Wajib benar: `provider_id`, `app_identifier` (= package
  name persis app sumber notifikasi), `detection_rules` sesuai teks notifikasi asli.
- Naikkan `bundle_version` (contoh `2026-08-20T09:00:00Z`).
- Provider yang rules-nya berubah: naikkan `"version"` blok tsb (1→2) supaya
  `PresetApplier` re-apply. Provider baru cukup `version: 1`.
- Untuk provider yang di-nonaktifkan: `"is_active_remote": false` (tanpa naikkan
  `version`) = kill-switch, rules dipertahankan untuk rollback.

### 2. Validasi JSON
```powershell
python -c "import json; json.load(open('presets.json', encoding='utf-8')); print('OK')"
```

### 3. Commit & push
```powershell
git add presets.json presets-beta.json
git commit -m "Add XYZ provider preset"
git push origin main
```

### 4. Tag baru (histori versi)
```powershell
git tag v1.0.1
git push origin v1.0.1
```

### 5. Update pointer ke tag baru
```powershell
# latest.json
{"preset_url": "https://cdn.jsdelivr.net/gh/jagatoqo/suara-qris@v1.0.1/presets.json"}
# latest-beta.json
{"preset_url": "https://cdn.jsdelivr.net/gh/jagatoqo/suara-qris@v1.0.1/presets-beta.json"}

git add latest.json latest-beta.json
git commit -m "Release v1.0.1"
git push origin main
```

### 6. Purge cache jsDelivr (WAJIB)
```powershell
curl "https://purge.jsdelivr.net/gh/jagatoqo/suara-qris@main/latest.json"
curl "https://purge.jsdelivr.net/gh/jagatoqo/suara-qris@main/latest-beta.json"
```

### 7. Verifikasi CDN
```powershell
curl -s "https://cdn.jsdelivr.net/gh/jagatoqo/suara-qris@main/latest.json"
# harus menampilkan preset_url ...@v1.0.1/presets.json
```

### 8. Terapkan di app
```powershell
adb shell am force-stop com.suaraqris.app
adb shell am start -n com.suaraqris.app/.MainActivity
adb logcat -d | findstr "PresetApplier PresetSync"
```
Ekspektasi log: `Upserted provider XYZ v1`, `Worker result SUCCESS`.
Verifikasi UI: Pengaturan → Kelola Provider QRIS → provider baru + status terpasang.

## Alur rilis dengan script `release.ps1` (otomatis langkah 4–7)

Jalankan dari **root repo clone**:

```powershell
# rilis baru
.\release.ps1 v1.0.1

# preview tanpa mengeksekusi apa pun
.\release.ps1 v1.0.1 -DryRun

# repo berbeda
.\release.ps1 v1.0.1 -Repo "namauser/namarepo"
```

Script melakukan: buat tag → update pointer → commit pointer → push main + tag →
purge CDN → verifikasi pointer. Lalu tampilkan perintah untuk memicu sync di app.

> Script hanya menangani tag/pointer/purge/verify. Edit & commit `presets.json`
> dilakukan manual di langkah 1–3.

## Alur rollback

### Cepat (tanpa hapus tag)
```powershell
.\release.ps1 v1.0.0 -RollbackTo v1.0.0   # atau manual: pointer ke tag lama + push + purge
```
Saat app sync:
- Provider baru yang tidak ada di bundle lama → tombstone (dinonaktifkan, rules dipertahankan).
- Provider yang naik versi → rollback otomatis dari `provider_profiles_history`.

### Kill-switch satu provider (darurat, tanpa rollback seluruh bundle)
Set `"is_active_remote": false` pada blok provider tsb, bump `bundle_version`,
rilis seperti biasa. `PresetApplier` menonaktifkannya dan mempertahankan rules
untuk rollback ke versi kerja terakhir.

## Checklist tiap rilis

- [ ] `bundle_version` dinaikkan
- [ ] `version` provider dinaikkan untuk provider yang rules-nya berubah
- [ ] JSON valid (langkah 2)
- [ ] Tag baru dibuat + dipush
- [ ] `latest.json` / `latest-beta.json` diupdate + dipush
- [ ] Cache di-purge
- [ ] Pointer CDN terverifikasi menunjuk ke tag baru
- [ ] App sync SUCCESS (`PresetApplier`), UI Kelola Provider benar

## Troubleshooting

| Gejala | Penyebab | Solusi |
|---|---|---|
| Sync `pointer_unreachable` | `latest.json` belum ada / path salah | Buat file di root repo, purge |
| Pointer di CDN masih tag lama | Cache jsDelivr belum ter-purge | Ulangi `purge.jsdelivr.net`, cek header `age` |
| Provider tidak muncul | `bundle_version`/`version` tidak naik, atau tag belum dibuat | Pastikan bump + tag dibuat sebelum pointer diubah |
| Provider tampil "tidak ditemukan" | `app_identifier` bukan package name asli | Cek `adb shell pm list packages \| findstr -i nama` |