import Combine
import Foundation

final class SessionStore: ObservableObject {
    @Published private(set) var rows: [SessionRow] = []
    @Published private(set) var candidates: [DesktopSession] = []
    @Published private(set) var replyKey: String?
    @Published private(set) var detail: String?
    @Published private(set) var sendStatus: String?
    @Published private(set) var pickerOpen = false
    @Published private(set) var shortcutsOpen = false

    private let source: SessionSource
    private var decidedRequestIds = Set<String>()
    private var timer: Timer?
    private var ticks = 0
    private var refreshing = false
    private var refreshAgain = false
    private let queue = DispatchQueue(label: "claude-widget.refresh", qos: .userInitiated)

    init(source: SessionSource) {
        self.source = source
    }

    func start() {
        source.prepare()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        source.shutdown()
    }

    func open(_ row: SessionRow) {
        source.markSeen(row)
        source.jump(row)
        refresh()
    }

    var replyRow: SessionRow? { rows.first { $0.key == replyKey } }

    func openReply(_ row: SessionRow) {
        sendStatus = nil
        replyKey = row.key
        refresh()
    }

    func openPicker() {
        ticks = 0
        refresh()
        pickerOpen = true
    }

    func openShortcuts() { shortcutsOpen = true }

    func closeShortcuts() { shortcutsOpen = false }

    func closePicker() {
        pickerOpen = false
    }

    func closeReply() {
        replyKey = nil
        detail = nil
        sendStatus = nil
    }

    func send(_ text: String, to row: SessionRow) -> Bool {
        do {
            try source.send(row, text)
            source.markSeen(row)
            closeReply()
            refresh()
            return true
        } catch {
            sendStatus = error.localizedDescription
            return false
        }
    }

    func remove(_ row: SessionRow) {
        source.remove(row)
        ticks = 0
        refresh()
    }

    func add(_ session: DesktopSession) {
        source.add(session)
        ticks = 0
        refresh()
    }

    func decide(_ request: PermissionRequest, _ decision: PermissionDecision) {
        decidedRequestIds.insert(request.id)
        source.decide(request, decision)
        refresh()
    }

    private func refresh() {
        guard !refreshing else {
            refreshAgain = true
            return
        }
        refreshing = true
        let wantedKey = replyKey
        let includeCandidates = ticks % 5 == 0
        ticks += 1
        let source = self.source
        queue.async { [weak self] in
            source.housekeeping()
            let loaded = source.load()
            let candidates = includeCandidates ? source.candidates() : nil
            let detail = wantedKey.flatMap { key in loaded.first { $0.key == key } }.flatMap(source.detail)
            DispatchQueue.main.async { self?.apply(loaded, candidates: candidates, detail: detail, wantedKey: wantedKey) }
        }
    }

    private func apply(_ loaded: [SessionRow], candidates latestCandidates: [DesktopSession]?, detail latestDetail: String?, wantedKey: String?) {
        decidedRequestIds.formIntersection(loaded.flatMap { $0.requests.map(\.id) })
        let latest = loaded.map { $0.withoutRequests(in: decidedRequestIds) }
        if latest != rows { rows = latest }
        if let latestCandidates, latestCandidates != candidates { candidates = latestCandidates }
        if let key = replyKey {
            if !latest.contains(where: { $0.key == key }) {
                closeReply()
            } else if key == wantedKey, latestDetail != detail {
                detail = latestDetail
            }
        }
        refreshing = false
        if refreshAgain {
            refreshAgain = false
            refresh()
        }
    }
}
