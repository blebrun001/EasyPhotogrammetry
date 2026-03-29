import Foundation
import Testing
@testable import Baguette

@Suite("ProcessingState")
struct ProcessingStateTests {
    @Test("status text mapping is stable")
    func statusTextMapping() {
        #expect(ProcessingState.idle.statusText == "Drop photos to start")
        #expect(ProcessingState.ready.statusText == "Ready to generate the model")
        #expect(ProcessingState.processing(progress: 0.1).statusText == "Processing...")
        #expect(ProcessingState.cancelled.statusText == "Generation cancelled")
        #expect(ProcessingState.completed(url: URL(fileURLWithPath: "/tmp/model.usdz")).statusText == "Model generated")
        #expect(ProcessingState.failed(message: "boom").statusText == "boom")
    }

    @Test("progress value is exposed only while processing")
    func progressValue() {
        #expect(ProcessingState.processing(progress: 0.42).progressValue == 0.42)
        #expect(ProcessingState.completed(url: URL(fileURLWithPath: "/tmp/model.usdz")).progressValue == 0)
    }

    @Test("presentation mapping includes tone, symbols and progress text")
    func presentationMapping() {
        let idle = ProcessingState.idle.presentation
        #expect(idle.title == "Ready")
        #expect(idle.tone == .secondary)
        #expect(idle.symbolName == nil)

        let ready = ProcessingState.ready.presentation
        #expect(ready.title == "Ready to generate")
        #expect(ready.symbolName == "checkmark.circle")
        #expect(ready.tone == .secondary)

        let processing = ProcessingState.processing(progress: 0.37).presentation
        #expect(processing.title == "Generating model")
        #expect(processing.progress == 0.37)
        #expect(processing.progressText == "37%")
        #expect(processing.tone == .secondary)

        let cancelled = ProcessingState.cancelled.presentation
        #expect(cancelled.title == "Generation cancelled")
        #expect(cancelled.symbolName == "xmark.circle.fill")

        let completed = ProcessingState.completed(url: URL(fileURLWithPath: "/tmp/model.usdz")).presentation
        #expect(completed.title == "Model generated")
        #expect(completed.symbolName == "checkmark.circle.fill")
        #expect(completed.tone == .success)

        let failed = ProcessingState.failed(message: "reason").presentation
        #expect(failed.title == "Generation failed")
        #expect(failed.detail == "reason")
        #expect(failed.symbolName == "exclamationmark.triangle.fill")
        #expect(failed.tone == .error)
    }
}
