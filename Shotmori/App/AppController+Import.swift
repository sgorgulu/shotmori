import AppKit

/// Dış dosya ve görsel verisi → `InboundImport` (kopya `Gelen/`e) → etkin raf. Özgün dosyaya dokunulmaz.
/// Açık kullanıcı içe aktarması kaldırma izini (`dismissed`) aşar: raftan kaldırılan görüntü yeniden bırakılınca geri gelir.
extension AppController {
    /// Dosyalar kopyalanıp etkin rafa eklenir; izlenen klasördekiler kopyalanmadan `.screenshot` olarak eklenir.
    /// Kestirmeler (`.intent`) dışındaki yollarda panel odak çalmadan açılır ve sonuç bildirilir.
    func importExternal(_ urls: [URL], source: InboundSource) {
        let watched = folder
        InboundImport.importFiles(urls, source: source, watchedFolder: watched) { [weak self] result in
            guard let self else { return }
            let items = (result.added + result.alreadyPresent).map { u in
                ShelfItem(path: u.path, fileID: ScreenshotFileInspector.fileIdentifier(u), capturedAt: ScreenshotFileInspector.creationDate(u) ?? Date(),
                          source: Self.shelfSource(for: u, watchedFolder: watched))
            }
            let inserted = items.isEmpty ? 0 : self.store.add(items.sorted { $0.capturedAt < $1.capturedAt }, overrideDismissed: true).count
            Log.info("Dış giriş (\(source.rawValue)): \(inserted) öğe rafa eklendi")
            guard source != .intent else { return }
            if let m = Self.importToast(result, inserted: inserted) { self.present(m) }
            self.shelf.show(takeKey: false)
        }
    }

    /// Pasteboard görseli (Servisler, bırakma): veri `Gelen/`e yazılır ve rafa eklenir.
    func importExternalData(_ data: Data, ext: String, source: InboundSource) {
        InboundImport.importDataOutcome(data, fileExtension: ext, source: source, completion: { [weak self] (outcome: InboundImport.Outcome) in
            guard let self else { return }
            var r = InboundImport.Result(); r.record(outcome)
            var inserted = 0
            if let url = (r.added + r.alreadyPresent).first {
                let item = ShelfItem(path: url.path, fileID: ScreenshotFileInspector.fileIdentifier(url), capturedAt: Date(), source: .imported)
                inserted = self.store.add(item, overrideDismissed: true) ? 1 : 0
            }
            guard source != .intent else { return }
            if let m = Self.importToast(r, inserted: inserted) { self.present(m) }
            self.shelf.show(takeKey: false)
        })
    }

    /// Başarı geçici tostla (1,6 sn); ret ve sınır kalıcı bildirimle (yüksek öncelikli duyuru) gösterilir.
    private func present(_ m: ImportMessage) {
        if m.isError { shelf.showNotice(m.text) } else { shelf.showToast(m.text) }
    }

    /// İzlenen klasördeki dosya ekran görüntüsüdür (kopyalanmadı); diğer her şey içe aktarılmıştır. Kendi konteynerimiz izlenen klasör sayılmaz.
    static func shelfSource(for url: URL, watchedFolder: URL?) -> ShelfItemSource {
        guard let w = watchedFolder,
              !InboundImport.shortCircuit(url, watchedFolder: nil, container: AppPaths.applicationSupport),
              InboundImport.shortCircuit(url, watchedFolder: nil, container: w) else { return .imported }
        return .screenshot
    }

    /// Dış giriş sonucu: metin ve türü (hata → kalıcı bildirim).
    struct ImportMessage: Equatable {
        let text: String
        let isError: Bool
        static func success(_ t: String) -> Self { Self(text: t, isError: false) }
        static func error(_ t: String) -> Self { Self(text: t, isError: true) }
    }

    /// Sonuç bildirimi: eklendi + sayı sınırı > sayı sınırı > eklendi > zaten rafta > 50 MB üstü > yalnız görüntü.
    static func importToast(_ r: InboundImport.Result, inserted: Int) -> ImportMessage? {
        if r.limited > 0 { return inserted > 0 ? .error(S.inboundAddedLimited(inserted)) : .error(S.inboundLimit) }
        if inserted > 0 { return .success(S.inboundAdded(inserted)) }
        if !r.added.isEmpty || !r.alreadyPresent.isEmpty { return .success(S.inboundAlready) }
        if r.oversized > 0 { return .error(S.inboundTooLarge) }
        return .error(S.inboundRejected)
    }
}
