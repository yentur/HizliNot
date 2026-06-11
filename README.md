# Hızlı Not — MacBook için uçan not widget'ı

`claude.ai/design` mockup'ından (`Hizli Not.dc.html`) gerçek bir **native macOS uygulamasına** dönüştürülmüş hâli. Pencere yönetimi, global kısayol, tüm Space'lerde üstte kalma, sürükle/boyutlandır tamamen native Swift (AppKit); arayüz ise tasarımın birebir HTML/CSS/JS portu olup sistemin WebKit'inde render edilir (paket ~birkaç yüz KB, gömülü runtime yok).

## Özellikler

- **⌘⇧N** ile her yerden notu aç/kapat (global kısayol — erişilebilirlik izni gerekmez).
- **Esc** ile gizle. Menü çubuğundaki ikon ↔ aç/gizle, çıkış.
- **Her ekranın üstünde** kalır — başka uygulamaya/Space'e geçsen bile görünür (floating, canJoinAllSpaces).
- Başlıktan **sürükle**, sağ/alt kenardan ve sağ-alt ◢ köşesinden **boyutlandır**.
- **Sekmeler:** birden çok not; `+` ile yeni, `×` ile kapat.
- **Notion benzeri editör:** H1, H2, **B**, _i_, • madde, ☑ yapılacak (tıkla → işaretle/üstünü çiz).
- **Pano** sekmesi: **kopyaladığın her şey otomatik düşer** (native pano izleyici); karta tıkla → tekrar panoya kopyalanır.
- **Dosyalar / Raf** — Dropover tarzı dosya rafı:
  - **Sürüklerken salla → raf imlecinin yanında belirir** (shake-to-summon), dosyaları üstüne bırak.
  - Menü çubuğundan ya da Dosyalar sekmesindeki **“Rafı aç”** ile de açılır.
  - Raftaki bir dosyayı **Finder’a / başka uygulamaya geri sürükle** (gerçek dosya, native drag-out), çift-tık → Finder’da göster, **✕** ile kaldır, **Temizle** ile boşalt.
  - Dosyalar diske kopyalanır; **İndir** (native kaydet paneli) ve **Finder** (göster) düğmeleri Dosyalar sekmesinde de var.
- **Saydam cam (vibrancy)** arkaplan — gerçek macOS frosted-glass; Ayarlar'dan açılıp kapatılır.
- **macOS trafik ışıkları**: 🔴 gizle · 🟡 küçült (windowshade) · 🟢 boyut (büyüt/geri).
- **Ayarlar (⚙)**: Tema (Açık / Koyu / **Sistem**), **9 vurgu rengi**, saydamlık, açılışta başlat, kısayol, uygulamadan çık.
- **Nota fotoğraf**: editöre **yapıştır (⌘V)** ya da **sürükle-bırak** → resim gömülür ve notla birlikte otomatik kaydedilir.
- Notlar, pano, tema, vurgu rengi, konum ve boyut otomatik kaydedilir.

## Kurulum / Çalıştırma

```bash
cd ~/HizliNot
./build.sh
```

`build.sh` derler, `HizliNot.app` paketini üretir, ad-hoc imzalar ve **/Applications**'a kurar.
Sonra Launchpad / Spotlight'tan **"Hızlı Not"** olarak aç, ya da:

```bash
open "/Applications/HizliNot.app"
```

> Menü çubuğu uygulamasıdır (LSUIElement): Dock'ta ve ⌘-Tab'da görünmez. Erişim menü çubuğundaki ikondan ve ⌘⇧N kısayolundandır. Applications klasöründe / Launchpad'de / Spotlight'ta görünür.

### Açılışta otomatik başlatma (opsiyonel)
Sistem Ayarları → Genel → Giriş Öğeleri → `+` → `/Applications/Hızlı Not` ekle.

## Mimari

| Dosya | Görev |
|---|---|
| `Sources/HizliNot/main.swift` | NSPanel (borderless, floating, nonactivating, tüm Space'ler), Carbon global kısayol, menü çubuğu, native sürükle/boyutlandır, native pano izleyici, JS↔Swift köprüsü, konum-boyut kalıcılığı. |
| `Sources/HizliNot/WebContent.swift` | Tasarımın birebir HTML/CSS/JS portu (gömülü string). Sahte masaüstü/dock/pill çıkarıldı; widget pencereyi doldurur. |
| `Sources/HizliNot/Shelf.swift` | Dropover tarzı raf: `FileStore` (diske kopyalayan tek kaynak), `ShakeMonitor` (global fare sürükleme + sallama algılama), `ShelfPanel`/`ShelfView` (HUD görünüm, drag-in destination + drag-out source), `ChipView` (Finder’a sürüklenebilir dosya çipi). |
| `build.sh` | Derle → `.app` paketle → imzala → /Applications'a kur. |

### Veri konumu
- Notlar/pano/tema: `~/Library/Application Support/HizliNot/state.json`
- Pencere konumu/boyutu: `com.omer.hizlinot` UserDefaults
- Dosyalar oturum boyunca bellektedir (uygulama kapanınca sıfırlanır — tasarımdaki gibi).

## Kaldırma
```bash
rm -rf "/Applications/HizliNot.app"
defaults delete com.omer.hizlinot
rm -rf "~/Library/Application Support/HizliNot"
```
