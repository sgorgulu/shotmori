import AppKit

/// Widget anlık görüntüsü: raf her değiştiğinde (0,5 sn debounce) grup konteynerine `widget-snapshot.json` + 3 küçük resim.
/// Yalıtılmış çalışmada (`SHOTMORI_DATA_DIR`, test/QA) `<kök>/WidgetGroup`a yazılır: gerçek widget kirlenmez.
/// Yazıcıyı gözlemci kapanışı tutar (raf → gözlemci → yazıcı; yazıcı rafı zayıf tutar, döngü yok).
extension AppController {
    func installWidgetSnapshot() {
        guard let container = WidgetSnapshotWriter.containerURL(isolatedRoot: WidgetSnapshotWriter.isolatedRoot) else {
            Log.info("Widget anlık görüntüsü kapalı: grup konteyneri yok"); return
        }
        let writer = WidgetSnapshotWriter(store: store, container: container, language: { [weak self] in self?.prefs.uiLanguage })
        _ = store.addObserver { writer.scheduleWrite() }
        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { _ in writer.scheduleWrite() } // dil değişince metinler de
        writer.scheduleWrite() // açılışta güncel durum
    }
}
