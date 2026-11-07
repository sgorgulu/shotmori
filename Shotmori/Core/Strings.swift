import Foundation

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
        let shown = names.prefix(6).map { "• " + $0 }.joined(separator: "\n")
        let more = names.count > 6 ? "\n" + F("trashConfirmMore", names.count - 6) : ""
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
