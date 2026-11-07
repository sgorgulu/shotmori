# Shotmori yerelleştirme üreteci: tek kaynak → Strings.swift + tr/en Localizable.strings
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "Shotmori"

# (anahtar, Türkçe, İngilizce). Biçim yer tutucuları %d / %@ her iki dilde aynı sayıda olmalı.
T = [
 # Panel
 ("shelfTitle", "Screenshot rafı", "Screenshot shelf"),
 ("hideShelf", "Gizle", "Hide"),
 ("shelfDefaultName", "Raf %d", "Shelf %d"),
 ("shelfPin", "Rafı önde tut", "Keep shelf in front"),
 ("shelfPinHelp", "Başka pencereye tıklayınca veya bıraktıktan sonra raf kapanmaz; Esc ya da Gizle kapatır.", "The shelf stays open when you click another window or after a drop; Esc or Hide closes it."),
 ("shelfPinOn", "Raf önde tutuluyor", "Shelf kept in front"),
 ("shelfPinOff", "Raf önde tutulmuyor", "Shelf no longer kept in front"),
 ("shelfTabNew", "Yeni raf", "New shelf"),
 ("shelfTabNewHelp", "Yeni bir raf açar (en çok 8).", "Opens a new shelf (up to 8)."),
 ("shelfRename", "Yeniden adlandır…", "Rename…"),
 ("shelfClose", "Rafı kapat…", "Close shelf…"),
 ("shelfDetach", "Ayrı pencerede aç", "Open in separate window"),
 ("shelfReattach", "Geri tak", "Put back"),
 ("shelfCloseTitle", "“%@” kapatılsın mı?", "Close “%@”?"),
 ("shelfCloseBody.one", "1 görüntü var. Dosyalar diske dokunulmadan kalır.", "It holds 1 image. Files on disk are not touched."),
 ("shelfCloseBody.other", "%d görüntü var. Dosyalar diske dokunulmadan kalır.", "It holds %d images. Files on disk are not touched."),
 ("shelfCloseMove", "Görüntüleri “%@” rafına taşı", "Move images to “%@”"),
 ("shelfCloseDrop", "Listeden düşür", "Remove from list"),
 ("actionMoveToShelf", "Rafa taşı", "Move to shelf"),
 ("actionMoveToShelfHelp", "Seçili görüntüleri başka bir rafa taşır; dosyalar yerinde kalır.", "Moves the selected images to another shelf; files stay where they are."),
 ("moveToNewShelf", "Yeni rafa…", "New shelf…"),
 ("movedToShelfToast.one", "1 görüntü “%@” rafına taşındı", "1 image moved to “%@”"),
 ("movedToShelfToast.other", "%d görüntü “%@” rafına taşındı", "%d images moved to “%@”"),
 ("moveTrimmedToast.one", "Taşındı · raf sınırı: en eski 1 görüntü listeden düştü, dosya diskte kalır", "Moved · shelf limit: the oldest image left the list; the file stays on disk"),
 ("moveTrimmedToast.other", "Taşındı · raf sınırı: en eski %d görüntü listeden düştü, dosyalar diskte kalır", "Moved · shelf limit: the %d oldest images left the list; files stay on disk"),
 ("shelfTabAX.one", "%@, 1 görüntü", "%@, 1 image"),
 ("shelfTabAX.other", "%@, %d görüntü", "%@, %d images"),
 ("shelfTabSelectedAX", "seçili", "selected"),
 ("shelfSwitchedAX", "Raf: %@", "Shelf: %@"),
 ("shelfInWindowBadge", "pencerede", "in window"),
 ("popoverShelfPicker", "Raf", "Shelf"),
 ("imageCount.one", "1 görüntü", "1 image"),
 ("imageCount.other", "%d görüntü", "%d images"),
 ("selectedCount.zero", "Seçim yok", "Nothing selected"),
 ("selectedCount.one", "1 görüntü seçili", "1 image selected"),
 ("selectedCount.other", "%d görüntü seçili", "%d images selected"),
 ("newBadge", "Yeni", "New"),
 ("editedCaption", "Düzenlendi", "Edited"),
 ("copyShort", "Kopyala", "Copy"),
 ("stripSelectedCount", "%d seçili", "%d selected"),
 ("copyShortCount", "Kopyala (%d)", "Copy (%d)"),
 ("quitShort", "Çık", "Quit"),
 ("newCount.one", "1 yeni", "1 new"),
 ("newCount.other", "%d yeni", "%d new"),
 ("emptyShelfTitle", "Görüntüleriniz burada birikir", "Your images collect here"),
 ("emptyShelfBody", "macOS ile ekran görüntüsü alın, sonra bu raftan sürükleyin.", "Take a screenshot with macOS, then drag it from this shelf."),
 ("folderMissing", "Ekran görüntüsü klasörüne erişilemiyor.", "The screenshot folder can’t be accessed."),
 ("missingFile", "Dosya diskte bulunamadı", "File not found on disk"),
 ("removeHint", "Raftan kaldır — dosya korunur", "Remove from shelf — the file is kept"),
 ("removeAXLabel", "Raftan kaldır", "Remove from shelf"),
 ("removeAXHelp", "Yalnızca bu kareyi raftan kaldırır; dosya diskte korunur.", "Removes only this item from the shelf; the file stays on disk."),
 ("actionRemoveSelected", "Seçilenleri raftan kaldır (%d)", "Remove selected from shelf (%d)"),
 ("trashConfirmMore", "… ve %d dosya daha", "… and %d more"),
 ("moreActions", "İşlemler", "Actions"),
 ("actionsMenuShortcutHelp", "İşlemler (⌘K)", "Actions (⌘K)"),
 # Eylemler
 ("actionCopyImage", "Görüntüyü kopyala", "Copy image"),
 ("actionCopyImages", "Görüntüleri kopyala (%d)", "Copy images (%d)"),
 ("actionOpen", "Aç", "Open"),
 ("actionOpenWith", "Şununla aç…", "Open with…"),
 ("actionRevealInFinder", "Finder’da göster", "Show in Finder"),
 ("actionSaveAs", "Farklı kaydet…", "Save as…"),
 ("actionShare", "Paylaş…", "Share…"),
 ("actionRemoveFromShelf", "Raftan kaldır", "Remove from shelf"),
 ("actionClearShelf", "Rafı temizle…", "Clear shelf…"),
 ("scopeWholeShelf", "Tüm raf", "Whole shelf"),
 ("scopeSingleImage", "Tek görüntü", "Single image"),
 ("actionMoveToTrash", "Dosyayı Çöp’e taşı…", "Move file to Trash…"),
 ("actionMoveToTrashMany", "%d dosyayı Çöp’e taşı…", "Move %d files to Trash…"),
 ("actionNewGroup", "Buradan yeni grup başlat", "Start new group here"),
 ("actionNewGroupHelp", "Bu görüntüden itibaren gelenleri rafta ayrı bir grup olarak gösterir; dosyalara dokunmaz.", "Shows this image and everything after it as a separate group on the shelf; files are not touched."),
 ("actionEndGroup", "Grup ayracını kaldır", "Remove group divider"),
 ("reasonImagesOnly", "Yalnızca görüntüler için", "Images only"),
 ("reasonSingleOnly", "Tek görüntü", "Single image"),
 ("reasonNoSelection", "Önce bir ekran görüntüsü seçin", "Select a screenshot first"),
 ("reasonMissing", "Dosya diskte yok", "File is missing on disk"),
 ("trashConfirmTitle", "Dosya Çöp’e taşınsın mı?", "Move the file to the Trash?"),
 ("trashConfirmTitleMany", "%d dosya Çöp’e taşınsın mı?", "Move %d files to the Trash?"),
 ("trashConfirmBody.one", "Dosya klasöründen ve raftan kaldırılır. Finder’daki Çöp’ten geri alabilirsiniz.", "The file is removed from its folder and the shelf. You can restore it from the Trash in the Finder."),
 ("trashConfirmBody.other", "Dosyalar klasörlerinden ve raftan kaldırılır. Finder’daki Çöp’ten geri alabilirsiniz.", "The files are removed from their folders and the shelf. You can restore them from the Trash in the Finder."),
 ("trashConfirmButton", "Çöp’e taşı", "Move to Trash"),
 ("trashConfirmButtonMany", "%d dosyayı Çöp’e taşı", "Move %d files to Trash"),
 ("cancel", "Vazgeç", "Cancel"),
 ("ok", "Tamam", "OK"),
 ("clearShelfBody", "Yalnızca raf temizlenir. Dosyalarınız bulundukları klasörde kalır.", "Only the shelf is cleared. Your files stay in their folder."),
 ("clearShelfTitle.one", "Raftaki 1 görüntü kaldırılsın mı?", "Remove 1 image from the shelf?"),
 ("clearShelfTitle.other", "Raftaki %d görüntü kaldırılsın mı?", "Remove %d images from the shelf?"),
 ("clearShelfButton", "Rafı temizle", "Clear shelf"),
 ("permLocal", "Yerel dosya işlemi", "Local file operation"),
 ("permSystemShare", "Sistem paylaşımı", "System sharing"),
 ("permExternal", "Dış servis", "External service"),
 # Menü
 ("menuShowShelf", "Rafı göster", "Show shelf"),
 ("menuCopyLast", "Son görüntüyü kopyala", "Copy latest image"),
 ("menuAddFromClipboard", "Panodan ekle", "Add from clipboard"),
 ("menuActions", "İşlemler", "Actions"),
 ("menuSettings", "Ayarlar…", "Settings…"),
 ("menuChooseFolder", "İzlenen klasörü seç…", "Choose watched folder…"),
 ("folderSaveFailed", "Klasör kaydedilemedi. Başka bir klasör seçmeyi deneyin.", "The folder couldn’t be saved. Try choosing another folder."),
 ("relaunchFailed", "Shotmori yeniden başlatılamadı. Uygulamadan çıkıp yeniden açın.", "Shotmori couldn’t relaunch. Quit and open it again."),
 ("emptyNoFolderBody", "Önce izlenen klasörü seçin.", "Choose a watched folder first."),
 ("menuHelp", "Yardım", "Help"),
 ("menuRerunSetup", "Kurulumu yeniden çalıştır…", "Run setup again…"),
 ("menuShowLog", "Tanılama günlüğünü göster", "Show diagnostic log"),
 ("menuAbout", "Shotmori hakkında", "About Shotmori"),
 ("menuQuit", "Shotmori’den çık", "Quit Shotmori"),
 ("menuHideApp", "Shotmori’yi gizle", "Hide Shotmori"),
 ("menuEdit", "Düzen", "Edit"),
 ("menuUndo", "Geri al", "Undo"),
 ("menuRedo", "Yinele", "Redo"),
 ("menuCut", "Kes", "Cut"),
 ("menuCopy", "Kopyala", "Copy"),
 ("menuPaste", "Yapıştır", "Paste"),
 ("menuSelectAll", "Tümünü seç", "Select All"),
 ("menuWindow", "Pencere", "Window"),
 ("menuClose", "Kapat", "Close"),
 ("menuMinimize", "Küçült", "Minimize"),
 ("clipboardNoImage", "Panoda görsel yok.", "No image on the clipboard."),
 # Ağır dosya işleri (Görev 6)
 ("clipboardFileName", "Pano %@", "Clipboard %@"),
 ("preparingImage", "Görüntü hazırlanıyor…", "Preparing image…"),
 # Ayarlar
 ("settingsTitle", "Shotmori ayarları", "Shotmori settings"),
 ("settingsStartupSection", "Başlangıç", "Startup"),
 ("settingsKeyboardSection", "Klavye", "Keyboard"),
 ("shelfBehaviorSection", "Raf davranışı", "Shelf behaviour"),
 ("scopeSelection", "Seçim", "Selection"),
 ("favoritesOverflowNote", "Yer kalmayan favoriler, aynı sırayla İşlemler menüsüne taşar.", "Favorites that don’t fit overflow into the Actions menu in the same order."),
 ("obStepCapture", "Görüntüyü al", "Take the image"),
 ("obStepShelf", "Rafta bul", "Find it on the shelf"),
 ("obStepDrag", "Sürükle", "Drag"),
 ("obFolderPermission", "Shotmori yalnız sizin seçtiğiniz klasörlere erişir.", "Shotmori only accesses folders you choose."),
 ("obHotKeyHelp", "Değiştirmek için kaydediciye tıklayın.", "Click the recorder to change it."),
 ("obSkipForNow", "Şimdilik atla", "Skip for now"),
 ("obShelfOpens", "Rafı aç", "Open the shelf"),
 ("obProgress", "%d / %d", "%d / %d"),
 ("tabScreenshots", "Ekran Görüntüleri", "Screenshots"),
 ("tabActions", "İşlemler", "Actions"),
 ("tabGeneral", "Genel", "General"),
 ("folderLabel", "İzlenen klasör", "Watched folder"),
 ("folderCustom", "Seçtiğiniz klasör", "Your chosen folder"),
 ("folderNotChosen", "Klasör seçilmedi", "No folder chosen"),
 ("chooseFolder", "Klasör Seç…", "Choose Folder…"),
 ("maxItemsLabel", "Rafta tutulacak görüntü", "Images kept on the shelf"),
 ("shelfStyle", "Raf görünümü", "Shelf style"),
 ("shelfStyleFloating", "Yüzen panel", "Floating panel"),
 ("shelfStyleStrip", "Üst şerit", "Top strip"),
 ("shelfStyleHelp", "Yüzen panel imlecin yanında açılır. Üst şerit ekranın üst kenarından iner.", "The floating panel opens beside the pointer. The top strip comes down from the top edge of the screen."),
 ("stripNewCapture", "Yeni karede şerit", "Strip on a new capture"),
 ("stripNewCapturePeek", "Kısa süre göster", "Show briefly"),
 ("stripNewCaptureStay", "Kapatana kadar açık", "Keep open"),
 ("stripNewCaptureHelp", "Kısa süre: 2,5 saniye sonra kendiliğinden çekilir. Kapatana kadar açık: kısayol, dışarı tıklama ya da kabul edilen bırakma kapatır; Esc bir karta tıkladıktan sonra çalışır.", "Briefly: tucks away after 2.5 seconds. Keep open: the shortcut, a click elsewhere or an accepted drop closes it; Esc works after you click a card."),
 ("stripMenuBarReveal", "İmleç menü çubuğunda durunca şeridi indir", "Bring the strip down when the pointer rests in the menu bar"),
 ("stripMenuBarRevealHelp", "Menü çubuğuna tıklamak şeridi kaldırır.", "Clicking the menu bar puts the strip away."),
 ("showOnNewShot", "Yeni ekran görüntüsünde rafı göster", "Show the shelf when a screenshot arrives"),
 ("showOnNewShotHelp", "Yeni kare kaydedilince raf odak çalmadan açılır. Yüzen panelde Esc, dışarı tıklama ya da bırakma kapatır; üst şeritte “Yeni karede şerit” ayarı geçerlidir.", "Opens without taking focus when a new capture is saved. The floating panel closes with Esc, a click elsewhere or a drop; the top strip follows “Strip on a new capture”."),
 ("hideAfterDrop", "Bıraktıktan sonra rafı gizle", "Hide the shelf after dropping"),
 ("hideAfterDropHelp", "Hedef kabul edince kapanır. ⌥ basılıysa açık kalır.", "Closes once the target accepts. Stays open while ⌥ is held."),
 ("thumbnailWarningTitle", "Yeni görüntü gecikiyor mu?", "New image arriving late?"),
 ("thumbnailWarningBody", "macOS’un yüzen küçük resmi kapanınca dosya kaydedilir (yaklaşık 5 sn). Ekran görüntüsü seçeneklerinden (%@ → Seçenekler) kapatabilirsiniz.", "macOS writes the file once its floating thumbnail closes (about 5 s). You can turn it off in the screenshot options (%@ → Options)."),
 ("favoritesLabel", "Favoriler", "Favorites"),
 ("favoritesHelp", "Sıra siz değiştirmedikçe sabit kalır.", "The order stays fixed unless you change it."),
 ("moveUp", "Yukarı", "Up"),
 ("moveDown", "Aşağı", "Down"),
 ("hotKeyLabel", "Rafı göster / gizle", "Show / hide shelf"),
 ("hotKeyRecordHint", "Tuş bileşimine basın (⌘, ⌃ veya ⌥ içermeli); Esc iptal eder", "Press a key combination (must include ⌘, ⌃ or ⌥); Esc cancels"),
 ("hotKeyRecordStart", "Kaydetmek için tıklayın ya da odaktayken Boşluk/Return", "Click, or press Space/Return while focused, to record"),
 ("keySpace", "Boşluk", "Space"),
 ("keyCodeName", "Tuş %d", "Key %d"),
 ("favoritesOverflowHeader", "Sığmayan favoriler", "Favorites that didn’t fit"),
 ("noticeDismiss", "Kapat", "Dismiss"),
 ("launchAtLogin", "Girişte başlat", "Launch at login"),
 ("languageLabel", "Dil", "Language"),
 ("languageSystem", "Sistem dili", "System language"),
 ("languageTurkish", "Türkçe", "Türkçe"),
 ("languageEnglish", "English", "English"),
 ("languageRelaunchNote", "Dil değişikliği uygulama yeniden başlatılınca geçerli olur.", "The language change takes effect after Shotmori relaunches."),
 ("relaunchNow", "Şimdi Yeniden Başlat", "Relaunch Now"),
 ("resetDefaults", "Varsayılanlara dön", "Reset to defaults"),
 ("settingsAbout", "Hakkında", "About"),
 ("aboutHelpLink", "Yardım sayfası", "Help page"),
 ("aboutPrivacyLink", "Gizlilik politikası", "Privacy policy"),
 ("diagnostics", "Tanılama", "Diagnostics"),
 ("showLogFile", "Günlük dosyasını göster", "Show log file"),
 # Kurulum
 ("onboardingTitle", "Shotmori’yi tanıyın", "Meet Shotmori"),
 ("obWelcomeTitle", "Ekran görüntüsünden sonra, doğrudan devam edin.", "After the screenshot, just keep going."),
 ("obWelcomeBody", "macOS ile görüntüyü alın, Shotmori’de biriktirin, çalıştığınız uygulamaya sürükleyin.", "Take the image with macOS, collect it in Shotmori, drag it into the app you’re working in."),
 ("obFolderTitle", "Ekran görüntüleriniz nerede?", "Where are your screenshots?"),
 ("obFolderBody", "macOS’un ekran görüntülerini kaydettiği klasörü seçin; %@ › Seçenekler › “Şuraya Kaydet” altında görebilirsiniz. Dosyalar yerinde kalır.", "Choose the folder macOS saves screenshots to; you can see it in %@ › Options › Save to. Files stay where they are."),
 ("obAccumulateTitle", "Görüntüler tek rafta birikir.", "Images collect on one shelf."),
 ("obAccumulateBody", "En yeni görüntü başa gelir; son aktarımdan sonrakiler “Yeni” işaretlenir.", "The newest image comes first; images since your last hand-off are marked “New”."),
 ("obSampleShelfAX", "Örnek raf: dört ekran görüntüsü kartı, ilk ikisi yeni", "Sample shelf: four screenshot cards, the first two new"),
 ("obHotKeyTitle", "Rafı bir kısayolla çağırın.", "Call the shelf with a shortcut."),
 ("obHotKeyBody", "Raf imlecin yanında açılır; çalıştığınız uygulamanın odağını almaz.", "The shelf opens next to the pointer and never steals focus from the app you’re in."),
 ("obTryTitle", "İlk görüntünüzü deneyin.", "Try your first image."),
 ("obTryBody", "macOS ile bir alanın ekran görüntüsünü alın; kaydedilince rafta görünür.", "Take a screenshot of an area with macOS; it appears on the shelf once saved."),
 ("obTryWaiting", "Ekran görüntüsü bekleniyor…", "Waiting for a screenshot…"),
 ("obTryDetected", "Algılandı:", "Detected:"),
 ("obDragTitle", "Hazırsınız. Sürükleyip devam edin.", "You’re set. Drag and keep going."),
 ("obDragBody", "Kısayolla rafı açın, görüntüyü dosya kabul eden herhangi bir uygulamaya sürükleyin.", "Open the shelf with the shortcut and drag the image into any app that accepts files."),
 ("next", "Devam", "Continue"),
 ("back", "Geri", "Back"),
 ("finish", "Bitir", "Finish"),
 ("skip", "Atla", "Skip"),
 # OCR
 ("actionCopyText", "Metni kopyala", "Copy text"),
 ("ocrBusy", "Metin tanınıyor…", "Recognizing text…"),
 ("ocrCopied.one", "Metin kopyalandı (1 karakter)", "Text copied (1 character)"),
 ("ocrCopied.other", "Metin kopyalandı (%d karakter)", "Text copied (%d characters)"),
 ("ocrEmpty", "Görüntüde okunabilir metin bulunamadı", "No readable text found in the image"),
 ("ocrErrorUnreadable", "Görüntü açılamadı.", "The image couldn’t be opened."),
 ("ocrErrorFailed", "Metin tanıma başarısız: %@", "Text recognition failed: %@"),
 ("ocrLanguagesHelp", "Metin tanıma cihazda, Apple Vision ile yapılır; Türkçe ve İngilizce hedeflenir.", "Text recognition runs on-device with Apple Vision, targeting Turkish and English."),
 # Boyutlandır
 ("actionResize", "Boyutlandır…", "Resize…"),
 ("resizeOriginal", "Orijinal", "Original"),
 ("resizeWidth", "Genişlik", "Width"),
 ("resizeHeight", "Yükseklik", "Height"),
 ("resizeKeepAspect", "Oranı koru", "Keep ratio"),
 ("resizeOutputLabel", "Çıktı", "Output"),
 ("resizePNGNote", "PNG, saydamlığı korur.", "PNG keeps transparency."),
 ("resizePresets", "Hazır ölçüler", "Presets"),
 ("resizeSizeSection", "Ölçü", "Size"),
 ("resizeFormat", "Biçim", "Format"),
 ("resizeQuality", "Kalite", "Quality"),
 ("resizeEstimated", "Tahmini dosya boyutu", "Estimated file size"),
 ("resizeJPEGAlphaNote", "Saydam alanlar beyaz olur.", "Transparent areas become white."),
 ("resizeUpscaleNote", "Seçtiğiniz ölçü orijinalden büyük; görüntü büyütülecek.", "The chosen size is larger than the original; the image will be upscaled."),
 ("resizeOutputCopy", "Kopyala", "Copy"),
 ("resizeOutputSaveAs", "Farklı kaydet…", "Save as…"),
 ("resizeOutputAddToShelf", "Rafa ekle", "Add to shelf"),
 ("resizeOutputHelp", "Orijinal dosya değişmez; yeni bir türev üretilir.", "The original file is unchanged; a new derivative is created."),
 ("resizeDone", "Türev üretildi", "Derivative created"),
 ("resizeErrorUnreadable", "Görüntü okunamadı.", "The image couldn’t be read."),
 ("resizeErrorInvalidSize", "Genişlik ve yükseklik 1–16384 px arasında olmalı.", "Width and height must be between 1 and 16384 px."),
 ("resizeErrorEncode", "Görüntü kodlanamadı.", "The image couldn’t be encoded."),
 ("resizeErrorTooLarge", "Görüntü işlenemeyecek kadar büyük.", "The image is too large to process."),
 ("resizeWorking", "İşleniyor…", "Working…"),
 # Popover
 ("popoverCount.zero", "Raf boş", "Shelf is empty"),
 ("popoverCount.one", "Rafta 1 görüntü", "1 image on the shelf"),
 ("popoverCount.other", "Rafta %d görüntü", "%d images on the shelf"),
 ("popoverEmptyTitle", "İlk görüntünüzü bekliyor", "Waiting for your first image"),
 ("popoverEmptyBody", "macOS ile bir ekran görüntüsü alın.\nKaydedilince burada görünür.", "Take a screenshot with macOS.\nIt appears here once saved."),
 ("popoverShowShelf", "Rafı göster", "Show shelf"),
 ("popoverMore", "İşlemler", "Actions"),
 ("popoverMoreCount.one", "1 görüntü daha", "1 more image"),
 ("popoverMoreCount.other", "%d görüntü daha", "%d more images"),
 ("popoverNoSelection", "Bir görüntü seçin", "Select an image"),
 ("popoverTargetLast", "Son görüntü", "Latest image"),
 # Ayarlar (yeni düzen)
 ("tabShelf", "Raf", "Shelf"),
 ("tabQuickActions", "Hızlı işlemler", "Quick actions"),
 ("folderChange", "Değiştir…", "Change…"),
 ("folderReveal", "Finder’da göster", "Show in Finder"),
 ("folderFooter", "Dosyalar taşınmaz.", "Files are not moved."),
 ("quickActionsFooter", "Favoriler raf panelinde düğme olur.", "Favorites become buttons on the shelf panel."),
 ("folderHelp", "macOS’un ekran görüntülerini kaydettiği klasörü seçin. Shotmori yalnız sizin seçtiğiniz klasörlere erişir; dosyalar taşınmaz.", "Choose the folder where macOS saves screenshots. Shotmori only accesses folders you choose; files are not moved."),
 ("maxItemsHelp", "Sınır aşılınca en eski öğeler raftan kalkar; dosyalar kalır.", "Past the limit the oldest items leave the shelf; files stay."),
 ("maxItemsConfirmTitle.one", "1 görüntü listeden düşecek", "1 image will leave the list"),
 ("maxItemsConfirmTitle.other", "%d görüntü listeden düşecek", "%d images will leave the list"),
 ("maxItemsConfirmBody", "Dosyalar diskte kalır.", "Files stay on disk."),
 ("maxItemsConfirmButton", "Sınırı uygula", "Apply limit"),
 ("afterDropTitle", "Bırakma sonrası", "After dropping"),
 ("aboutVersion", "Sürüm", "Version"),
 ("aboutLog", "Tanılama günlüğü…", "Diagnostic log…"),
 ("openSourceLicenses", "Açık kaynak lisansları", "Open source licenses"),
 ("openSourceLicensesTitle", "Açık kaynak lisansları", "Open source licenses"),
 ("generalHotKeyHelp", "Rafı açar ya da kapatır; çalıştığınız uygulama önde kalır.", "Opens or closes the shelf; the app you are working in stays in front."),
 ("appliesToSelection", "Seçili görüntülere uygulanır", "Applies to the selected images"),
 ("appliesToSingle", "Tek görüntüye uygulanır", "Applies to a single image"),
 ("otherActionsSection", "Diğer işlemler", "Other actions"),
 ("dragToReorder", "Sürükleyerek sırala", "Drag to reorder"),
 ("favoriteOn", "favori", "favorite"),
 ("favoriteOff", "favori değil", "not a favorite"),
 ("choosePrompt", "Seç", "Choose"),
 ("copyHerePrompt", "Buraya Kopyala", "Copy Here"),
 ("noSuitableApp", "Uygun uygulama yok", "No suitable app"),
 ("copiedToast", "Kopyalandı", "Copied"),
 ("saveAsSameFileTitle", "Kaynak dosyanın üzerine yazılamaz", "The source file can’t be overwritten"),
 ("saveAsSameFileBody", "Seçtiğiniz hedef, kopyalanan dosyanın kendisi. Başka bir ad veya konum seçin; orijinal dosya değişmedi.", "The chosen destination is the file being copied. Pick another name or location; the original file was not changed."),
 ("saveAsChooseAnother", "Başka Yer Seç…", "Choose Another…"),
 ("saveAsSkippedTitle", "Bazı dosyalar kopyalanmadı", "Some files were not copied"),
 ("saveAsSkippedBody", "Kopyalanan: %d · atlanan: %d. Atlananlar aynı dosyaydı ya da hedefte aynı adla bir dosya zaten vardı; hiçbiri değiştirilmedi.", "Copied: %d · skipped: %d. Skipped files were the same file or a file with that name already existed at the destination; none were changed."),
 ("saveAsSkipReasonExists", "Hedefte aynı adla dosya var", "A file with that name already exists"),
 ("saveAsCopiedToast.one", "1 dosya kopyalandı", "1 file copied"),
 ("saveAsCopiedToast.other", "%d dosya kopyalandı", "%d files copied"),
 ("outputStaleTitle", "Düzenleme çıktı hazırlanırken değişti", "The edit changed while the output was being prepared"),
 ("outputStaleBody", "Çıktı üretilmedi; son hâli için işlemi yeniden başlatın.", "No output was produced; run the action again for the latest state."),
 ("outputErrorTitle", "Görüntü oluşturulamadı", "The image couldn’t be created"),
 ("resizeErrorWrite", "Türev dosyası yazılamadı.", "The derivative file couldn’t be written."),
 ("resizeErrorClipboard", "Panoya yazılamadı.", "Couldn’t write to the clipboard."),
 # Düzenle
 ("actionEdit", "Düzenle…", "Edit…"),
 ("editTitle", "Düzenle", "Edit"),
 ("editToolCrop", "Kırp", "Crop"),
 ("editToolRedact", "Gizle", "Redact"),
 ("editToolAX", "Araç", "Tool"),
 ("editAspect", "Oran", "Aspect"),
 ("editAspectFree", "Serbest", "Free"),
 ("editUndo", "Geri Al", "Undo"),
 ("editRedo", "Yinele", "Redo"),
 ("editZoomIn", "Yakınlaştır", "Zoom In"),
 ("editZoomOut", "Uzaklaştır", "Zoom Out"),
 ("editZoomAX", "Yakınlaştırma", "Zoom level"),
 ("editZoomFit", "Sığdır", "Fit"),
 ("editNoSelection", "Seçim yok", "No selection"),
 ("editRemoveRedaction", "Alanı Kaldır", "Remove Area"),
 ("editClearCrop", "Kırpmayı Kaldır", "Clear Crop"),
 ("editHintCrop", "Köşelerden ayarlayın. Oklarla 1 px, ⇧ + oklarla 10 px taşıyın.", "Adjust from the corners. Arrow keys move 1 px, ⇧ + arrows 10 px."),
 ("editHintRedact", "Gizlenen alanlar yeni kopyada opak siyaha dönüşür.", "Hidden areas become opaque black in the new copy."),
 ("editInfoCrop", "Kırpma: %@", "Crop: %@"),
 ("editInfoRedact.one", "1 gizleme alanı · Seçili: %@", "1 hidden area · Selected: %@"),
 ("editInfoRedact.other", "%d gizleme alanı · Seçili: %@", "%d hidden areas · Selected: %@"),
 ("editInfoRedactCount.one", "1 gizleme alanı", "1 hidden area"),
 ("editInfoRedactCount.other", "%d gizleme alanı", "%d hidden areas"),
 ("editInfoNoCrop", "Kırpma yok", "No crop"),
 ("editFileInfo", "%d × %d px · %@", "%d × %d px · %@"),
 ("editFormatLabel", "Çıktı biçimi", "Output format"),
 ("editOriginalHelp", "Orijinal dosya değişmez; sonuç yeni bir kopyadır.", "The original file is not changed; the result is a new copy."),
 ("outputErrorBody", "Orijinal dosya değişmedi. Daha küçük bir çıktı deneyin veya farklı bir görüntü açın.", "The original file was not changed. Try a smaller output or open a different image."),
 ("outputMenuLabel", "Diğer çıktılar", "More outputs"),
 ("zoomPercent", "%%%d", "%d%%"),
 ("editOutputHelp", "Orijinal değişmez. Çıktı düzleştirilir: gizlenen alanların piksel verisi dosyada bulunmaz.", "The original is unchanged. The output is flattened: pixel data of hidden areas is not in the file."),
 ("editUnsavedTitle", "Düzenlemeler kaydedilmedi", "Edits were not saved"),
 ("editUnsavedBody", "Bu pencereyi kapatırsanız kırpma ve gizleme değişiklikleri atılır. Orijinal dosya değişmez.", "Closing this window discards the crop and hide changes. The original file does not change."),
 ("editDiscard", "Değişiklikleri at", "Discard changes"),
 ("editKeepEditing", "Düzenlemeye dön", "Keep editing"),
 ("editErrorSourceMissing", "Kaynak dosya artık diskte yok; çıktı üretilemedi.", "The source file is no longer on disk; no output was created."),
 ("editDone", "Düzenlenmiş kopya üretildi", "Edited copy created"),
 ("editWorking", "Çıktı hazırlanıyor…", "Preparing output…"),
 ("editedBadge", "düzenlendi", "edited"),
 ("editHEIFNote", "HEIF/HDR kaynak PNG'ye dönüştürülür; genişletilmiş renk aralığı korunmaz.", "HEIF/HDR sources are converted to PNG; the extended color range is not preserved."),
 ("editSizeLabel", "%d × %d px", "%d × %d px"),
 # Otomasyon (URL şeması, Kestirmeler, Servisler, Denetim Merkezi) ve dış giriş yolları
 ("settingsAutomationSection", "Otomasyon", "Automation"),
 ("urlSchemeToggle", "URL şemasına izin ver", "Allow URL scheme"),
 ("urlSchemeHelp", "Diğer uygulamalar shotmori:// komutlarıyla rafı gösterebilir ve panodan rafa ekleyebilir. Dosya yolu kabul edilmez.", "Other apps can show the shelf and add from the clipboard with shotmori:// commands. File paths are never accepted."),
 ("urlSchemeAskTitle", "shotmori:// bağlantılarına izin verilsin mi?", "Allow shotmori:// links?"),
 ("urlSchemeAskBody", "İzin verirseniz diğer uygulamalar shotmori:// bağlantılarıyla rafı gösterebilir ve panodan rafa ekleyebilir. Dosya yolu kabul edilmez. Tercihi Ayarlar › Genel › Otomasyon'dan değiştirebilirsiniz.", "If you allow them, other apps can show the shelf and add from the clipboard with shotmori:// links. File paths are never accepted. You can change this later in Settings › General › Automation."),
 ("urlSchemeDeny", "İzin verme", "Don't Allow"),
 ("urlSchemeAllow", "İzin ver", "Allow"),
 ("openShortcuts", "Kestirmeler'de aç", "Open in Shortcuts"),
 ("openShortcutsHelp", "Shotmori eylemleri Kestirmeler'de görünür: rafa ekle, raftan al, panodan ekle, son görüntüyü kopyala, rafı göster/gizle, rafı temizle, buluta yükle.", "Shotmori actions appear in Shortcuts: add to shelf, get from shelf, add clipboard, copy latest, show/hide shelf, clear shelf, upload to cloud."),
 ("servicesInfo", "Finder › sağ tık › Servisler › Shotmori rafına ekle", "Finder › right-click › Services › Add to Shotmori Shelf"),
 ("servicesInfoHelp", "Kısayol Sistem Ayarları › Klavye › Klavye Kestirmeleri › Servisler'den atanır.", "Assign a shortcut in System Settings › Keyboard › Keyboard Shortcuts › Services."),
 ("controlCenterInfo", "Denetim Merkezi düğmeleri", "Control Center buttons"),
 ("controlCenterInfoHelp", "macOS 26 ve sonrasında Denetim Merkezi'ne ya da menü çubuğuna Rafı göster, Panodan ekle ve Son görüntüyü kopyala düğmeleri eklenebilir.", "On macOS 26 and later, add Show Shelf, Add Clipboard and Copy Latest buttons to Control Center or the menu bar."),
 ("inboundAdded.one", "1 görüntü rafa eklendi", "1 image added to the shelf"),
 ("inboundAdded.other", "%d görüntü rafa eklendi", "%d images added to the shelf"),
 ("inboundAlready", "Zaten rafta", "Already on the shelf"),
 ("inboundRejected", "Yalnız görüntü dosyaları eklenebilir", "Only image files can be added"),
 ("inboundLimit", "En çok 20 görüntü, her biri 50 MB'tan küçük", "Up to 20 images, each under 50 MB"),
 ("inboundAddedLimited.one", "1 görüntü eklendi; bir seferde en çok 20 görüntü eklenebilir", "1 image added; you can add up to 20 at a time"),
 ("inboundAddedLimited.other", "%d görüntü eklendi; bir seferde en çok 20 görüntü eklenebilir", "%d images added; you can add up to 20 at a time"),
 ("inboundTooLarge", "Görüntü 50 MB'tan büyük; daha küçük bir dosya seçin", "The image is larger than 50 MB; choose a smaller file"),
 # App Intents (Kestirmeler / Spotlight)
 ("intentAddTitle", "Rafa ekle", "Add to Shelf"),
 ("intentAddDesc", "Görüntüleri Shotmori rafına ekler; dosyalar kopyalanır, özgün dosyaya dokunulmaz.", "Adds images to the Shotmori shelf; files are copied, originals are untouched."),
 ("intentGetTitle", "Raftan görüntüleri al", "Get Images from Shelf"),
 ("intentGetNewTitle", "Yeni görüntüleri al", "Get New Images"),
 ("intentGetDesc", "Raftaki görüntüleri dosya olarak verir. “Yalnız yeni olanlar” açıkken verilenler teslim edilmiş sayılır.", "Returns shelf images as files. With “Only new ones”, returned images count as handed off."),
 ("intentGetNewDesc", "Son teslimden sonra rafa gelen görüntüleri dosya olarak verir; verilenler teslim edilmiş sayılır.", "Returns images added to the shelf since the last hand-off as files; returned images count as handed off."),
 ("intentClipboardTitle", "Panodan rafa ekle", "Add Clipboard to Shelf"),
 ("intentClipboardDesc", "Panodaki görseli PNG olarak rafa ekler.", "Adds the clipboard image to the shelf as PNG."),
 ("intentCopyLatestTitle", "Son görüntüyü kopyala", "Copy Latest Image"),
 ("intentCopyLatestDesc", "Raftaki en yeni görüntüyü panoya kopyalar.", "Copies the newest shelf image to the clipboard."),
 ("intentShowTitle", "Rafı göster", "Show Shelf"),
 ("intentHideTitle", "Rafı gizle", "Hide Shelf"),
 ("intentClearTitle", "Rafı temizle", "Clear Shelf"),
 ("intentClearDesc", "Rafı listeden boşaltır; dosyalar diskte kalır.", "Empties the shelf list; files stay on disk."),
 # Konumsal yer tutucu: sıra dillerde farklı (%1$@ raf adı, %2$d sayı). Raf adı çekimsiz konumda ("Raf 1" → "Raf 1 rafındaki" olmasın).
 ("intentClearConfirm.one", "“%1$@” içindeki 1 görüntü listeden kaldırılsın mı? Dosyalar diskte kalır.", "Remove 1 image from “%1$@”? Files stay on disk."),
 ("intentClearConfirm.other", "“%1$@” içindeki %2$d görüntü listeden kaldırılsın mı? Dosyalar diskte kalır.", "Remove %2$d images from “%1$@”? Files stay on disk."),
 ("intentUploadTitle", "Buluta yükle", "Upload to Cloud"),
 ("intentUploadDesc", "Görüntüleri kendi Google Drive ya da S3 hesabınıza yükler ve linklerini döndürür.", "Uploads images to your own Google Drive or S3 and returns the links."),
 ("paramFiles", "Görüntüler", "Images"),
 ("paramShelf", "Raf", "Shelf"),
 ("paramOnlyNew", "Yalnız yeni olanlar", "Only new ones"),
 ("paramLimit", "En çok", "Limit"),
 ("paramProvider", "Hizmet", "Service"),
 ("paramCopyLink", "Linki panoya kopyala", "Copy link to clipboard"),
 ("paramItems", "Raf görüntüleri", "Shelf images"),
 ("entityShot", "Raf görüntüsü", "Shelf Image"),
 ("entityShelf", "Raf", "Shelf"),
 ("entityNew", "Yeni", "New"),
 ("entityFileName", "Dosya adı", "File Name"),
 ("entityCapturedAt", "Çekim tarihi", "Date Taken"),
 ("entityCloudLink", "Bulut linki", "Cloud Link"),
 ("entityItemCount", "Görüntü sayısı", "Image Count"),
 ("intentErrNotReady", "Shotmori açılıyor; birkaç saniye sonra yeniden deneyin", "Shotmori is still starting; try again in a few seconds"),
 ("intentErrNoImages", "Görüntü verilmedi", "No images were given"),
 ("intentErrShelfNotFound", "Raf bulunamadı", "Shelf not found"),
 ("intentErrFileRejected", "Yalnız görüntü dosyaları eklenebilir", "Only image files can be added"),
 ("intentErrTooMany", "Bir seferde en çok 20 görüntü eklenebilir; daha az görüntü seçin", "You can add up to 20 images at a time; choose fewer"),
 ("intentErrNotConnected", "%@ bağlı değil; Ayarlar › Bulut'tan bağlayın", "%@ isn't connected; connect it in Settings › Cloud"),
 ("intentErrUploadRunning", "Yükleme sürüyor; link hazır olunca Son yüklemeler'de", "Upload still running; the link will be in Recent Uploads"),
 ("intentErrClipboardEmpty", "Panoda görsel yok", "No image on the clipboard"),
 # Denetim Merkezi komutları (W tablosunda da aynı değerlerle)
 ("cmdShowTitle", "Rafı göster", "Show Shelf"),
 ("cmdClipboardTitle", "Panodan ekle", "Add Clipboard"),
 ("cmdCopyLatestTitle", "Son görüntüyü kopyala", "Copy Latest"),
]

# Servisler menü adı (tablo I): (Info.plist NSMenuItem varsayılanı = İngilizce anahtar, Türkçe) → {tr,en}.lproj/ServicesMenu.strings
I = [
 ("Add to Shotmori Shelf", "Shotmori rafına ekle"),
]

# App Shortcuts ifadeleri (tablo A): (İngilizce ifade = anahtar, Türkçe) → {tr,en}.lproj/AppShortcuts.strings. `${applicationName}` korunur.
A = [
 ("Add images to ${applicationName}", "Görüntüleri ${applicationName} rafına ekle"),
 ("Add to ${applicationName} shelf", "${applicationName} rafına ekle"),
 ("Get images from ${applicationName}", "${applicationName} rafından görüntüleri al"),
 ("Get new images from ${applicationName}", "${applicationName} rafındaki yeni görüntüleri al"),
 ("Add clipboard to ${applicationName}", "Panoyu ${applicationName} rafına ekle"),
 ("Copy latest image from ${applicationName}", "${applicationName} son görüntüyü kopyala"),
 ("Show ${applicationName} shelf", "${applicationName} rafını göster"),
 ("Hide ${applicationName} shelf", "${applicationName} rafını gizle"),
 ("Clear ${applicationName} shelf", "${applicationName} rafını temizle"),
 ("Upload with ${applicationName}", "${applicationName} ile buluta yükle"),
]

# App Intents parametre özetleri (tablo P): (İngilizce özet = anahtar, Türkçe) → {tr,en}.lproj/Localizable.strings sonuna.
# Anahtar `Summary("…")` metniyle birebir aynıdır; `${…}` yer tutucuları iki dilde aynı kümeyi taşır.
P = [
 # Raf adı/yer tutucusu ("Raf", "Raf 1") çekimsiz konumda: "Raf rafını" gibi çift isim çıkmasın.
 ("Add ${files} to ${shelf}", "${files} ekle → ${shelf}"),
 ("Get ${limit} images from ${shelf}", "${shelf} içinden en çok ${limit} görüntü al"),
 ("Get ${limit} new images from ${shelf}", "${shelf} içinden en çok ${limit} yeni görüntü al"),
 ("Show ${shelf}", "Göster: ${shelf}"),
 ("Clear ${shelf}", "Temizle: ${shelf}"),
 ("Upload ${files} to ${provider}", "${files} → ${provider} hesabına yükle"),
]

# Widget uzantısı metinleri (tablo W): → ShotmoriWidgets/{tr,en}.lproj/Localizable.strings + Shared/WStrings.swift (enum WS).
# Ana tabloyla yalnız üç komut başlığı ortak olabilir (değerleri aynı).
W = [
 ("widgetRecentTitle", "Son görüntüler", "Recent Images"),
 ("widgetRecentDesc", "Rafınızdaki son görüntüler ve yeni sayısı.", "Your latest shelf images and the new count."),
 ("widgetEmpty", "Görüntüleriniz burada birikir", "Your images collect here"),
 ("widgetNew.one", "1 yeni", "1 new"),
 ("widgetNew.other", "%d yeni", "%d new"),
 ("widgetTotal.one", "1 görüntü", "1 image"),
 ("widgetTotal.other", "%d görüntü", "%d images"),
 ("cmdShowTitle", "Rafı göster", "Show Shelf"),
 ("cmdClipboardTitle", "Panodan ekle", "Add Clipboard"),
 ("cmdCopyLatestTitle", "Son görüntüyü kopyala", "Copy Latest"),
]

# Bulut metinleri: ayrı `Cloud` tablosu (tr/en.lproj/Cloud.strings). Yalnız `SHOTMORI_CLOUD` (Debug) derlemesinde kullanılır;
# Release'te Cloud.strings pakete girmez (project.yml EXCLUDED_SOURCE_FILE_NAMES) ve Swift üyeleri derlenmez.
C = [
 ("cloudErrNotConnected", "Bu servis bağlı değil. Ayarlar › Bulut’tan bağlayın.", "This service isn’t connected. Connect it in Settings › Cloud."),
 ("cloudErrUnauthorized", "Oturum geçersiz. Yeniden giriş yapın.", "The session is no longer valid. Sign in again."),
 ("cloudErrForbidden", "Erişim reddedildi (yetki veya kota).", "Access denied (permission or quota)."),
 ("cloudErrNotFound", "Buluttaki kopya bulunamadı.", "The cloud copy wasn’t found."),
 ("cloudErrNetwork", "Ağ hatası: %@", "Network error: %@"),
 ("cloudErrServer", "Sunucu hatası (%d). %@", "Server error (%d). %@"),
 ("cloudErrVerify", "Yüklenen kopya yerel dosyayla eşleşmedi; yerel dosyaya dokunulmadı.", "The uploaded copy didn’t match the local file; the local file was left alone."),
 ("cloudErrFileUnreadable", "Dosya okunamadı. Erişim izni gerekebilir ya da dosya henüz iCloud’dan indirilmemiş olabilir.", "Couldn’t read the file. It may need access permission, or it may not be downloaded from iCloud yet."),
 ("cloudErrServerCode", "Sunucu hatası (%d).", "Server error (%d)."),
 ("cloudErrInvalidResponse", "Sunucudan beklenmeyen bir yanıt geldi. Biraz sonra yeniden deneyin.", "The server sent an unexpected response. Try again in a moment."),
 ("cloudErrCancelled", "İşlem iptal edildi ya da zaman aşımına uğradı.", "The operation was cancelled or timed out."),
 ("cloudErrAuthDenied", "Google girişi iptal edildi ya da izin verilmedi.", "Google sign-in was cancelled or access wasn’t granted."),
 ("cloudErrNoRefreshToken", "Google oturumu tamamlanmadı. Yeniden giriş yapın.", "Google didn’t complete the sign-in. Sign in again."),
 ("cloudErrKeychain", "Bilgiler Anahtar Zinciri’ne kaydedilemedi (hata %d).", "Couldn’t save to your Keychain (error %d)."),
 ("cloudErrBucketNotFound", "Bucket bulunamadı. Adını ve bölgesini denetleyin.", "Bucket not found. Check its name and region."),
 ("cloudErrBadCredentials", "Erişim anahtarı ya da gizli anahtar geçersiz.", "The access key or secret key isn’t valid."),
 ("cloudErrRateLimited", "Sunucu şu an çok fazla istek alıyor. Biraz sonra yeniden deneyin.", "The server is receiving too many requests. Try again in a moment."),
 ("cloudErrQuotaExceeded", "Bulut depolama alanınız dolu.", "Your cloud storage is full."),
 ("s3PresetOther", "Diğer (S3 uyumlu)", "Other (S3-compatible)"),
 ("actionUploadDrive", "Drive’a yükle", "Upload to Drive"),
 ("actionUploadS3", "S3’e yükle", "Upload to S3"),
 ("cloudMenu", "Bulut", "Cloud"),
 ("cloudCopyLink", "Linki kopyala", "Copy link"),
 ("cloudOpenLink", "Tarayıcıda aç", "Open in browser"),
 ("cloudAccessMenu", "Erişimi değiştir", "Change access"),
 ("cloudDelete", "Buluttan sil…", "Delete from cloud…"),
 ("cloudDeleteTitle", "Buluttaki kopya silinsin mi?", "Delete the cloud copy?"),
 ("cloudDeleteBody", "%@ üzerindeki kopya ve linki kaldırılır. Yerel dosyaya dokunulmaz.", "The copy on %@ and its link are removed. The local file is left alone."),
 ("cloudDeleteBodyLocalTrashed", "%@ üzerindeki kopya ve linki kaldırılır. Yerel dosya yedekten sonra Çöp’e taşınmıştı; Çöp boşaltıldıysa bu, görüntünün tek kopyası olabilir.", "The copy on %@ and its link are removed. The local file was moved to the Trash after backup; if the Trash has been emptied, this may be the only copy of the image."),
 ("cloudDeleteButton", "Buluttan sil", "Delete from cloud"),
 ("cloudNotConnected", "%@ bağlı değil", "%@ is not connected"),
 ("cloudQueued", "Yükleme kuyruğa alındı", "Upload queued"),
 ("cloudUploading", "Yükleniyor: %@", "Uploading: %@"),
 ("cloudLinkCopied", "Yüklendi · link panoda", "Uploaded · link copied"),
 ("cloudUploadedNoLink", "Yüklendi", "Uploaded"),
 ("cloudFailed", "Yükleme başarısız: %@", "Upload failed: %@"),
 ("cloudRetry", "Yeniden dene", "Retry"),
 ("cloudAccessAnyone", "Bağlantıya sahip herkes", "Anyone with the link"),
 ("cloudAccessOwner", "Yalnızca ben", "Only me"),
 ("cloudAccessPublic", "Herkese açık nesne", "Public object"),
 ("cloudAccessPresigned", "İmzalı link (%@)", "Signed link (%@)"),
 ("cloudAccessChanged", "Erişim güncellendi · link panoda", "Access updated · link copied"),
 ("cloudAccessChangeFailed", "Erişim değiştirilemedi: %@", "Couldn’t change access: %@"),
 ("cloudDeleteFailed", "Buluttan silinemedi: %@", "Couldn’t delete from the cloud: %@"),
 ("cloudRecentUploads", "Son yüklemeler", "Recent uploads"),
 ("cloudRecentEmpty", "Henüz yükleme yok", "No uploads yet"),
 ("cloudRemoveFromList", "Listeden kaldır", "Remove from list"),
 ("cloudBadgePending", "Yükleme bekliyor", "Upload pending"),
 ("cloudBadgeUploaded", "%@ üzerinde", "On %@"),
 ("cloudBadgeFailed", "Yükleme başarısız", "Upload failed"),
 ("cloudLocalTrashed", "Yerel kopya Çöp’te · bulutta", "Local copy in Trash · in cloud"),
 ("cloudBackupQueued", "Yedek kuyruğa alındı", "Backup queued"),
 ("cloudTrashedAfterBackup", "Yedeklendi ve yerel kopya Çöp’e taşındı", "Backed up; local copy moved to Trash"),
 ("tabCloud", "Bulut", "Cloud"),
 ("cloudIntro", "Yükle ve paylaş ile otomatik yedek ayrı özelliklerdir. Dosyalarınız yerinde kalır; bulut bir kopyadır.", "Upload-and-share and automatic backup are separate features. Your files stay in place; the cloud holds a copy."),
 ("cloudAccountsSection", "Hesaplar", "Accounts"),
 ("cloudAccountsFooter", "Dosyalar kendi hesabınıza gider; Shotmori’nin sunucusu yoktur. Oturum bilgileri Anahtar Zinciri’nde kalır.", "Files go to your own account; Shotmori has no server. Credentials stay in your Keychain."),
 ("cloudSharingSection", "Paylaşım", "Sharing"),
 ("cloudSetUp", "Ayarla…", "Set up…"),
 ("cloudEdit", "Düzenle…", "Edit…"),
 ("cloudAdvancedButton", "Gelişmiş…", "Advanced…"),
 ("cloudDriveLinkAccess", "Drive link gizliliği", "Drive link privacy"),
 ("cloudS3LinkAccess", "S3 link gizliliği", "S3 link privacy"),
 ("cloudDriveTemplate", "Drive klasör şablonu", "Drive folder template"),
 ("cloudS3Template", "S3 yol şablonu", "S3 path template"),
 ("s3SheetTitle", "S3 / S3 uyumlu hesap", "S3 / S3-compatible account"),
 ("cloudDriveAdvancedTitle", "Kendi Google OAuth istemcin", "Your own Google OAuth client"),
 ("cloudS3Subtitle", "Amazon S3, Cloudflare R2, MinIO, Backblaze B2…", "Amazon S3, Cloudflare R2, MinIO, Backblaze B2…"),
 ("cloudDriveSection", "Google Drive", "Google Drive"),
 ("cloudS3Section", "S3 / S3 uyumlu", "S3 / S3-compatible"),
 ("cloudCommonSection", "Ortak", "Shared settings"),
 ("cloudBackupSection", "Otomatik yedek", "Automatic backup"),
 ("cloudClientID", "OAuth istemci kimliği", "OAuth client ID"),
 ("cloudClientSecret", "İstemci gizli anahtarı", "Client secret"),
 ("cloudClientHelp", "Google Cloud Console › Kimlik bilgileri › OAuth istemci kimliği › tür “Masaüstü uygulaması”. Drive API’yi etkinleştirin; OAuth onay ekranında kendi hesabınızı test kullanıcısı olarak ekleyin.", "Google Cloud Console › Credentials › OAuth client ID › type “Desktop app”. Enable the Drive API and add your own account as a test user on the consent screen."),
 ("cloudSignIn", "Google ile giriş yap", "Sign in with Google"),
 ("cloudSignInHint", "Tarayıcıda Google hesabınızı onaylayın. Shotmori yalnız kendi yüklediği dosyalara erişir; oturum bilgisi Anahtar Zinciri’nde kalır.", "Approve your Google account in the browser. Shotmori can only access files it uploaded; the sign-in stays in your Keychain."),
 ("cloudAdvancedClient", "Gelişmiş: kendi Google OAuth istemcin", "Advanced: your own Google OAuth client"),
 ("cloudAdvancedClientHelp", "Boş bırakılırsa Shotmori’nin gömülü istemcisi kullanılır. Kendi Google Cloud projenizi kullanmak için “Masaüstü uygulaması” türü istemci kimliğini girin.", "Leave empty to use Shotmori’s built-in client. To use your own Google Cloud project, enter a “Desktop app” client ID."),
 ("cloudSignOut", "Çıkış yap", "Sign out"),
 ("cloudConnected", "Bağlı", "Connected"),
 ("cloudDisconnected", "Bağlı değil", "Not connected"),
 ("cloudSigningIn", "Tarayıcıda giriş bekleniyor…", "Waiting for sign-in in the browser…"),
 ("cloudDefaultAccess", "Varsayılan link gizliliği", "Default link privacy"),
 ("cloudFolderTemplate", "Klasör / yol şablonu", "Folder / path template"),
 ("cloudTemplateHelp", "Jetonlar: {yyyy} {MM} {dd} {name} {ext}", "Tokens: {yyyy} {MM} {dd} {name} {ext}"),
 ("cloudTest", "Bağlantıyı sına", "Test connection"),
 ("cloudTestOK", "Bağlantı çalışıyor", "Connection works"),
 ("cloudTesting", "Sınanıyor…", "Testing…"),
 ("s3Preset", "Sağlayıcı", "Provider"),
 ("s3Endpoint", "Uç nokta", "Endpoint"),
 ("s3EndpointPromptR2", "https://<hesap-kimliği>.r2.cloudflarestorage.com", "https://<account-id>.r2.cloudflarestorage.com"),
 ("s3EndpointPromptB2", "https://s3.<bölge>.backblazeb2.com", "https://s3.<region>.backblazeb2.com"),
 ("s3Region", "Bölge", "Region"),
 ("s3Bucket", "Bucket", "Bucket"),
 ("s3AccessKey", "Erişim anahtarı", "Access key"),
 ("s3SecretKey", "Gizli anahtar", "Secret key"),
 ("s3SecretStored", "Gizli anahtar kayıtlı (Anahtar Zinciri)", "Secret key stored (Keychain)"),
 ("s3PathStyle", "Yol stili adresleme", "Path-style addressing"),
 ("s3PresignDuration", "İmzalı link süresi", "Signed link lifetime"),
 ("s3Save", "Kaydet", "Save"),
 ("s3Clear", "Bilgileri kaldır", "Remove credentials"),
 ("cloudLinkFormat", "Link biçimi", "Link format"),
 ("cloudLinkFormatURL", "Düz URL", "Plain URL"),
 ("cloudLinkFormatMarkdown", "Markdown görsel", "Markdown image"),
 ("cloudLinkFormatHTML", "HTML <img>", "HTML <img>"),
 ("cloudBackupTarget", "Yeni ekran görüntülerini yedekle", "Back up new screenshots to"),
 ("cloudBackupOff", "Kapalı", "Off"),
 ("cloudBackupDerivatives", "Düzenlenmiş/boyutlandırılmış kopyaları da yedekle", "Also back up edited/resized copies"),
 ("cloudTrashAfterBackup", "Yükleme doğrulanınca yerel dosyayı Çöp’e taşı", "Move the local file to the Trash once the upload is verified"),
 ("cloudTrashAfterBackupHelp", "Yalnız otomatik yedek için. Sunucudaki kopya boyut ve sağlamayla doğrulanmadan dosyaya dokunulmaz; dosya Çöp’e taşınır, kalıcı silinmez. Rafta “bulutta” olarak kalır ve linki sürüklenir.", "Automatic backup only. The file isn’t touched until the server copy is verified by size and checksum; it goes to the Trash, not permanently deleted. It stays on the shelf as “in cloud” and its link can be dragged."),
 ("cloudQueueStatus", "Kuyruk: %d bekliyor", "Queue: %d pending"),
 ("cloudAuthDone", "Giriş tamamlandı. Bu sekmeyi kapatıp Shotmori’ye dönebilirsiniz.", "Sign-in complete. You can close this tab and return to Shotmori."),
 ("cloudAuthDenied", "Giriş iptal edildi. Shotmori’ye dönebilirsiniz.", "Sign-in was cancelled. You can return to Shotmori."),
 ("cloudAuthStateMismatch", "Bu istek doğrulanamadı. Shotmori’den girişi yeniden başlatın.", "This request couldn’t be verified. Start the sign-in again from Shotmori."),
]

SWIFT = '''import Foundation

/// Tüm kullanıcı metinleri tek yerde. Kaynak: en.lproj / tr.lproj Localizable.strings (geliştirme ve yedek dili İngilizce);
/// `#if SHOTMORI_CLOUD` üyeleri ayrı Cloud.strings tablosundan (bulutlu derleme: Debug ve Release 1.0).
/// Üreteç: scripts/gen_strings.py — anahtar adları Swift üye adlarıyla aynıdır.
enum S {
    static let appName = "Shotmori"
    // Panel
    static let shelfTitle = L("shelfTitle")
    static let hideShelf = L("hideShelf")
    static func shelfDefaultName(_ n: Int) -> String { F("shelfDefaultName", n) }
    static let shelfPin = L("shelfPin")
    static let shelfPinHelp = L("shelfPinHelp")
    static let shelfPinOn = L("shelfPinOn")
    static let shelfPinOff = L("shelfPinOff")
    static let shelfTabNew = L("shelfTabNew")
    static let shelfTabNewHelp = L("shelfTabNewHelp")
    static let shelfRename = L("shelfRename")
    static let shelfClose = L("shelfClose")
    static let shelfDetach = L("shelfDetach")
    static let shelfReattach = L("shelfReattach")
    static func shelfCloseTitle(_ name: String) -> String { F("shelfCloseTitle", name) }
    static func shelfCloseBody(_ n: Int) -> String { n == 1 ? L("shelfCloseBody.one") : F("shelfCloseBody.other", n) }
    static func shelfCloseMove(_ name: String) -> String { F("shelfCloseMove", name) }
    static let shelfCloseDrop = L("shelfCloseDrop")
    static let actionMoveToShelf = L("actionMoveToShelf")
    static let actionMoveToShelfHelp = L("actionMoveToShelfHelp")
    static let moveToNewShelf = L("moveToNewShelf")
    static func movedToShelfToast(_ n: Int, _ name: String) -> String { n == 1 ? F("movedToShelfToast.one", name) : F("movedToShelfToast.other", n, name) }
    static func moveTrimmedToast(_ n: Int) -> String { n == 1 ? L("moveTrimmedToast.one") : F("moveTrimmedToast.other", n) }
    static func shelfTabAX(_ name: String, _ n: Int) -> String { n == 1 ? F("shelfTabAX.one", name) : F("shelfTabAX.other", name, n) }
    static let shelfTabSelectedAX = L("shelfTabSelectedAX")
    static func shelfSwitchedAX(_ name: String) -> String { F("shelfSwitchedAX", name) }
    static let shelfInWindowBadge = L("shelfInWindowBadge")
    static let popoverShelfPicker = L("popoverShelfPicker")
    static func imageCount(_ n: Int) -> String { n == 1 ? L("imageCount.one") : F("imageCount.other", n) }
    static func selectedCount(_ n: Int) -> String { n == 0 ? L("selectedCount.zero") : (n == 1 ? L("selectedCount.one") : F("selectedCount.other", n)) }
    static let newBadge = L("newBadge")
    static let editedCaption = L("editedCaption")
    static let copyShort = L("copyShort")
    static func stripSelectedCount(_ n: Int) -> String { F("stripSelectedCount", n) }
    static func copyShortCount(_ n: Int) -> String { n > 1 ? F("copyShortCount", n) : L("copyShort") }
    static let quitShort = L("quitShort")
    static func newCount(_ n: Int) -> String { n == 1 ? L("newCount.one") : F("newCount.other", n) }
    static let emptyShelfTitle = L("emptyShelfTitle")
    static let emptyShelfBody = L("emptyShelfBody")
    static let folderMissing = L("folderMissing")
    static let missingFile = L("missingFile")
    static let removeHint = L("removeHint")
    static let removeAXLabel = L("removeAXLabel")
    static let removeAXHelp = L("removeAXHelp")
    static func actionRemoveSelected(_ n: Int) -> String { F("actionRemoveSelected", n) }
    static func trashConfirmList(_ names: [String]) -> String {
        let shown = names.prefix(6).map { "• " + $0 }.joined(separator: "\\n")
        let more = names.count > 6 ? "\\n" + F("trashConfirmMore", names.count - 6) : ""
        return shown + more
    }
    static let moreActions = L("moreActions")
    static let actionsMenuShortcutHelp = L("actionsMenuShortcutHelp")
    // Eylemler
    static let actionCopyImage = L("actionCopyImage")
    static func actionCopyImages(_ n: Int) -> String { n > 1 ? F("actionCopyImages", n) : L("actionCopyImage") }
    static let actionOpen = L("actionOpen")
    static let actionOpenWith = L("actionOpenWith")
    static let actionRevealInFinder = L("actionRevealInFinder")
    static let actionSaveAs = L("actionSaveAs")
    static let actionShare = L("actionShare")
    static let actionRemoveFromShelf = L("actionRemoveFromShelf")
    static let actionClearShelf = L("actionClearShelf")
    static let scopeWholeShelf = L("scopeWholeShelf")
    static let scopeSingleImage = L("scopeSingleImage")
    static let actionMoveToTrash = L("actionMoveToTrash")
    static func actionMoveToTrashMany(_ n: Int) -> String { F("actionMoveToTrashMany", n) }
    static let actionNewGroup = L("actionNewGroup")
    static let actionNewGroupHelp = L("actionNewGroupHelp")
    static let actionEndGroup = L("actionEndGroup")
    static let reasonImagesOnly = L("reasonImagesOnly")
    static let reasonSingleOnly = L("reasonSingleOnly")
    static let reasonNoSelection = L("reasonNoSelection")
    static let reasonMissing = L("reasonMissing")
    static let trashConfirmTitle = L("trashConfirmTitle")
    static func trashConfirmTitleMany(_ n: Int) -> String { F("trashConfirmTitleMany", n) }
    static func trashConfirmBody(_ n: Int) -> String { n == 1 ? L("trashConfirmBody.one") : F("trashConfirmBody.other", n) }
    static let trashConfirmButton = L("trashConfirmButton")
    static func trashConfirmButtonMany(_ n: Int) -> String { n > 1 ? F("trashConfirmButtonMany", n) : L("trashConfirmButton") }
    static let cancel = L("cancel")
    static let ok = L("ok")
    static let clearShelfBody = L("clearShelfBody")
    static func clearShelfTitle(_ n: Int) -> String { n == 1 ? L("clearShelfTitle.one") : F("clearShelfTitle.other", n) }
    static let clearShelfButton = L("clearShelfButton")
    static let permLocal = L("permLocal")
    static let permSystemShare = L("permSystemShare")
    static let permExternal = L("permExternal")
    // Menü
    static let menuShowShelf = L("menuShowShelf")
    static let menuCopyLast = L("menuCopyLast")
    static let menuAddFromClipboard = L("menuAddFromClipboard")
    static let menuActions = L("menuActions")
    static let menuSettings = L("menuSettings")
    static let menuChooseFolder = L("menuChooseFolder")
    static let folderSaveFailed = L("folderSaveFailed")
    static let relaunchFailed = L("relaunchFailed")
    static let emptyNoFolderBody = L("emptyNoFolderBody")
    static let menuHelp = L("menuHelp")
    static let menuRerunSetup = L("menuRerunSetup")
    static let menuShowLog = L("menuShowLog")
    static let menuAbout = L("menuAbout")
    static let menuQuit = L("menuQuit")
    static let menuHideApp = L("menuHideApp")
    static let menuEdit = L("menuEdit")
    static let menuUndo = L("menuUndo")
    static let menuRedo = L("menuRedo")
    static let menuCut = L("menuCut")
    static let menuCopy = L("menuCopy")
    static let menuPaste = L("menuPaste")
    static let menuSelectAll = L("menuSelectAll")
    static let menuWindow = L("menuWindow")
    static let menuClose = L("menuClose")
    static let menuMinimize = L("menuMinimize")
    static let clipboardNoImage = L("clipboardNoImage")
    static func clipboardFileName(_ date: String) -> String { F("clipboardFileName", date) }
    static let preparingImage = L("preparingImage")
    // Ayarlar
    static let settingsTitle = L("settingsTitle")
    static let settingsStartupSection = L("settingsStartupSection")
    static let settingsKeyboardSection = L("settingsKeyboardSection")
    static let shelfBehaviorSection = L("shelfBehaviorSection")
    static let scopeSelection = L("scopeSelection")
    static let favoritesOverflowNote = L("favoritesOverflowNote")
    static let obStepCapture = L("obStepCapture")
    static let obStepShelf = L("obStepShelf")
    static let obStepDrag = L("obStepDrag")
    static let obFolderPermission = L("obFolderPermission")
    static let obHotKeyHelp = L("obHotKeyHelp")
    static let obSkipForNow = L("obSkipForNow")
    static let obShelfOpens = L("obShelfOpens")
    static func obProgress(_ i: Int, _ n: Int) -> String { F("obProgress", i, n) }
    static let tabScreenshots = L("tabScreenshots")
    static let tabActions = L("tabActions")
    static let tabGeneral = L("tabGeneral")
    static let folderLabel = L("folderLabel")
    static let folderCustom = L("folderCustom")
    static let folderNotChosen = L("folderNotChosen")
    static let chooseFolder = L("chooseFolder")
    static let maxItemsLabel = L("maxItemsLabel")
    static let shelfStyle = L("shelfStyle")
    static let shelfStyleFloating = L("shelfStyleFloating")
    static let shelfStyleStrip = L("shelfStyleStrip")
    static let shelfStyleHelp = L("shelfStyleHelp")
    static let stripNewCapture = L("stripNewCapture")
    static let stripNewCapturePeek = L("stripNewCapturePeek")
    static let stripNewCaptureStay = L("stripNewCaptureStay")
    static let stripNewCaptureHelp = L("stripNewCaptureHelp")
    static let stripMenuBarReveal = L("stripMenuBarReveal")
    static let stripMenuBarRevealHelp = L("stripMenuBarRevealHelp")
    static let showOnNewShot = L("showOnNewShot")
    static let showOnNewShotHelp = L("showOnNewShotHelp")
    static let hideAfterDrop = L("hideAfterDrop")
    static let hideAfterDropHelp = L("hideAfterDropHelp")
    static let thumbnailWarningTitle = L("thumbnailWarningTitle")
    static var thumbnailWarningBody: String { F("thumbnailWarningBody", ScreenshotHotKeys.options) }
    static let favoritesLabel = L("favoritesLabel")
    static let favoritesHelp = L("favoritesHelp")
    static let moveUp = L("moveUp")
    static let moveDown = L("moveDown")
    static let hotKeyLabel = L("hotKeyLabel")
    static let hotKeyRecordHint = L("hotKeyRecordHint")
    static let hotKeyRecordStart = L("hotKeyRecordStart")
    static let keySpace = L("keySpace")
    static func keyCodeName(_ code: Int) -> String { F("keyCodeName", code) }
    static let favoritesOverflowHeader = L("favoritesOverflowHeader")
    static let noticeDismiss = L("noticeDismiss")
    static let launchAtLogin = L("launchAtLogin")
    static let languageLabel = L("languageLabel")
    static let languageSystem = L("languageSystem")
    static let languageTurkish = L("languageTurkish")
    static let languageEnglish = L("languageEnglish")
    static let languageRelaunchNote = L("languageRelaunchNote")
    static let relaunchNow = L("relaunchNow")
    static let resetDefaults = L("resetDefaults")
    static let settingsAbout = L("settingsAbout")
    static let aboutHelpLink = L("aboutHelpLink")
    static let aboutPrivacyLink = L("aboutPrivacyLink")
    static let diagnostics = L("diagnostics")
    static let showLogFile = L("showLogFile")
    // Kurulum
    static let onboardingTitle = L("onboardingTitle")
    static let obWelcomeTitle = L("obWelcomeTitle")
    static let obWelcomeBody = L("obWelcomeBody")
    static let obFolderTitle = L("obFolderTitle")
    static var obFolderBody: String { F("obFolderBody", ScreenshotHotKeys.options) }
    static let obAccumulateTitle = L("obAccumulateTitle")
    static let obAccumulateBody = L("obAccumulateBody")
    static let obSampleShelfAX = L("obSampleShelfAX")
    static let obHotKeyTitle = L("obHotKeyTitle")
    static let obHotKeyBody = L("obHotKeyBody")
    static let obTryTitle = L("obTryTitle")
    static let obTryBody = L("obTryBody")
    static let obTryWaiting = L("obTryWaiting")
    static let obTryDetected = L("obTryDetected")
    static let obDragTitle = L("obDragTitle")
    static let obDragBody = L("obDragBody")
    static let next = L("next")
    static let back = L("back")
    static let finish = L("finish")
    static let skip = L("skip")
}

// MARK: - OCR
extension S {
    static let actionCopyText = L("actionCopyText")
    static let ocrBusy = L("ocrBusy")
    static func ocrCopied(_ n: Int) -> String { n == 1 ? L("ocrCopied.one") : F("ocrCopied.other", n) }
    static let ocrEmpty = L("ocrEmpty")
    static let ocrErrorUnreadable = L("ocrErrorUnreadable")
    static func ocrErrorFailed(_ m: String) -> String { F("ocrErrorFailed", m) }
    static let ocrLanguagesHelp = L("ocrLanguagesHelp")
}
// MARK: - Boyutlandır
extension S {
    static let actionResize = L("actionResize")
    static let resizeOriginal = L("resizeOriginal")
    static let resizeWidth = L("resizeWidth")
    static let resizeHeight = L("resizeHeight")
    static let resizeKeepAspect = L("resizeKeepAspect")
    static let resizeOutputLabel = L("resizeOutputLabel")
    static let resizePNGNote = L("resizePNGNote")
    static let resizePresets = L("resizePresets")
    static let resizeSizeSection = L("resizeSizeSection")
    static let resizeFormat = L("resizeFormat")
    static let resizeQuality = L("resizeQuality")
    static let resizeEstimated = L("resizeEstimated")
    static let resizeJPEGAlphaNote = L("resizeJPEGAlphaNote")
    static let resizeUpscaleNote = L("resizeUpscaleNote")
    static let resizeOutputCopy = L("resizeOutputCopy")
    static let resizeOutputSaveAs = L("resizeOutputSaveAs")
    static let resizeOutputAddToShelf = L("resizeOutputAddToShelf")
    static let resizeOutputHelp = L("resizeOutputHelp")
    static let resizeDone = L("resizeDone")
    static let resizeErrorUnreadable = L("resizeErrorUnreadable")
    static let resizeErrorInvalidSize = L("resizeErrorInvalidSize")
    static let resizeErrorEncode = L("resizeErrorEncode")
    static let resizeErrorTooLarge = L("resizeErrorTooLarge")
    static let resizeWorking = L("resizeWorking")
}
// MARK: - Menü çubuğu popover'ı
extension S {
    static func popoverCount(_ n: Int) -> String { n == 0 ? L("popoverCount.zero") : (n == 1 ? L("popoverCount.one") : F("popoverCount.other", n)) }
    static let popoverEmptyTitle = L("popoverEmptyTitle")
    static let popoverEmptyBody = L("popoverEmptyBody")
    static let popoverShowShelf = L("popoverShowShelf")
    static let popoverMore = L("popoverMore")
    static func popoverMoreCount(_ n: Int) -> String { n == 1 ? L("popoverMoreCount.one") : F("popoverMoreCount.other", n) }
    static let popoverNoSelection = L("popoverNoSelection")
    static let popoverTargetLast = L("popoverTargetLast")
}
// MARK: - Ayarlar (yeni düzen)
extension S {
    static let tabShelf = L("tabShelf")
    static let tabQuickActions = L("tabQuickActions")
    static let folderChange = L("folderChange")
    static let folderReveal = L("folderReveal")
    static let folderFooter = L("folderFooter")
    static let quickActionsFooter = L("quickActionsFooter")
    static let folderHelp = L("folderHelp")
    static let maxItemsHelp = L("maxItemsHelp")
    static func maxItemsConfirmTitle(_ n: Int) -> String { n == 1 ? L("maxItemsConfirmTitle.one") : F("maxItemsConfirmTitle.other", n) }
    static let maxItemsConfirmBody = L("maxItemsConfirmBody")
    static let maxItemsConfirmButton = L("maxItemsConfirmButton")
    static let afterDropTitle = L("afterDropTitle")
    static let aboutVersion = L("aboutVersion")
    static let aboutLog = L("aboutLog")
    static let openSourceLicenses = L("openSourceLicenses")
    static let openSourceLicensesTitle = L("openSourceLicensesTitle")
    static let generalHotKeyHelp = L("generalHotKeyHelp")
    static let appliesToSelection = L("appliesToSelection")
    static let appliesToSingle = L("appliesToSingle")
    static let otherActionsSection = L("otherActionsSection")
    static let dragToReorder = L("dragToReorder")
    static let favoriteOn = L("favoriteOn")
    static let favoriteOff = L("favoriteOff")
    static let choosePrompt = L("choosePrompt")
    static let copyHerePrompt = L("copyHerePrompt")
    static let noSuitableApp = L("noSuitableApp")
    static let copiedToast = L("copiedToast")
    static let saveAsSameFileTitle = L("saveAsSameFileTitle")
    static let saveAsSameFileBody = L("saveAsSameFileBody")
    static let saveAsChooseAnother = L("saveAsChooseAnother")
    static let saveAsSkippedTitle = L("saveAsSkippedTitle")
    static func saveAsSkippedBody(_ copied: Int, _ skipped: Int) -> String { F("saveAsSkippedBody", copied, skipped) }
    static let saveAsSkipReasonExists = L("saveAsSkipReasonExists")
    static func saveAsCopiedToast(_ n: Int) -> String { n == 1 ? L("saveAsCopiedToast.one") : F("saveAsCopiedToast.other", n) }
    static let outputStaleTitle = L("outputStaleTitle")
    static let outputStaleBody = L("outputStaleBody")
    static let outputErrorTitle = L("outputErrorTitle")
    static let resizeErrorWrite = L("resizeErrorWrite")
    static let resizeErrorClipboard = L("resizeErrorClipboard")
}

// MARK: - Düzenle
extension S {
    static let actionEdit = L("actionEdit")
    static let editTitle = L("editTitle")
    static let editToolCrop = L("editToolCrop")
    static let editToolRedact = L("editToolRedact")
    static let editToolAX = L("editToolAX")
    static let editAspect = L("editAspect")
    static let editAspectFree = L("editAspectFree")
    static let editUndo = L("editUndo")
    static let editRedo = L("editRedo")
    static let editZoomIn = L("editZoomIn")
    static let editZoomOut = L("editZoomOut")
    static let editZoomAX = L("editZoomAX")
    static let editZoomFit = L("editZoomFit")
    static let editNoSelection = L("editNoSelection")
    static let editRemoveRedaction = L("editRemoveRedaction")
    static let editClearCrop = L("editClearCrop")
    static let editHintCrop = L("editHintCrop")
    static let editHintRedact = L("editHintRedact")
    static func editInfoCrop(_ s: String) -> String { F("editInfoCrop", s) }
    static func editInfoRedact(_ n: Int, _ s: String?) -> String { if let s { return n == 1 ? F("editInfoRedact.one", s) : F("editInfoRedact.other", n, s) }; return n == 1 ? L("editInfoRedactCount.one") : F("editInfoRedactCount.other", n) }
    static let editInfoNoCrop = L("editInfoNoCrop")
    static func editFileInfo(_ w: Int, _ h: Int, _ size: String) -> String { F("editFileInfo", w, h, size) }
    static let editFormatLabel = L("editFormatLabel")
    static let editOriginalHelp = L("editOriginalHelp")
    static let outputErrorBody = L("outputErrorBody")
    static let outputMenuLabel = L("outputMenuLabel")
    static func zoomPercent(_ p: Int) -> String { F("zoomPercent", p) }
    static let editOutputHelp = L("editOutputHelp")
    static let editUnsavedTitle = L("editUnsavedTitle")
    static let editUnsavedBody = L("editUnsavedBody")
    static let editDiscard = L("editDiscard")
    static let editKeepEditing = L("editKeepEditing")
    static let editErrorSourceMissing = L("editErrorSourceMissing")
    static let editDone = L("editDone")
    static let editWorking = L("editWorking")
    static let editedBadge = L("editedBadge")
    static let editHEIFNote = L("editHEIFNote")
    static func editSizeLabel(_ w: Int, _ h: Int) -> String { F("editSizeLabel", w, h) }
}

// MARK: - Otomasyon ve dış giriş yolları
extension S {
    static let settingsAutomationSection = L("settingsAutomationSection")
    static let urlSchemeToggle = L("urlSchemeToggle")
    static let urlSchemeHelp = L("urlSchemeHelp")
    static let urlSchemeAskTitle = L("urlSchemeAskTitle")
    static let urlSchemeAskBody = L("urlSchemeAskBody")
    static let urlSchemeDeny = L("urlSchemeDeny")
    static let urlSchemeAllow = L("urlSchemeAllow")
    static let openShortcuts = L("openShortcuts")
    static let openShortcutsHelp = L("openShortcutsHelp")
    static let servicesInfo = L("servicesInfo")
    static let servicesInfoHelp = L("servicesInfoHelp")
    static let controlCenterInfo = L("controlCenterInfo")
    static let controlCenterInfoHelp = L("controlCenterInfoHelp")
    static func inboundAdded(_ n: Int) -> String { n == 1 ? L("inboundAdded.one") : F("inboundAdded.other", n) }
    static let inboundAlready = L("inboundAlready")
    static let inboundRejected = L("inboundRejected")
    static let inboundLimit = L("inboundLimit")
    /// Sayı sınırı aşıldı ama bir kısmı eklendi.
    static func inboundAddedLimited(_ n: Int) -> String { n == 1 ? L("inboundAddedLimited.one") : F("inboundAddedLimited.other", n) }
    static let inboundTooLarge = L("inboundTooLarge")
    // App Intents
    static let intentAddTitle = L("intentAddTitle")
    static let intentAddDesc = L("intentAddDesc")
    static let intentGetTitle = L("intentGetTitle")
    static let intentGetNewTitle = L("intentGetNewTitle")
    static let intentGetDesc = L("intentGetDesc")
    static let intentGetNewDesc = L("intentGetNewDesc")
    static let intentClipboardTitle = L("intentClipboardTitle")
    static let intentClipboardDesc = L("intentClipboardDesc")
    static let intentCopyLatestTitle = L("intentCopyLatestTitle")
    static let intentCopyLatestDesc = L("intentCopyLatestDesc")
    static let intentShowTitle = L("intentShowTitle")
    static let intentHideTitle = L("intentHideTitle")
    static let intentClearTitle = L("intentClearTitle")
    static let intentClearDesc = L("intentClearDesc")
    /// Konumsal biçim: `%1$@` raf adı, `%2$d` sayı.
    static func intentClearConfirm(_ shelf: String, _ n: Int) -> String { n == 1 ? F("intentClearConfirm.one", shelf) : F("intentClearConfirm.other", shelf, n) }
    static let intentUploadTitle = L("intentUploadTitle")
    static let intentUploadDesc = L("intentUploadDesc")
    static let paramFiles = L("paramFiles")
    static let paramShelf = L("paramShelf")
    static let paramOnlyNew = L("paramOnlyNew")
    static let paramLimit = L("paramLimit")
    static let paramProvider = L("paramProvider")
    static let paramCopyLink = L("paramCopyLink")
    static let paramItems = L("paramItems")
    static let entityShot = L("entityShot")
    static let entityShelf = L("entityShelf")
    static let entityNew = L("entityNew")
    static let entityFileName = L("entityFileName")
    static let entityCapturedAt = L("entityCapturedAt")
    static let entityCloudLink = L("entityCloudLink")
    static let entityItemCount = L("entityItemCount")
    static let intentErrNotReady = L("intentErrNotReady")
    static let intentErrNoImages = L("intentErrNoImages")
    static let intentErrShelfNotFound = L("intentErrShelfNotFound")
    static let intentErrFileRejected = L("intentErrFileRejected")
    static let intentErrTooMany = L("intentErrTooMany")
    static func intentErrNotConnected(_ provider: String) -> String { F("intentErrNotConnected", provider) }
    static let intentErrUploadRunning = L("intentErrUploadRunning")
    static let intentErrClipboardEmpty = L("intentErrClipboardEmpty")
    static let cmdShowTitle = L("cmdShowTitle")
    static let cmdClipboardTitle = L("cmdClipboardTitle")
    static let cmdCopyLatestTitle = L("cmdCopyLatestTitle")
}

// MARK: - Yerelleştirme yardımcıları
/// Uygulama paketi; birim testleri de uygulamayı host ettiği için `Bundle.main` doğru pakettir.
private let stringsBundle = Bundle.main
@inline(__always) private func L(_ key: String) -> String { stringsBundle.localizedString(forKey: key, value: nil, table: nil) }
private func F(_ key: String, _ args: CVarArg...) -> String {
    String(format: stringsBundle.localizedString(forKey: key, value: nil, table: nil), arguments: args) // locale yok: sayılar gruplanmaz
}
'''

# Bulut üyeleri yalnız bulutlu derlemede (Release 1.0 ikilisinde bulut metni olmasın); tablo: Cloud.strings.
CLOUD_SWIFT = '''
#if SHOTMORI_CLOUD
// MARK: - Bulut (yalnız SHOTMORI_CLOUD; tablo: Cloud.strings)
extension S {
    static let cloudErrNotConnected = LC("cloudErrNotConnected")
    static let cloudErrUnauthorized = LC("cloudErrUnauthorized")
    static let cloudErrForbidden = LC("cloudErrForbidden")
    static let cloudErrNotFound = LC("cloudErrNotFound")
    static func cloudErrNetwork(_ m: String) -> String { FC("cloudErrNetwork", m) }
    static func cloudErrServer(_ code: Int, _ m: String) -> String { FC("cloudErrServer", code, m) }
    static let cloudErrVerify = LC("cloudErrVerify")
    static let cloudErrFileUnreadable = LC("cloudErrFileUnreadable")
    static func cloudErrServerCode(_ code: Int) -> String { FC("cloudErrServerCode", code) }
    static let cloudErrInvalidResponse = LC("cloudErrInvalidResponse")
    static let cloudErrCancelled = LC("cloudErrCancelled")
    static let cloudErrAuthDenied = LC("cloudErrAuthDenied")
    static let cloudErrNoRefreshToken = LC("cloudErrNoRefreshToken")
    static func cloudErrKeychain(_ status: Int) -> String { FC("cloudErrKeychain", status) }
    static let cloudErrBucketNotFound = LC("cloudErrBucketNotFound")
    static let cloudErrBadCredentials = LC("cloudErrBadCredentials")
    static let cloudErrRateLimited = LC("cloudErrRateLimited")
    static let cloudErrQuotaExceeded = LC("cloudErrQuotaExceeded")
    static let s3PresetOther = LC("s3PresetOther")
    static let actionUploadDrive = LC("actionUploadDrive")
    static let actionUploadS3 = LC("actionUploadS3")
    static let cloudMenu = LC("cloudMenu")
    static let cloudCopyLink = LC("cloudCopyLink")
    static let cloudOpenLink = LC("cloudOpenLink")
    static let cloudAccessMenu = LC("cloudAccessMenu")
    static let cloudDelete = LC("cloudDelete")
    static let cloudDeleteTitle = LC("cloudDeleteTitle")
    static func cloudDeleteBody(_ p: String) -> String { FC("cloudDeleteBody", p) }
    static func cloudDeleteBodyLocalTrashed(_ p: String) -> String { FC("cloudDeleteBodyLocalTrashed", p) }
    static let cloudDeleteButton = LC("cloudDeleteButton")
    static func cloudNotConnected(_ p: String) -> String { FC("cloudNotConnected", p) }
    static let cloudQueued = LC("cloudQueued")
    static func cloudUploading(_ n: String) -> String { FC("cloudUploading", n) }
    static let cloudLinkCopied = LC("cloudLinkCopied")
    static let cloudUploadedNoLink = LC("cloudUploadedNoLink")
    static func cloudFailed(_ m: String) -> String { FC("cloudFailed", m) }
    static let cloudRetry = LC("cloudRetry")
    static let cloudAccessAnyone = LC("cloudAccessAnyone")
    static let cloudAccessOwner = LC("cloudAccessOwner")
    static let cloudAccessPublic = LC("cloudAccessPublic")
    static func cloudAccessPresigned(_ d: String) -> String { FC("cloudAccessPresigned", d) }
    static let cloudAccessChanged = LC("cloudAccessChanged")
    static func cloudAccessChangeFailed(_ m: String) -> String { FC("cloudAccessChangeFailed", m) }
    static func cloudDeleteFailed(_ m: String) -> String { FC("cloudDeleteFailed", m) }
    static let cloudRecentUploads = LC("cloudRecentUploads")
    static let cloudRecentEmpty = LC("cloudRecentEmpty")
    static let cloudRemoveFromList = LC("cloudRemoveFromList")
    static let cloudBadgePending = LC("cloudBadgePending")
    static func cloudBadgeUploaded(_ p: String) -> String { FC("cloudBadgeUploaded", p) }
    static let cloudBadgeFailed = LC("cloudBadgeFailed")
    static let cloudLocalTrashed = LC("cloudLocalTrashed")
    static let cloudBackupQueued = LC("cloudBackupQueued")
    static let cloudTrashedAfterBackup = LC("cloudTrashedAfterBackup")
    static let tabCloud = LC("tabCloud")
    static let cloudIntro = LC("cloudIntro")
    static let cloudAccountsSection = LC("cloudAccountsSection")
    static let cloudAccountsFooter = LC("cloudAccountsFooter")
    static let cloudSharingSection = LC("cloudSharingSection")
    static let cloudSetUp = LC("cloudSetUp")
    static let cloudEdit = LC("cloudEdit")
    static let cloudAdvancedButton = LC("cloudAdvancedButton")
    static let cloudDriveLinkAccess = LC("cloudDriveLinkAccess")
    static let cloudS3LinkAccess = LC("cloudS3LinkAccess")
    static let cloudDriveTemplate = LC("cloudDriveTemplate")
    static let cloudS3Template = LC("cloudS3Template")
    static let s3SheetTitle = LC("s3SheetTitle")
    static let cloudDriveAdvancedTitle = LC("cloudDriveAdvancedTitle")
    static let cloudS3Subtitle = LC("cloudS3Subtitle")
    static let cloudDriveSection = LC("cloudDriveSection")
    static let cloudS3Section = LC("cloudS3Section")
    static let cloudCommonSection = LC("cloudCommonSection")
    static let cloudBackupSection = LC("cloudBackupSection")
    static let cloudClientID = LC("cloudClientID")
    static let cloudClientSecret = LC("cloudClientSecret")
    static let cloudClientHelp = LC("cloudClientHelp")
    static let cloudSignIn = LC("cloudSignIn")
    static let cloudSignInHint = LC("cloudSignInHint")
    static let cloudAdvancedClient = LC("cloudAdvancedClient")
    static let cloudAdvancedClientHelp = LC("cloudAdvancedClientHelp")
    static let cloudSignOut = LC("cloudSignOut")
    static let cloudConnected = LC("cloudConnected")
    static let cloudDisconnected = LC("cloudDisconnected")
    static let cloudSigningIn = LC("cloudSigningIn")
    static let cloudDefaultAccess = LC("cloudDefaultAccess")
    static let cloudFolderTemplate = LC("cloudFolderTemplate")
    static let cloudTemplateHelp = LC("cloudTemplateHelp")
    static let cloudTest = LC("cloudTest")
    static let cloudTestOK = LC("cloudTestOK")
    static let cloudTesting = LC("cloudTesting")
    static let s3Preset = LC("s3Preset")
    static let s3Endpoint = LC("s3Endpoint")
    static let s3EndpointPromptR2 = LC("s3EndpointPromptR2")
    static let s3EndpointPromptB2 = LC("s3EndpointPromptB2")
    static let s3Region = LC("s3Region")
    static let s3Bucket = LC("s3Bucket")
    static let s3AccessKey = LC("s3AccessKey")
    static let s3SecretKey = LC("s3SecretKey")
    static let s3SecretStored = LC("s3SecretStored")
    static let s3PathStyle = LC("s3PathStyle")
    static let s3PresignDuration = LC("s3PresignDuration")
    static let s3Save = LC("s3Save")
    static let s3Clear = LC("s3Clear")
    static let cloudLinkFormat = LC("cloudLinkFormat")
    static let cloudLinkFormatURL = LC("cloudLinkFormatURL")
    static let cloudLinkFormatMarkdown = LC("cloudLinkFormatMarkdown")
    static let cloudLinkFormatHTML = LC("cloudLinkFormatHTML")
    static let cloudBackupTarget = LC("cloudBackupTarget")
    static let cloudBackupOff = LC("cloudBackupOff")
    static let cloudBackupDerivatives = LC("cloudBackupDerivatives")
    static let cloudTrashAfterBackup = LC("cloudTrashAfterBackup")
    static let cloudTrashAfterBackupHelp = LC("cloudTrashAfterBackupHelp")
    static func cloudQueueStatus(_ n: Int) -> String { FC("cloudQueueStatus", n) }
    static let cloudAuthDone = LC("cloudAuthDone")
    static let cloudAuthDenied = LC("cloudAuthDenied")
    static let cloudAuthStateMismatch = LC("cloudAuthStateMismatch")
}

@inline(__always) private func LC(_ key: String) -> String { stringsBundle.localizedString(forKey: key, value: nil, table: "Cloud") }
private func FC(_ key: String, _ args: CVarArg...) -> String {
    String(format: stringsBundle.localizedString(forKey: key, value: nil, table: "Cloud"), arguments: args)
}
#endif
'''

# Widget uzantısı erişimcileri (Shared/WStrings.swift; uzantı sürecinde `Bundle.main` uzantı paketidir).
W_SWIFT = '''import Foundation

/// Widget uzantısı metinleri. Kaynak: ShotmoriWidgets/{tr,en}.lproj/Localizable.strings.
/// Üreteç: scripts/gen_strings.py (tablo W) — elle düzenlenmez. `Bundle.main` uzantı sürecinde uzantı paketidir.
/// Dil: `languageOverride` (anlık görüntüdeki uygulama dili, "tr"/"en") verilirse o `.lproj` okunur; yoksa sistem dili.
enum WS {
    /// Ana uygulamanın seçtiği arayüz dili; uzantı bunu `widget-snapshot.json`dan alır. nil = sistem dili.
    static var languageOverride: String?
    static var widgetRecentTitle: String { WL("widgetRecentTitle") }
    static var widgetRecentDesc: String { WL("widgetRecentDesc") }
    static var widgetEmpty: String { WL("widgetEmpty") }
    static func widgetNew(_ n: Int) -> String { n == 1 ? WL("widgetNew.one") : WF("widgetNew.other", n) }
    static func widgetTotal(_ n: Int) -> String { n == 1 ? WL("widgetTotal.one") : WF("widgetTotal.other", n) }
    static var cmdShowTitle: String { WL("cmdShowTitle") }
    static var cmdClipboardTitle: String { WL("cmdClipboardTitle") }
    static var cmdCopyLatestTitle: String { WL("cmdCopyLatestTitle") }

    /// `languageOverride` paketi varsa o, yoksa `Bundle.main` (sistem dili seçimi).
    static var bundle: Bundle {
        guard let code = languageOverride, let url = Bundle.main.url(forResource: code, withExtension: "lproj"), let b = Bundle(url: url) else { return .main }
        return b
    }
}

@inline(__always) private func WL(_ key: String) -> String { WS.bundle.localizedString(forKey: key, value: nil, table: nil) }
private func WF(_ key: String, _ args: CVarArg...) -> String {
    String(format: WS.bundle.localizedString(forKey: key, value: nil, table: nil), arguments: args)
}
'''

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

def strings_file(table, idx, lang_comment):
    out = [f"/* Shotmori — {lang_comment}. Üreteç: scripts/gen_strings.py; elle düzenlerseniz üreteci de güncelleyin. */", ""]
    for key, tr, en in table:
        out.append(f'"{key}" = "{esc((tr, en)[idx])}";')
    return "\n".join(out) + "\n"

# Biçim yer tutucuları: sıralı (%d, %@) sırayla, konumsal (%2$d) konuma göre; iki dilde aynı olmalı.
def fmt(v):
    seq, pos = [], []
    for n, t in re.findall(r"%(?:(\d+)\$)?([d@])", v):
        if n: pos.append((int(n), t))
        else: seq.append(t)
    return seq + [f"{n}${t}" for n, t in sorted(pos)]

# Tutarlılık denetimleri: ana tablo ↔ L/F, bulut tablosu ↔ LC/FC, widget tablosu ↔ WL/WF; ana ve bulut ortak anahtar taşımaz.
def check(table, swift, pattern, name):
    keys = [k for k, _, _ in table]
    assert len(keys) == len(set(keys)), f"yinelenen anahtar ({name})"
    used = set(re.findall(pattern, swift))
    missing = used - set(keys); unused = set(keys) - used
    assert not missing, f"Swift'te var, {name} tablosunda yok: {missing}"
    assert not unused, f"{name} tablosunda var, Swift'te yok: {unused}"
    for k, tr, en in table:
        assert fmt(tr) == fmt(en), f"biçim uyuşmazlığı: {k}"
        assert tr and en, f"boş değer: {k}"
    return keys
keys = check(T, SWIFT, r'\b[LF]\("([^"]+)"', "ana")
ckeys = check(C, CLOUD_SWIFT, r'\b[LF]C\("([^"]+)"', "Cloud")
wkeys = check(W, W_SWIFT, r'\bW[LF]\("([^"]+)"', "W")
assert not set(keys) & set(ckeys), f"iki tabloda birden: {set(keys) & set(ckeys)}"
assert not re.search(r'\b[LF]C\(', SWIFT) and not re.search(r'\b[LF]\(', CLOUD_SWIFT), "tablo yardımcısı karıştı"
WSHARED = {"cmdShowTitle", "cmdClipboardTitle", "cmdCopyLatestTitle"}
assert set(wkeys) & set(keys) <= WSHARED, f"widget ve ana tabloda birden: {(set(wkeys) & set(keys)) - WSHARED}"
tmap = {k: (tr, en) for k, tr, en in T}
for k, tr, en in W:
    if k in WSHARED: assert tmap.get(k) == (tr, en), f"ortak komut başlığı farklı: {k}"
# I ve A: (İngilizce anahtar, Türkçe); yinelenen anahtar yok; A satırları iki dilde de tek `${applicationName}` taşır.
for name, table in (("I", I), ("A", A)):
    en_keys = [en for en, _ in table]
    assert len(en_keys) == len(set(en_keys)), f"yinelenen anahtar ({name})"
    for en, tr in table:
        assert en and tr, f"boş değer ({name}): {en}"
        assert fmt(en) == fmt(tr), f"biçim uyuşmazlığı ({name}): {en}"
tkeys = set(keys) | set(ckeys)
for en, tr in P:
    assert en and tr and en not in tkeys, f"P anahtarı boş ya da T/C ile çakışıyor: {en}"
    assert sorted(re.findall(r"\$\{(\w+)\}", en)) == sorted(re.findall(r"\$\{(\w+)\}", tr)), f"yer tutucu uyuşmazlığı (P): {en}"
assert len({en for en, _ in P}) == len(P), "yinelenen anahtar (P)"
for en, tr in A:
    assert en.count("${applicationName}") == 1 and tr.count("${applicationName}") == 1, f"${{applicationName}} eksik: {en}"

def pair_file(table, idx, comment):
    out = [f"/* Shotmori — {comment}. Üreteç: scripts/gen_strings.py; elle düzenlerseniz üreteci de güncelleyin. */", ""]
    for en, tr in table:
        out.append(f'"{esc(en)}" = "{esc((tr, en)[idx])}";')
    return "\n".join(out) + "\n"

PROJECT = ROOT.parent
(ROOT / "Core/Strings.swift").write_text(SWIFT + CLOUD_SWIFT, encoding="utf-8")
(PROJECT / "Shared").mkdir(exist_ok=True)
(PROJECT / "Shared/WStrings.swift").write_text(W_SWIFT, encoding="utf-8")
for lang, idx, comment in (("tr", 0, "Türkçe (varsayılan dil)"), ("en", 1, "English")):
    (ROOT / f"{lang}.lproj").mkdir(exist_ok=True)
    summaries = "\n/* App Intents parametre özetleri (tablo P) */\n" + "".join(f'"{esc(en)}" = "{esc((tr, en)[idx])}";\n' for en, tr in P)
    (ROOT / f"{lang}.lproj/Localizable.strings").write_text(strings_file(T, idx, comment) + summaries, encoding="utf-8")
    (ROOT / f"{lang}.lproj/Cloud.strings").write_text(strings_file(C, idx, comment + " · bulut (SHOTMORI_CLOUD: Debug ve Release 1.0)"), encoding="utf-8")
    (ROOT / f"{lang}.lproj/ServicesMenu.strings").write_text(pair_file(I, idx, comment + " · Servisler menüsü"), encoding="utf-8")
    (ROOT / f"{lang}.lproj/AppShortcuts.strings").write_text(pair_file(A, idx, comment + " · App Shortcuts ifadeleri"), encoding="utf-8")
    (PROJECT / f"ShotmoriWidgets/{lang}.lproj").mkdir(parents=True, exist_ok=True)
    (PROJECT / f"ShotmoriWidgets/{lang}.lproj/Localizable.strings").write_text(strings_file(W, idx, comment + " · widget uzantısı"), encoding="utf-8")
print(f"{len(keys)} anahtar + {len(ckeys)} bulut anahtarı + {len(wkeys)} widget anahtarı + {len(I)} servis + {len(A)} kestirme ifadesi + {len(P)} parametre özeti yazıldı")
