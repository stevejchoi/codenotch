import XCTest
import SwiftUI
@testable import Codenotch

final class OllamaUsageTests: XCTestCase {
    func testEmptyListingIsAReadingWithoutAQuota() throws {
        let reading = try OllamaUsage.parse(Data(#"{"models":[]}"#.utf8))
        let snapshot = ollamaSnapshot(reading)
        XCTAssertTrue(snapshot.hasReading)
        XCTAssertTrue(snapshot.notchSnapshots.isEmpty)
        XCTAssertNil(snapshot.ringFraction)
        XCTAssertTrue(snapshot.statusMessage?.contains("No models loaded") == true)
    }

    func testPreservesReportedUnitsAndMissingFields() throws {
        let data = Data(#"{"models":[{"name":"z-model","size":6442450944,"size_vram":4294967296,"context_length":32768},{"name":"a-model"}]}"#.utf8)
        let reading = try OllamaUsage.parse(data)
        XCTAssertEqual(reading.models.map(\.name), ["a-model", "z-model"])
        XCTAssertNil(reading.models[0].memoryBytes)
        XCTAssertNil(reading.models[0].contextLength)
        XCTAssertEqual(reading.models[1].memoryBytes, 6_442_450_944)
        XCTAssertEqual(reading.models[1].gpuMemoryBytes, 4_294_967_296)
        XCTAssertEqual(reading.models[1].contextLength, 32_768)
        XCTAssertNil(ollamaSnapshot(reading).usedFraction)
        XCTAssertTrue(ollamaSnapshot(reading).windows.isEmpty)
    }

    func testMalformedListingsAreNotEmptySuccesses() {
        for payload in ["{}", "{\"models\":null}", "not json",
                        #"{"models":[{"name":" "}]}"#,
                        #"{"models":[{"name":"a","size":-1}]}"#,
                        #"{"models":[{"name":"a","size_vram":-1}]}"#,
                        #"{"models":[{"name":"a","context_length":0}]}"#,
                        #"{"models":[{"name":"a"},{"name":"a"}]}"#] {
            XCTAssertThrowsError(try OllamaUsage.parse(Data(payload.utf8)), payload)
        }
    }

    func testOnlyLocalHTTPOriginsAreAccepted() throws {
        XCTAssertEqual(try OllamaEndpoint.parse(" http://localhost:11434/ ").absoluteString,
                       "http://127.0.0.1:11434")
        XCTAssertEqual(try OllamaEndpoint.parse("http://[::1]:11434").port, 11434)
        for address in ["https://127.0.0.1:11434", "http://192.168.1.2:11434",
                        "http://127.0.0.1.example.com", "http://user:pass@localhost:11434",
                        "http://localhost:11434/api", "http://localhost:11434?x=y",
                        "http://localhost:11434#x", "http://localhost:0", "file:///tmp/a"] {
            XCTAssertThrowsError(try OllamaEndpoint.parse(address), address)
        }
    }
}

@MainActor
final class OllamaModelCellTests: XCTestCase {
    func testEachModelHasItsOwnMemoryReadingAndSharesTheRuntimeRefresh() throws {
        let reading = try OllamaUsage.parse(Data(#"{"models":[{"name":"llama3.1:8b","size":4831838208,"context_length":2048},{"name":"qwen3:8b","size":6442450944}]}"#.utf8))
        let cloud = ProviderSnapshot(id: "cloud", displayName: "Cloud", glyph: .claude,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.4)])
        let model = NotchViewModel()
        model.updateSnapshots([cloud, ollamaSnapshot(reading)])
        XCTAssertEqual(model.snapshots.count, 3)
        XCTAssertEqual(model.snapshots[0], cloud)
        XCTAssertEqual(model.snapshots.dropFirst().map(\.providerID), ["ollama", "ollama"])
        XCTAssertEqual(model.snapshots.dropFirst().map(\.headlineText), ["— tok/s", "— tok/s"])
        XCTAssertEqual(Set(model.snapshots.map(\.id)).count, 3)
        XCTAssertTrue(model.snapshots.dropFirst().allSatisfy { $0.ringFraction == nil })
        XCTAssertEqual(model.snapshots[1].localModel?.contextText, "2,048 tokens")
        XCTAssertEqual(model.snapshots[2].localModel?.contextText, "Unavailable")
    }

    func testHoverKeepsTheSameModelWhenNeighborsChangeAndClearsOnUnload() throws {
        let model = NotchViewModel()
        func update(_ names: [String]) throws {
            let data = try JSONSerialization.data(withJSONObject: ["models": names.map { ["name": $0] }])
            model.updateSnapshots([ollamaSnapshot(try OllamaUsage.parse(data))])
        }
        try update(["b-model", "a-model"])
        model.hoveredIndex = 1
        let selectedID = model.hoveredSnapshot?.id
        try update(["b-model"])
        XCTAssertEqual(model.hoveredIndex, 0)
        XCTAssertEqual(model.hoveredSnapshot?.id, selectedID)
        try update(["c-model"])
        XCTAssertNil(model.hoveredIndex)
        try update([])
        XCTAssertTrue(model.snapshots.isEmpty)
    }

    func testUnavailableRuntimeDoesNotLeavePhantomModelCells() {
        let failure = ProviderSnapshot(id: "ollama", displayName: "Ollama", glyph: .ollama,
            fidelity: .official, status: .error("Unavailable"), windows: [], kind: .localRuntime)
        XCTAssertTrue(failure.notchSnapshots.isEmpty)
        XCTAssertNotNil(failure.statusMessage, "The connection problem must remain available in Settings")
    }

    func testUnknownAndSmallMemoryReadingsAreNotModelCountsOrZeroes() throws {
        let data = Data(#"{"models":[{"name":"a"},{"name":"b","size":536870912}]}"#.utf8)
        let cells = ollamaSnapshot(try OllamaUsage.parse(data)).notchSnapshots
        XCTAssertEqual(cells.map(\.headlineText), ["— tok/s", "— tok/s"])
        XCTAssertTrue(cells[0].hasReading)
        XCTAssertTrue(cells[0].localModel?.detail.contains("RAM unavailable") == true)
    }
}

@MainActor
final class LocalModelBrandTests: XCTestCase {
    func testDetectsBrandsAcrossVersionsTagsAndNamespaces() {
        let cases: [(String, LocalModelBrand)] = [
            ("qwen3:0.6b", .qwen), ("Qwen/Qwen2.5-Coder-7B-Instruct:Q4_K_M", .qwen),
            ("qwq:32b", .qwen), ("gemma3:270m", .gemma),
            ("google/gemma-3-1b-it-GGUF", .gemma), ("embeddinggemma:latest", .gemma),
            ("llama3.2:1b", .llama), ("meta-llama/Llama-3.1-8B-Instruct", .llama),
            ("hf.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF:Q4_K_M", .llama),
            ("deepseek-r1:1.5b", .deepseek),
            ("hf.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF:Q4_K_M", .deepseek),
            ("DeepSeek-R1-Distill-Llama-8B", .deepseek),
            ("mistral:7b", .mistral), ("ministral-3:3b", .mistral),
            ("mistralai/Ministral-3-3B-Instruct-2512", .mistral),
            ("mixtral:8x7b", .mistral), ("devstral-small:24b", .mistral)
        ]
        for (name, expected) in cases {
            XCTAssertEqual(LocalModelBrand.detect(modelName: name), expected, name)
        }
    }

    func testUnknownNamesAndLookalikesKeepTheOllamaFallback() throws {
        for name in ["my-local-model:latest", "someone/my-qwen-helper:8b", "qwenish:latest",
                     "gemmaverse:latest", "llamafile:latest", "mistralicious:latest", "", "  "] {
            XCTAssertNil(LocalModelBrand.detect(modelName: name), name)
        }
        let data = Data(#"{"models":[{"name":"my-local-model","details":{"family":"llama"}}]}"#.utf8)
        let snapshot = ollamaSnapshot(try OllamaUsage.parse(data))
        XCTAssertEqual(snapshot.notchSnapshots.first?.glyph, .ollama)
    }

    func testBrandIconsDoNotChangeTheRuntimeConnectionOrModelIdentity() throws {
        let data = Data(#"{"models":[{"name":"deepseek-r1:1.5b","details":{"family":"qwen2"}}]}"#.utf8)
        let runtime = ollamaSnapshot(try OllamaUsage.parse(data))
        let cell = try XCTUnwrap(runtime.notchSnapshots.first)
        XCTAssertEqual(runtime.glyph, .ollama)
        XCTAssertEqual(cell.glyph, .deepseek)
        XCTAssertEqual(cell.localModel?.brand, .deepseek)
        XCTAssertEqual(cell.providerID, "ollama")
        XCTAssertEqual(cell.id, "ollama:model:deepseek-r1:1.5b")
        XCTAssertNil(cell.ringFraction)
    }

    func testEverySupportedBrandHasABundledVectorAsset() throws {
        for brand in LocalModelBrand.allCases {
            let asset = try XCTUnwrap(NSImage(named: brand.glyph.assetName), brand.rawValue)
            XCTAssertGreaterThan(asset.size.width, 0)
            XCTAssertGreaterThan(asset.size.height, 0)
            // Unsupported SVG root attributes can resolve an asset but render
            // a solid placeholder square. Check the native template's alpha.
            let renderer = ImageRenderer(content: ProviderGlyphView(glyph: brand.glyph, size: 32)
                .foregroundStyle(.white))
            let data = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            var inkPixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { inkPixels += 1 }
                }
            }
            let coverage = Double(inkPixels) / Double(bitmap.pixelsWide * bitmap.pixelsHigh)
            XCTAssertGreaterThan(coverage, 0.05, brand.rawValue)
            XCTAssertLessThan(coverage, 0.85, brand.rawValue)
        }
        XCTAssertNotNil(Bundle.main.url(forResource: "LobeIcons-LICENSE", withExtension: "txt"))
    }
}

@MainActor
final class OllamaProviderTests: XCTestCase {
    func testTransportUsesOnlyTheReadOnlyListing() async throws {
        let requested = expectation(description: "listing")
        let provider = makeProvider { request in
            XCTAssertEqual(request.url?.path, "/api/ps")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertEqual(request.timeoutInterval, 3)
            requested.fulfill()
            return (200, Data(#"{"models":[]}"#.utf8))
        }
        let snapshot = try await provider.fetchSnapshot()
        await fulfillment(of: [requested], timeout: 1)
        XCTAssertEqual(snapshot.kind, .localRuntime)
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertTrue(snapshot.hasReading)
        XCTAssertNil(provider.account())
    }

    func testTransportAndHTTPFailuresStayVisible() async {
        for status in [301, 401, 404, 500] {
            let provider = makeProvider { _ in (status, Data()) }
            do {
                _ = try await provider.fetchSnapshot()
                XCTFail("HTTP \(status) succeeded")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("HTTP \(status)"))
            }
        }
        let provider = makeProvider { _ in throw URLError(.timedOut) }
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("Timeout succeeded")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("unavailable"))
        }
    }

    func testSessionDoesNotStoreCredentialsOrFollowRedirects() {
        let session = OllamaProvider.makeSession()
        defer { session.invalidateAndCancel() }
        XCTAssertNil(session.configuration.httpCookieStorage)
        XCTAssertNil(session.configuration.urlCredentialStorage)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
        let url = URL(string: "http://127.0.0.1:11434/api/ps")!
        let task = session.dataTask(with: url)
        OllamaRedirectPolicy().urlSession(session, task: task,
            willPerformHTTPRedirection: HTTPURLResponse(url: url, statusCode: 302,
                httpVersion: nil, headerFields: nil)!,
            newRequest: URLRequest(url: URL(string: "https://example.com")!)) { request in
                XCTAssertNil(request)
            }
    }

    private func makeProvider(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> OllamaProvider {
        OllamaStubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OllamaStubProtocol.self]
        return OllamaProvider(endpoint: URL(string: OllamaEndpoint.defaultAddress)!,
                              session: URLSession(configuration: configuration))
    }
}

private final class OllamaStubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!,
                statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class OllamaLifecycleTests: XCTestCase {
    func testOptInMigrationRunsOnceAndPreservesOtherChoices() {
        let defaults = isolatedDefaults()
        defaults.set(["cursor"], forKey: "hiddenProviders")
        let first = Preferences(defaults: defaults)
        XCTAssertFalse(first.isConnected("ollama"))
        XCTAssertFalse(first.isConnected("cursor"))
        XCTAssertTrue(first.isConnected("codex"))
        first.setConnected(true, for: "ollama")
        XCTAssertTrue(Preferences(defaults: defaults).isConnected("ollama"))
    }

    func testRuntimeNeverUsesTheQuotaArchiveAndFailureClearsItImmediately() async {
        let defaults = isolatedDefaults()
        let provider = RuntimeStub()
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults))
        await store.refresh()
        XCTAssertTrue(store.snapshots[0].hasReading)
        XCTAssertTrue(UsageArchive(defaults: defaults).load().isEmpty)
        let relaunched = UsageStore(providers: [provider], archive: UsageArchive(defaults: defaults))
        XCTAssertFalse(relaunched.snapshots[0].hasReading)
        provider.fails = true
        await store.refresh()
        XCTAssertNil(store.snapshots[0].localRuntime)
        XCTAssertTrue(store.snapshots[0].statusMessage?.contains("unavailable") == true)
    }

    func testDisabledRuntimeMakesNoRequests() async {
        let provider = RuntimeStub()
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: isolatedDefaults()),
                               disconnected: ["ollama"])
        await store.refresh()
        store.refreshLocalRuntimes()
        store.refresh(providerID: "ollama")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(provider.calls, 0)
        XCTAssertTrue(store.snapshots.isEmpty)
    }

    func testLateResponseCannotRestoreDisabledRuntime() async {
        let provider = RuntimeStub()
        provider.suspended = true
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: isolatedDefaults()))
        let pass = Task { await store.refresh() }
        await started(provider)
        store.disconnected = ["ollama"]
        provider.finish()
        await pass.value
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.refreshing.isEmpty)
    }

    func testFullAndLocalRefreshCoalesce() async {
        let provider = RuntimeStub()
        provider.suspended = true
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: isolatedDefaults()))
        store.refreshLocalRuntimes()
        await started(provider)
        let pass = Task { await store.refresh() }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(provider.calls, 1)
        provider.finish()
        await pass.value
        XCTAssertTrue(store.snapshots[0].hasReading)
    }

    func testReconnectingIgnoresThePreviousConnectionResponse() async {
        let provider = RuntimeStub()
        provider.suspended = true
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: isolatedDefaults()))
        let first = Task { await store.refresh() }
        await started(provider)
        store.disconnected = ["ollama"]
        store.disconnected = []
        for _ in 0..<100 {
            if provider.calls == 2 { break }
            await Task.yield()
        }
        XCTAssertEqual(provider.calls, 2)
        provider.finish()
        await first.value
        XCTAssertFalse(store.snapshots[0].hasReading, "The cancelled request restored a reading")
        XCTAssertTrue(store.refreshing.contains("ollama"))
        provider.finish()
        await store.refresh()
        XCTAssertTrue(store.snapshots[0].hasReading)
    }

    func testLocalResultIsPublishedWhileACloudRequestIsStillPending() async {
        let cloud = RuntimeStub(id: "cloud", kind: .usage)
        cloud.suspended = true
        let local = RuntimeStub()
        let store = UsageStore(providers: [cloud, local], archive: UsageArchive(defaults: isolatedDefaults()))
        let pass = Task { await store.refresh() }
        await started(cloud)
        for _ in 0..<100 {
            if store.snapshots.last?.hasReading == true { break }
            await Task.yield()
        }
        XCTAssertTrue(store.snapshots.last?.hasReading == true)
        XCTAssertTrue(store.refreshing.contains("cloud"))
        cloud.finish()
        await pass.value
    }

    func testLocalTicksDoNotFetchOrStarveCloudProviders() async throws {
        let local = RuntimeStub()
        let cloud = QuotaStub()
        let store = UsageStore(providers: [cloud, local], refreshInterval: 0.02,
                               idleRefreshInterval: 0.05, archive: UsageArchive(defaults: isolatedDefaults()))
        store.refreshLocalRuntimes()
        await started(local)
        XCTAssertEqual(cloud.calls, 0)
        store.start()
        defer { store.stop() }
        for _ in 0..<20 {
            store.refreshLocalRuntimes()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThanOrEqual(cloud.calls, 2)
        XCTAssertEqual(store.snapshots.map(\.id), ["cloud", "ollama"])
    }

    func testChangingEndpointClearsOldReadingAndDoesNotEnableMonitoring() async throws {
        let provider = OllamaProvider(endpoint: try OllamaEndpoint.parse(OllamaEndpoint.defaultAddress))
        let store = UsageStore(providers: [provider], archive: UsageArchive(defaults: isolatedDefaults()),
                               disconnected: ["ollama"])
        let updated = try OllamaEndpoint.parse("http://127.0.0.1:11435")
        store.updateOllamaEndpoint(updated)
        XCTAssertEqual(provider.endpoint, updated)
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.refreshing.isEmpty)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "OllamaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func started(_ provider: RuntimeStub) async {
        for _ in 0..<100 {
            if provider.calls > 0 { return }
            await Task.yield()
        }
        XCTFail("Provider did not start")
    }
}

@MainActor
private final class RuntimeStub: UsageProvider {
    nonisolated let id: String
    nonisolated let displayName = "Ollama"
    nonisolated let glyph = ProviderGlyph.ollama
    nonisolated let kind: ProviderKind
    var calls = 0
    var fails = false
    var suspended = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    init(id: String = "ollama", kind: ProviderKind = .localRuntime) {
        self.id = id
        self.kind = kind
    }
    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        if suspended { await withCheckedContinuation { continuations.append($0) } }
        if fails { throw OllamaError.unavailable }
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
                                fidelity: .official, status: .ok, windows: [],
                                kind: kind, localRuntime: LocalRuntimeReading(models: [], observedAt: Date()))
    }
    func finish() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

@MainActor
private final class QuotaStub: UsageProvider {
    nonisolated let id = "cloud"
    nonisolated let displayName = "Cloud"
    nonisolated let glyph = ProviderGlyph.claude
    var calls = 0
    func fetchSnapshot() async throws -> ProviderSnapshot {
        calls += 1
        return ProviderSnapshot(id: id, displayName: displayName, glyph: glyph,
            fidelity: .official, status: .ok,
            windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.4)])
    }
}

private func ollamaSnapshot(_ reading: LocalRuntimeReading) -> ProviderSnapshot {
    ProviderSnapshot(id: "ollama", displayName: "Ollama", glyph: .ollama,
                     fidelity: .official, status: .ok, windows: [],
                     kind: .localRuntime, localRuntime: reading)
}

@MainActor
final class OllamaRenderTests: XCTestCase {
    func testLocalCardsFitTheExistingPanelBudgetOnEveryEdge() throws {
        let models = (0..<8).map { index in
            LocalRuntimeReading.Model(id: "m\(index)", name: "example/long-model-name-\(index):latest",
                memoryBytes: 6_442_450_944, gpuMemoryBytes: nil, contextLength: 32_768)
        }
        let snapshots = ollamaSnapshot(LocalRuntimeReading(models: models, observedAt: Date())).notchSnapshots
        XCTAssertEqual(snapshots.count, models.count)
        for (index, snapshot) in snapshots.enumerated() {
            let height = NotchLayout.cardHeight(windowCount: 0, localModelName: snapshot.localModel?.name)
            XCTAssertLessThanOrEqual(height, NotchLayout.maxCardHeight(sessionCap: 0))
            for edge in NotchEdge.allCases {
                let view = TooltipCard(snapshot: snapshot, now: Date(), direction: edge.tooltipDirection)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertGreaterThan(image.size.height, 0)
                try save(image, name: "ollama-model-\(index)-\(edge.rawValue).png")
            }
        }
    }

    func testLiveLocalListingWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODENOTCH_OLLAMA_LIVE"] == "1" else {
            throw XCTSkip("Opt-in live Ollama check")
        }
        let provider = OllamaProvider(endpoint: try OllamaEndpoint.parse(OllamaEndpoint.defaultAddress))
        let snapshot = try await provider.fetchSnapshot()
        XCTAssertTrue(snapshot.hasReading)
        XCTAssertNil(snapshot.ringFraction)
        if let expectedName = ProcessInfo.processInfo.environment["CODENOTCH_OLLAMA_EXPECTED_MODEL"],
           let expectedBrand = ProcessInfo.processInfo.environment["CODENOTCH_OLLAMA_EXPECTED_BRAND"] {
            let cell = try XCTUnwrap(snapshot.notchSnapshots.first { $0.localModel?.name == expectedName })
            XCTAssertEqual(cell.localModel?.brand?.rawValue ?? "ollama", expectedBrand)
            XCTAssertEqual(cell.glyph, cell.localModel?.brand?.glyph ?? .ollama)
            XCTAssertEqual(cell.providerID, "ollama")
        }
        for (index, cell) in snapshot.notchSnapshots.enumerated() {
            XCTAssertNotNil(cell.localModel)
            let renderer = ImageRenderer(content: TooltipCard(snapshot: cell, now: Date()))
            renderer.scale = 2
            try save(XCTUnwrap(renderer.nsImage), name: "ollama-model-live-\(index).png")
        }
    }

    func testSettingsAndNotchRenderWithTheLocalStore() async throws {
        let domain = "OllamaSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        let store = UsageStore(providers: [RuntimeStub()], archive: UsageArchive(defaults: defaults),
                               disconnected: preferences.disconnectedProviders)
        for enabled in [false, true] {
            preferences.setConnected(enabled, for: "ollama")
            store.disconnected = preferences.disconnectedProviders
            if enabled { await store.refresh() }
            let content = OllamaSettingsRow(preferences: preferences, store: store)
                .padding(20).frame(width: 460).background(Color(nsColor: .windowBackgroundColor))
            let hosting = NSHostingView(rootView: content)
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            let image = NSImage(size: hosting.bounds.size)
            image.addRepresentation(rep)
            try save(image, name: "ollama-settings-\(enabled ? "on" : "off").png")
        }
        let model = NotchViewModel()
        let models = [
            LocalRuntimeReading.Model(id: "llama3.1:8b", name: "llama3.1:8b",
                memoryBytes: 4_831_838_208, gpuMemoryBytes: nil, contextLength: 2_048),
            LocalRuntimeReading.Model(id: "qwen3:8b", name: "qwen3:8b",
                memoryBytes: 6_442_450_944, gpuMemoryBytes: nil, contextLength: 8_192)
        ]
        model.updateSnapshots([ollamaSnapshot(LocalRuntimeReading(models: models, observedAt: Date()))])
        XCTAssertEqual(model.snapshots.count, 2)
        model.isExpanded = true
        model.hoveredIndex = 0
        for edge in NotchEdge.allCases {
            model.edge = edge
            let size = model.panelSize
            let renderer = ImageRenderer(content: NotchRootView(model: model)
                .frame(width: size.width, height: size.height))
            renderer.scale = 2
            try save(XCTUnwrap(renderer.nsImage), name: "ollama-notch-\(edge.rawValue).png")
        }
    }

    func testMixedCloudAndLocalCellsRenderOnEveryEdge() throws {
        let clouds = [ProviderGlyph.claude, .openai, .cursor].map { glyph in
            ProviderSnapshot(id: glyph.rawValue, displayName: glyph.rawValue,
                glyph: glyph, fidelity: .official, status: .ok,
                windows: [LimitWindow(id: "session", label: "Session", usedFraction: 0.4)])
        }
        let reading = try OllamaUsage.parse(Data(#"{"models":[{"name":"a-long-model-name/with-a-long-variant:8b","size":4831838208,"context_length":2048},{"name":"b-model:8b","size":15569256448,"context_length":8192},{"name":"c-model:8b"}]}"#.utf8))
        let controller = NotchWindowController()
        let model = controller.model
        model.updateSnapshots(clouds + [ollamaSnapshot(reading)])
        model.isExpanded = true
        model.screenSize = CGSize(width: 1512, height: 982)
        model.screenUsableSize = CGSize(width: 1512, height: 900)
        XCTAssertEqual(model.snapshots.count, 6)
        for edge in NotchEdge.allCases {
            model.edge = edge
            XCTAssertGreaterThan(model.cellSpacing, 0)
            for index in model.snapshots.indices {
                let centre = model.slack + model.ringCenter(index: index)
                XCTAssertEqual(controller.cellIndex(along: centre), index)
                XCTAssertEqual(controller.cellIndex(along: centre + model.cellPitch / 2 - 0.01), index)
            }
            for index in [3, 5] {
                model.hoveredIndex = index
                let size = model.panelSize
                XCTAssertLessThanOrEqual(size.width, model.screenSize.width)
                XCTAssertLessThanOrEqual(size.height, model.screenSize.height + 0.001)
                let renderer = ImageRenderer(content: NotchRootView(model: model)
                    .frame(width: size.width, height: size.height))
                renderer.scale = 2
                try save(XCTUnwrap(renderer.nsImage), name: "ollama-mixed-\(edge.rawValue)-\(index).png")
            }
        }
        model.updateSnapshots([])
        model.isHoveringSettings = true
        let size = model.panelSize
        let renderer = ImageRenderer(content: NotchRootView(model: model)
            .frame(width: size.width, height: size.height))
        renderer.scale = 2
        try save(XCTUnwrap(renderer.nsImage), name: "ollama-empty-settings.png")
    }

    func testBrandIconsAndRuntimeLabelsRenderTogether() throws {
        let names = ["qwen3:0.6b", "gemma3:270m", "llama3.2:1b",
                     "deepseek-r1:1.5b", "ministral-3:3b", "my-custom-model:latest"]
        let models = names.map { LocalRuntimeReading.Model(id: $0, name: $0,
            memoryBytes: 1_610_612_736, gpuMemoryBytes: nil, contextLength: 2_048) }
        let runtime = ollamaSnapshot(LocalRuntimeReading(models: models, observedAt: Date()))
        let model = NotchViewModel()
        model.updateSnapshots([runtime])
        model.isExpanded = true
        model.screenSize = CGSize(width: 1920, height: 1080)
        model.screenUsableSize = CGSize(width: 1920, height: 1000)
        for edge in NotchEdge.allCases {
            model.edge = edge
            model.hoveredIndex = 0
            let size = model.panelSize
            let renderer = ImageRenderer(content: NotchRootView(model: model)
                .frame(width: size.width, height: size.height))
            renderer.scale = 2
            try save(XCTUnwrap(renderer.nsImage), name: "ollama-brands-\(edge.rawValue).png")
        }
        for cell in model.snapshots {
            let renderer = ImageRenderer(content: TooltipCard(snapshot: cell, now: Date()))
            renderer.scale = 2
            try save(XCTUnwrap(renderer.nsImage),
                     name: "ollama-brand-\(cell.localModel?.brand?.rawValue ?? "fallback")-tooltip.png")
        }
    }

    private func save(_ image: NSImage, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["OLLAMA_RENDER_DIRECTORY"] else { return }
        let data = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
}
