import Darwin
import Foundation
import Quartz
import QuickLookUI
import UniformTypeIdentifiers

private typealias CompileMarkdownFn = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
) -> UnsafeMutablePointer<SogoodBuffer>?

private typealias FreeBufferFn = @convention(c) (
    UnsafeMutablePointer<SogoodBuffer>?
) -> Void

private typealias SetCacheDirFn = @convention(c) (
    UnsafePointer<CChar>?
) -> Void

private final class NativeCoreBridge: @unchecked Sendable {
    static let shared = NativeCoreBridge()

    private var handle: UnsafeMutableRawPointer?
    private var compileFn: CompileMarkdownFn?
    private var freeBufferFn: FreeBufferFn?

    private init() {
        // QuickLookExtension.appex lives at:
        // SuperGoodViewer.app/Contents/PlugIns/QuickLookExtension.appex
        let appContentsURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let dylibURL = appContentsURL
            .appendingPathComponent("Frameworks", isDirectory: true)
            .appendingPathComponent("libsogood_core.dylib", isDirectory: false)

        guard let dl = dlopen(dylibURL.path, RTLD_NOW | RTLD_LOCAL) else {
            return
        }
        self.handle = dl

        if let setCacheSym = dlsym(dl, "sogood_set_cache_dir") {
            let setCacheFn = unsafeBitCast(setCacheSym, to: SetCacheDirFn.self)
            let tempCacheDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("sgv_ql_cache", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: tempCacheDir,
                withIntermediateDirectories: true
            )
            tempCacheDir.path.withCString { ptr in
                setCacheFn(ptr)
            }
        }

        if let compileSym = dlsym(dl, "sogood_compile_markdown"),
           let freeSym = dlsym(dl, "sogood_free_buffer") {
            self.compileFn = unsafeBitCast(compileSym, to: CompileMarkdownFn.self)
            self.freeBufferFn = unsafeBitCast(freeSym, to: FreeBufferFn.self)
        }
    }

    func compileMarkdownToPDF(
        markdown: String,
        title: String,
        docDir: String,
        optionsJSON: String
    ) -> Data? {
        guard let compileFn = self.compileFn,
              let freeBufferFn = self.freeBufferFn else {
            return nil
        }

        return markdown.withCString { mdPtr in
            title.withCString { titlePtr in
                docDir.withCString { dirPtr in
                    optionsJSON.withCString { optsPtr in
                        guard let bufPtr = compileFn(mdPtr, titlePtr, dirPtr, optsPtr) else {
                            return nil
                        }
                        defer {
                            freeBufferFn(bufPtr)
                        }
                        let buf = bufPtr.pointee
                        guard let dataPtr = buf.data, buf.len > 0 else {
                            return nil
                        }
                        return Data(bytes: dataPtr, count: Int(buf.len))
                    }
                }
            }
        }
    }
}

public final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    private static let maxPreviewBytes = 5 * 1024 * 1024 // 5 MB safety cap

    public func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        let fileURL = request.fileURL

        let reply = QLPreviewReply(
            dataOfContentType: .pdf,
            contentSize: CGSize(width: 800, height: 1000)
        ) { _ in
            let rawData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let cappedData = rawData.count > Self.maxPreviewBytes
                ? rawData.prefix(Self.maxPreviewBytes)
                : rawData[...]

            var markdown = String(decoding: cappedData, as: UTF8.self)
            if markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                markdown = "_(Empty Markdown Document)_"
            }

            let title = fileURL.deletingPathExtension().lastPathComponent
            let docDir = fileURL.deletingLastPathComponent().path
            let optionsJSON = Self.buildRenderOptionsJSON()

            if let pdfData = NativeCoreBridge.shared.compileMarkdownToPDF(
                markdown: markdown,
                title: title.isEmpty ? "Document" : title,
                docDir: docDir,
                optionsJSON: optionsJSON
            ) {
                return pdfData
            }

            throw NSError(
                domain: "com.sogood.sogoodviewer.QuickLookExtension",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to compile Markdown preview"]
            )
        }

        handler(reply, nil)
    }

    private static func realUserHomeDirectory() -> String? {
        if let pw = getpwuid(getuid()), let dirPtr = pw.pointee.pw_dir {
            return String(cString: dirPtr)
        }
        return nil
    }

    private static func isSystemDarkMode() -> Bool {
        if let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
            return style.caseInsensitiveCompare("Dark") == .orderedSame
        }
        return false
    }

    private static func buildRenderOptionsJSON() -> String {
        var theme = isSystemDarkMode() ? "dark" : "light"
        var mode = "fluid"
        var viewportWidth: Double = 780.0
        var fontSize: Double = 10.5
        var bodyFont: String?
        var codeFont: String?
        var imageCacheDir: String?

        if let home = realUserHomeDirectory() {
            let remoteCache = "\(home)/Library/Caches/com.sogood.sogoodviewer/remote_images"
            if FileManager.default.fileExists(atPath: remoteCache) {
                imageCacheDir = remoteCache
            }

            let prefsPath = "\(home)/Library/Application Support/com.sogood.sogoodviewer/preferences.json"
            if let prefsData = try? Data(contentsOf: URL(fileURLWithPath: prefsPath)),
               let json = try? JSONSerialization.jsonObject(with: prefsData) as? [String: Any] {
                if let themeMode = json["themeMode"] as? String {
                    if themeMode == "dark" {
                        theme = "dark"
                    } else if themeMode == "light" {
                        theme = "light"
                    }
                } else if let isDark = json["isDark"] as? Bool {
                    theme = isDark ? "dark" : "light"
                }

                if let savedSize = json["fontSize"] as? NSNumber {
                    let v = savedSize.doubleValue
                    if v >= 8.0 && v <= 28.0 {
                        fontSize = v
                    }
                }
                if let savedBody = json["bodyFont"] as? String, !savedBody.isEmpty {
                    bodyFont = savedBody
                }
                if let savedCode = json["codeFont"] as? String, !savedCode.isEmpty {
                    codeFont = savedCode
                }
                if let savedMode = json["mode"] as? String,
                   (savedMode == "fluid" || savedMode == "paginated") {
                    mode = savedMode
                }
                if let savedWidth = json["viewportWidth"] as? NSNumber {
                    let w = savedWidth.doubleValue
                    if w >= 320.0 && w <= 2400.0 {
                        viewportWidth = w
                    }
                }
            }
        }

        var dict: [String: Any] = [
            "mode": mode,
            "theme": theme,
            "viewport_width": viewportWidth,
            "font_size": fontSize,
            // Slice tall fluid documents at ~1100pt per page so macOS Quick Look
            // fits the page width naturally rather than shrinking a 10,000pt tall page.
            "fluid_page_height": 1100.0,
        ]
        if let bodyFont = bodyFont {
            dict["body_font"] = bodyFont
        }
        if let codeFont = codeFont {
            dict["code_font"] = codeFont
        }
        if let imageCacheDir = imageCacheDir {
            dict["image_cache_dir"] = imageCacheDir
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return #"{"mode":"fluid","theme":"\#(theme)","viewport_width":780.0,"font_size":10.5,"fluid_page_height":1100.0}"#
    }
}
