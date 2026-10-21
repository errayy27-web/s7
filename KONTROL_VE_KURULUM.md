# SS OIL SQL Entegrasyonu — Kontrol ve Kurulum

Bu paket, kullanıcının gönderdiği `SS_OIL_CADMUS_TAMAM_AKISI_KONTROLLU(1).zip` kaynak kodundan türetilmiştir. Mevcut sayım, Excel ve Cadmus kodları korunarak eklenenler:

- SQL Ayarları: bilgisayar servis adresi ve erişim anahtarı.
- Stok Güncelle: ART ürünleri ile ART_BK barkodlarının toplu aktarımı; ART stokları baz değer olarak kaydedilir.
- Barkod Oku: barkod eşleşmesi ile Artikal ID bulma; birden fazla ID varsa seçim/elle giriş; SQL'den `ART.Kolicina - SUM(SmP_S.Kolicina)` sorgulama; telefonun stok ve fiyatını güncelleme.
- Tanımsız/çift/yanlış barkodları yerel kayıt ve Excel'de beşinci `Hatali Barkodlar` sayfasına `Artikal ID, Barkod, Hata` sütunlarıyla aktarma.
- SQL'de hiçbir yazma işlemi bulunmaz. Yalnızca SELECT.

## Bilinen sınırlar ve testler

- SQL Server 2005 ile ODBC uyumluluğu gerçek bilgisayarda doğrulanmalı.
- SQL şema alanları, fotoğraflardaki isimler temel alınarak kodlandı; `ART_BK.BKod_ID` gerçek barkod metni değilse sorgu uyarlanmalı.
- SmP_S satış toplamının hangi dönemi kapsadığı doğrulanmalı. Toplam geçmiş satış ise ART stokundan hepsini çıkarmak yanlış olabilir.
- Telefon ve bilgisayar aynı yerel ağda olmalı; servis çalışır durumda olmalı.
- Kaynak kodun statik ve Python sözdizimi testleri yapılmıştır; Flutter SDK bu ortamda kurulu olmadığı için gerçek Flutter derlemesi ve cihaz testi yapılamamıştır.
- Paket kaynak kodudur, APK değildir. `.github/workflows/android.yml` GitHub Actions ile derleme içindir.
- HTTP + token yerel ağ içindir; güvenilmeyen ağlarda TLS/VPN gereklidir.
- Mevcut uygulamanın yedeğini alın; aynı uygulama kimliğiyle yüklerken eski yerel kayıtları korumak için uygulamayı kaldırmayın.
