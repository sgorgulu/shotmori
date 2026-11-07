import AppIntents

// macOS 26+: yürütme kipleri (Spotlight ve Kestirmeler önde/arkada çalıştırmayı buradan okur). 14–25'te `openAppWhenRun` geçerli.
// Rafı gösteren eylem önde, diğerleri arka planda (panel açılmaz, odak çalınmaz).

@available(macOS 26, *)
extension AddToShelfIntent { static var supportedModes: IntentModes { .background } }
@available(macOS 26, *)
extension GetShelfItemsIntent { static var supportedModes: IntentModes { .background } }
@available(macOS 26, *)
extension GetNewShelfItemsIntent { static var supportedModes: IntentModes { .background } }
@available(macOS 26, *)
extension AddClipboardIntent { static var supportedModes: IntentModes { .background } }
@available(macOS 26, *)
extension CopyLatestIntent { static var supportedModes: IntentModes { .background } }
@available(macOS 26, *)
extension ShowShelfIntent { static var supportedModes: IntentModes { .foreground } }
@available(macOS 26, *)
extension HideShelfIntent { static var supportedModes: IntentModes { .background } }
@available(macOS 26, *)
extension ClearShelfIntent { static var supportedModes: IntentModes { .background } }
#if SHOTMORI_CLOUD
@available(macOS 26, *)
extension UploadIntent { static var supportedModes: IntentModes { .background } }
#endif
