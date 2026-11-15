import Foundation
import Importing
import OCR

extension ConversionModel {
    /// The name of the document an input stands for: a folder's own name, a
    /// PDF's or a project's without the extension.
    static func documentName(for url: URL) -> String {
        let name = url.lastPathComponent
        let isPDF = PDFImporter.isPDF(url) && !isDirectory(url)
        return isPDF || url.pathExtension == "scanproject" ? url.deletingPathExtension().lastPathComponent : name
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func failure(for error: any Error) -> Failure {
        switch error {
        case ImportError.notADirectory: .notAFolder
        case ImportError.noImages: .noImages
        case PDFImportError.unreadable: .pdfUnreadable
        case PDFImportError.passwordRequired: .pdfPasswordRequired
        case PDFImportError.noPages: .pdfNoPages
        case OCRError.timedOut: .recognitionTimedOut
        default: .other(String(describing: error))
        }
    }
}
