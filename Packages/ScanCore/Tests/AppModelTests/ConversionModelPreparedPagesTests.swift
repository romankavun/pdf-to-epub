@testable import AppModel
import Conversion
import Foundation
import ProjectStore
import Testing

@MainActor
@Suite("ConversionModel prepared pages")
struct ConversionModelPreparedPagesTests {
    private let storage = FakeStorage()

    @Test("scans are prepared into a folder of their own, which the new project takes over")
    func scansMoveIntoProject() async throws {
        let pipeline = FakePipeline(echoPages: true, prepares: true)
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(folder: folder)

        model.start()
        await model.conversionTask?.value

        let prepared = try #require(pipeline.preparedInto.values.first ?? nil)
        #expect(storage.createdDetail.first?.movingPages == true)
        #expect(model.project?.base.pageURLs.first?.path == "/documents/Sample.scanproject/pages/1.png")
        // The temporary folder goes once the project has the pages.
        #expect(!FileManager.default.fileExists(atPath: prepared.path))
    }

    @Test("clean pages are read in place: nothing moves and the unused folder goes")
    func cleanPagesStay() async throws {
        let pipeline = FakePipeline(echoPages: true)
        let model = ConversionModel(pipeline: pipeline, storage: storage)
        model.open(folder: folder)

        model.start()
        await model.conversionTask?.value

        let prepared = try #require(pipeline.preparedInto.values.first ?? nil)
        #expect(storage.createdDetail.first?.movingPages == false)
        #expect(model.project?.base.pageURLs == threePages)
        #expect(!FileManager.default.fileExists(atPath: prepared.path))
    }
}
