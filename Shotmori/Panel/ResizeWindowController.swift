import AppKit
import SwiftUI
import Combine

/// "Boyutlandır…" penceresi: tek görüntü için yeni ölçü, biçim, kalite; sonuç Kopyala (ana) + Rafa ekle / Farklı kaydet menüde.
final class ResizeModel: ObservableObject {
    let source: URL
    let info: ImageResizer.SourceInfo
    @Published var width: Int { didSet { if keepAspect && !syncing { syncing = true; height = ResizeMath.heightKeepingAspect(original: info.pixelSize, width: max(width, 1)); syncing = false }; scheduleEstimate() } }
    @Published var height: Int { didSet { if keepAspect && !syncing { syncing = true; width = ResizeMath.widthKeepingAspect(original: info.pixelSize, height: max(height, 1)); syncing = false }; scheduleEstimate() } }
    @Published var keepAspect = true
    @Published var format: ImageOutputFormat = .png { didSet { scheduleEstimate() } }
    @Published var quality: Double = 0.8 { didSet { scheduleEstimate() } }
    @Published var estimatedBytes: Int?
    @Published var working = false
    @Published var errorText: String?
    /// Pencere kapandı (Vazgeç, Esc, ✕, ⌘W): süren render bitse de çıktı teslim edilmez.
    private(set) var cancelled = false
    func cancel() { cancelled = true; estimateWork?.cancel() }
    private var syncing = false
    private var estimateWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "dev.shotmori.resize", qos: .userInitiated)

    init(source: URL, info: ImageResizer.SourceInfo) {
        self.source = source; self.info = info
        width = info.pixelSize.width; height = info.pixelSize.height
        format = source.pathExtension.lowercased().hasPrefix("jp") ? .jpeg : .png
        scheduleEstimate()
    }
    var target: ResizeMath.Size { .init(width: width, height: height) }
    var validation: ResizeMath.Validation { ResizeMath.validate(target) }
    var isUpscale: Bool { width > info.pixelSize.width || height > info.pixelSize.height }
    var canOutput: Bool { validation == .ok && !working }
    func applyPercent(_ p: Double) { let s = ResizeMath.scaled(info.pixelSize, percent: p); syncing = true; width = s.width; height = s.height; syncing = false; scheduleEstimate() }
    func applyWidth(_ w: Int) { syncing = true; width = w; height = ResizeMath.heightKeepingAspect(original: info.pixelSize, width: w); syncing = false; scheduleEstimate() }
    func isPercentActive(_ p: Double) -> Bool { ResizeMath.scaled(info.pixelSize, percent: p) == target }
    /// Gruplu form yükseklikleri (v2): PNG 440 · JPEG 484 (+28 saydam kaynak uyarısı) · hata +28 (bağlamsal satırlar kadar büyür/küçülür).
    var preferredHeight: CGFloat {
        var h: CGFloat = 440
        if format == .jpeg { h += 44 }
        if format == .jpeg && info.hasAlpha { h += 28 } // "Saydam alanlar beyaz olur." görünür uyarı
        if validation != .ok || errorText != nil { h += 28 }
        return h
    }

    /// Tahmin: gerçek kodlama arka planda, 350 ms gecikmeyle (arayüz bloklanmaz).
    private func scheduleEstimate() {
        estimateWork?.cancel()
        guard validation == .ok else { estimatedBytes = nil; return }
        let w = DispatchWorkItem { [weak self, source, target, format, quality] in
            let n = (try? ImageResizer.render(source, to: target, format: format, quality: quality))?.count
            DispatchQueue.main.async { self?.estimatedBytes = n }
        }
        estimateWork = w; queue.asyncAfter(deadline: .now() + 0.35, execute: w)
    }
    /// Üç çıktı aynı render yolundan geçer; geçersiz ölçüde veya çalışırken yeniden tetiklenmez.
    func render(completion: @escaping (Result<Data, Error>) -> Void) {
        guard canOutput else { return }
        working = true; errorText = nil
        queue.async { [source, target, format, quality] in
            let r = Result { try ImageResizer.render(source, to: target, format: format, quality: quality) }
            DispatchQueue.main.async {
                self.working = false
                guard !self.cancelled else { return } // kapalı pencereden dosya yazılmaz, pano ezilmez, rafa eklenmez
                if case .failure(let e) = r { self.errorText = e.localizedDescription }; completion(r)
            }
        }
    }
}

struct ResizeView: View {
    @ObservedObject var m: ResizeModel
    let onCopy: (Data) -> Void
    let onSaveAs: (Data) -> Void
    let onAddToShelf: (Data) -> Void
    let onCancel: () -> Void
    @FocusState private var editingField: Bool
    private let fmt = ByteCountFormatter()

    var body: some View {
        VStack(spacing: 0) {
            // Gruplu form (cam krom görünsün diye saydam zemin); dosya adı ve ölçü·boyut pencere başlığında
            Pane.form {
                Section(S.resizeSizeSection) {
                    HStack(alignment: .bottom, spacing: 10) {
                        field(S.resizeWidth, value: $m.width, invalid: m.validation != .ok && !(1...16384).contains(m.width))
                        Text("×").foregroundStyle(.secondary).padding(.bottom, 6)
                        field(S.resizeHeight, value: $m.height, invalid: m.validation != .ok && !(1...16384).contains(m.height))
                        Text("px").foregroundStyle(.secondary).padding(.bottom, 6)
                        Spacer()
                        Toggle(isOn: $m.keepAspect) { Label(S.resizeKeepAspect, systemImage: m.keepAspect ? "lock" : "lock.open") }.toggleStyle(.button).padding(.bottom, 1)
                    }
                    HStack(spacing: 6) {
                        ForEach([75.0, 50.0, 25.0], id: \.self) { p in chip(S.zoomPercent(Int(p)), active: m.isPercentActive(p)) { m.applyPercent(p) } }
                        Divider().frame(height: 18).padding(.horizontal, 4)
                        ForEach([1920, 1280, 800], id: \.self) { w in chip("\(w) px", active: m.width == w) { m.applyWidth(w) }.disabled(w >= m.info.pixelSize.width) }
                    }.accessibilityElement(children: .contain).accessibilityLabel(S.resizePresets) // grup etiketi; düğmeler kendi adını ("50%", "1280 px") korur
                }
                Section {
                    // PNG/JPEG; "PNG saydamlığı korur" notu araç ipucunda
                    Pane.row(S.resizeFormat, help: S.resizePNGNote) {
                        Picker("", selection: $m.format) { ForEach(ImageOutputFormat.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(width: 180).accessibilityLabel(S.resizeFormat)
                    }
                    if m.format == .jpeg {
                        Pane.row(S.resizeQuality) {
                            HStack { Slider(value: $m.quality, in: 0.3...1.0, step: 0.05).frame(width: 200).accessibilityLabel(S.resizeQuality); Text(verbatim: S.zoomPercent(Int((m.quality * 100).rounded()))).monospacedDigit().frame(width: 40, alignment: .trailing) }
                        }
                        // Koşullu uyarı görünür kalır: saydam kaynak JPEG'de beyazlaşır
                        if m.info.hasAlpha { Label(S.resizeJPEGAlphaNote, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) { Text(S.resizeOutputLabel).font(.callout).foregroundStyle(.secondary); Text(verbatim: m.validation == .ok ? "\(m.width) × \(m.height) px" : "—").monospacedDigit() }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(S.resizeEstimated).font(.callout).foregroundStyle(.secondary)
                            if let b = m.estimatedBytes, m.validation == .ok { Text(fmt.string(fromByteCount: Int64(b))).monospacedDigit() }
                            else if m.validation == .ok { ProgressView().controlSize(.mini) } else { Text("—") }
                        }
                    }
                    if m.validation != .ok { Label(S.resizeErrorInvalidSize, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Color.smDestructive) }
                    else if m.isUpscale { Label(S.resizeUpscaleNote, systemImage: "arrow.up.left.and.arrow.down.right").font(.callout).foregroundStyle(.secondary) }
                    if let e = m.errorText { Label(e, systemImage: "xmark.octagon").font(.callout).foregroundStyle(Color.smDestructive) }
                }
            }
            Divider()
            // Çıktı satırı: kilit (ipucu: orijinal korunur) · Vazgeç · Kopyala (ana, cam) + menü
            HStack(spacing: 12) {
                Image(systemName: "lock").foregroundStyle(.secondary).help(S.editOriginalHelp).accessibilityLabel(S.editOriginalHelp)
                Spacer()
                if m.working { ProgressView().controlSize(.small) }
                Button(S.cancel, role: .cancel) { onCancel() }.buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut(.cancelAction)
                HStack(spacing: 4) {
                    Button { m.render { if case .success(let d) = $0 { onCopy(d) } } } label: { Label(S.copyShort, systemImage: "doc.on.doc") }
                        .glassButton(prominent: true).controlSize(.large).accessibilityLabel(S.copyShort)
                    Menu {
                        Button { m.render { if case .success(let d) = $0 { onCopy(d) } } } label: { Label(S.copyShort, systemImage: "doc.on.doc") }
                        Button { m.render { if case .success(let d) = $0 { onAddToShelf(d) } } } label: { Label(S.resizeOutputAddToShelf, systemImage: "tray") }
                        Button { m.render { if case .success(let d) = $0 { onSaveAs(d) } } } label: { Label(S.resizeOutputSaveAs, systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "chevron.down") }
                        .menuStyle(.button).menuIndicator(.hidden).controlSize(.large).fixedSize().accessibilityLabel(S.outputMenuLabel).help(S.outputMenuLabel)
                }.disabled(!m.canOutput)
                // Return: yalnızca bir metin alanı düzenlenmiyorken Kopyala'yı tetikler.
                Button("") { m.render { if case .success(let d) = $0 { onCopy(d) } } }.keyboardShortcut(.defaultAction).disabled(!m.canOutput || editingField).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .frame(width: 560).tint(.smAccent)
    }
    private func field(_ title: String, value: Binding<Int>, invalid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout).foregroundStyle(Color.smSecondary)
            TextField("", value: value, format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 130).monospacedDigit().focused($editingField)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(invalid ? Color.smDestructive : .clear, lineWidth: 1.5)).accessibilityLabel(title)
        }
    }
    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.bordered).controlSize(.small).tint(active ? .smAccent : nil)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(active ? Color.smAccent : .clear, lineWidth: 1.5))
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}

final class ResizeWindowController: NSWindowController, NSWindowDelegate {
    static var current: ResizeWindowController?
    private var sizeSub: AnyCancellable?
    private let model: ResizeModel
    /// `sourceInfo` arka planda okunur, pencere ana kuyrukta kurulur; bu sürede panel meşgul gösterilir. Okunamazsa nil.
    static func load(item: ShelfItem, store: ShelfStore, panel: ShelfPresenting?, completion: @escaping (ResizeWindowController?) -> Void) {
        panel?.setBusy(S.preparingImage)
        DispatchQueue.global(qos: .userInitiated).async {
            let info = ImageResizer.sourceInfo(item.url)
            DispatchQueue.main.async {
                panel?.setBusy(nil)
                completion(ResizeWindowController(item: item, store: store, panel: panel, info: info))
            }
        }
    }
    init?(item: ShelfItem, store: ShelfStore, panel: ShelfPresenting?, info: ImageResizer.SourceInfo?) {
        guard let info = info else { return nil }
        let model = ResizeModel(source: item.url, info: info)
        self.model = model
        var closeRef: (() -> Void)?
        /// Türevi kendi klasörüne yazar; hata model üzerinde görünür kalır ve pencere kapanmaz.
        let finish: (Data, ResizeModel) -> URL? = { data, m in
            let url = ImageResizer.derivativeURL(for: m.source, size: m.target, format: m.format)
            do { try data.write(to: url, options: .atomic); return url }
            catch { Log.error("Türev yazılamadı: \(Log.describe(error))"); m.errorText = S.resizeErrorWrite; return nil }
        }
        let view = ResizeView(m: model,
            onCopy: { data in
                guard let url = finish(data, model) else { return }
                guard ClipboardPayload.make(edited: data, format: model.format, fileURL: url).write() else { model.errorText = S.resizeErrorClipboard; return } // editörle aynı pano yükü
                panel?.showToast(S.resizeDone); closeRef?()
            },
            onSaveAs: { data in
                let p = NSSavePanel(); p.nameFieldStringValue = ImageResizer.derivativeURL(for: model.source, size: model.target, format: model.format).lastPathComponent
                p.allowedContentTypes = [model.format.utType]
                p.begin { r in
                    guard r == .OK, let u = p.url, !model.cancelled else { return } // iptal: pencere açık kalır; pencere kapandıysa yazılmaz
                    do { try SafeFileCopy.write(data, to: u, source: model.source); closeRef?() }
                    catch SafeFileCopy.Failure.sameFile { model.errorText = S.saveAsSameFileBody }
                    catch { Log.error("Farklı kaydet başarısız: \(Log.describe(error))"); model.errorText = error.localizedDescription }
                }
            },
            onAddToShelf: { data in
                guard let url = finish(data, model) else { return }
                store.addDerivative(at: url, sourceItemID: item.id)
                panel?.showToast(S.resizeDone); closeRef?()
            },
            onCancel: { closeRef?() })
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = item.fileName; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false
        w.applyGlassChrome(toolbarIdentifier: "resize", subtitle: S.editFileInfo(info.pixelSize.width, info.pixelSize.height, ByteCountFormatter.string(fromByteCount: Int64(info.fileSize), countStyle: .file)))
        w.level = .floating; w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: w)
        w.delegate = self
        sizeSub = model.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self, weak model] _ in DispatchQueue.main.async { self?.apply(height: model?.preferredHeight ?? 457) } }
        apply(height: model.preferredHeight, animate: false); w.center()
        closeRef = { [weak self] in self?.close() } // temizlik `windowWillClose`ta (✕/⌘W ile aynı yol)
    }
    required init?(coder: NSCoder) { fatalError() }
    /// Her kapanış yolu (Vazgeç, Esc, ✕, ⌘W, başarılı çıktı): süren render iptal, `current` düşer (üst şerit geri çekilebilir).
    func windowWillClose(_ notification: Notification) {
        model.cancel(); sizeSub = nil
        if Self.current === self { Self.current = nil }
    }
    private func apply(height: CGFloat, animate: Bool = true) {
        guard let w = window else { return }
        let target = NSSize(width: 560, height: height)
        guard abs(w.contentRect(forFrameRect: w.frame).height - target.height) > 0.5 else { return }
        var f = w.frameRect(forContentRect: NSRect(origin: .zero, size: target)); f.origin = NSPoint(x: w.frame.minX, y: w.frame.maxY - f.height)
        w.setFrame(f, display: true, animate: animate && !ShotmoriStyle.reduceMotion)
    }
    override func showWindow(_ sender: Any?) { super.showWindow(sender); window?.orderFrontRegardless(); window?.makeKey() }
}

#if DEBUG
extension ResizeWindowController {
    /// Yalnız QA (`SHOTMORI_QA_RESIZE`, mağaza görüntüleri): `50,jpeg` → yüzde ve biçim seçilir; dosyaya yazılmaz.
    func qaApply(_ spec: String) {
        for p in spec.split(separator: ",") {
            if let v = Double(p) { model.applyPercent(v) } else if p == "jpeg" { model.format = .jpeg } else if p == "png" { model.format = .png }
        }
    }
}
#endif
