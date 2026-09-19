import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let tangentDiaryXML = UTType.xml
}

struct SettingsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.tangentDiaryXML] }

    let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
