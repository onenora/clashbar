import Foundation

@MainActor
extension AppState {
    func startPolling() {
        teardownStreams()
        ensurePeriodicTasksForCurrentVisibility()
        updateDataAcquisitionPolicy()
    }

    func cancelPolling() {
        teardownStreams()
    }

    func teardownStreams() {
        mediumFrequencyTask?.cancel()
        lowFrequencyTask?.cancel()
        for kind in StreamKind.allCases {
            cancelStream(kind)
        }
        mediumFrequencyTask = nil
        lowFrequencyTask = nil
        currentConnectionsStreamIntervalMilliseconds = nil
    }

    func startPeriodicTask(
        intervalProvider: @escaping (AppState) -> UInt64,
        operation: @escaping (AppState) async -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await operation(self)
                do {
                    let interval = max(1_000_000_000, intervalProvider(self))
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
            }
        }
    }

    func ensurePeriodicTasksForCurrentVisibility() {
        if isPanelPresented {
            if mediumFrequencyTask == nil {
                mediumFrequencyTask = startPeriodicTask(intervalProvider: { state in
                    state.mediumFrequencyIntervalNanoseconds
                }) { state in
                    await state.refreshMediumFrequency()
                }
            }

            if lowFrequencyTask == nil {
                lowFrequencyTask = startPeriodicTask(intervalProvider: { state in
                    state.lowFrequencyIntervalNanoseconds
                }) { state in
                    await state.refreshLowFrequency()
                }
            }
            return
        }

        mediumFrequencyTask?.cancel()
        lowFrequencyTask?.cancel()
        mediumFrequencyTask = nil
        lowFrequencyTask = nil
    }

    func refreshFromAPI(includeSlowCalls: Bool) async {
        await refreshHighFrequency()
        await refreshMediumFrequency()
        if includeSlowCalls {
            await refreshLowFrequency()
        }
    }

    func refreshHighFrequency() async {
        updateDataAcquisitionPolicy()
    }

    func setPanelVisibility(_ presented: Bool) {
        guard isPanelPresented != presented else { return }
        isPanelPresented = presented
        if !presented {
            cancelProxyPortsAutoSave()
            clearTrafficPresentationHistory()
            releasePanelCachedData()
        }
        trimInMemoryLogsForCurrentVisibility()
        updateDataAcquisitionPolicy()

        guard presented else { return }
        Task {
            await refreshForActivatedTab(activeMenuTab)
        }
    }

    func setActiveMenuTab(_ tab: MenuPanelTabHint) {
        let changed = activeMenuTab != tab
        activeMenuTab = tab
        updateDataAcquisitionPolicy()

        guard changed else { return }
        Task {
            await refreshForActivatedTab(tab)
        }
    }

    func desiredDataAcquisitionPolicy(
        panelPresented: Bool,
        activeTab: MenuPanelTabHint
    ) -> DataAcquisitionPolicy {
        if !panelPresented {
            return DataAcquisitionPolicy(
                enableTrafficStream: true,
                enableMemoryStream: false,
                enableConnectionsStream: false,
                connectionsIntervalMilliseconds: nil,
                enableLogsStream: false,
                mediumFrequencyIntervalNanoseconds: backgroundMediumFrequencyIntervalNanoseconds,
                lowFrequencyIntervalNanoseconds: backgroundLowFrequencyIntervalNanoseconds
            )
        }

        let lowFrequencyInterval: UInt64
        switch activeTab {
        case .proxy, .rules:
            lowFrequencyInterval = foregroundLowFrequencyPrimaryTabsIntervalNanoseconds
        default:
            lowFrequencyInterval = foregroundLowFrequencyOtherTabsIntervalNanoseconds
        }

        let memoryEnabled = activeTab == .proxy
        let connectionsEnabled = (activeTab == .proxy || activeTab == .activity)
        let logsEnabled = activeTab == .logs

        return DataAcquisitionPolicy(
            enableTrafficStream: true,
            enableMemoryStream: memoryEnabled,
            enableConnectionsStream: connectionsEnabled,
            connectionsIntervalMilliseconds: connectionsEnabled ? 1000 : nil,
            enableLogsStream: logsEnabled,
            mediumFrequencyIntervalNanoseconds: foregroundMediumFrequencyIntervalNanoseconds,
            lowFrequencyIntervalNanoseconds: lowFrequencyInterval
        )
    }

    func updateDataAcquisitionPolicy() {
        guard processManager.isRunning else {
            ensurePeriodicTasksForCurrentVisibility()
            mediumFrequencyIntervalNanoseconds = foregroundMediumFrequencyIntervalNanoseconds
            lowFrequencyIntervalNanoseconds = foregroundLowFrequencyPrimaryTabsIntervalNanoseconds
            return
        }

        let policy = desiredDataAcquisitionPolicy(
            panelPresented: isPanelPresented,
            activeTab: activeMenuTab
        )

        mediumFrequencyIntervalNanoseconds = policy.mediumFrequencyIntervalNanoseconds
        lowFrequencyIntervalNanoseconds = policy.lowFrequencyIntervalNanoseconds
        ensurePeriodicTasksForCurrentVisibility()
        applyStreamPolicy(policy)
    }

    func refreshForActivatedTab(_ tab: MenuPanelTabHint) async {
        guard processManager.isRunning else { return }

        switch tab {
        case .proxy:
            await refreshMediumFrequency()
            if proxyProvidersDetail.isEmpty || ruleItems.isEmpty {
                await refreshProvidersAndRules()
            }
        case .rules:
            await refreshProvidersAndRules()
        case .activity:
            await refreshConnections()
        case .logs:
            break
        case .system:
            await refreshMediumFrequency()
            await refreshSystemProxyStatus()
        }
    }

    func refreshMediumFrequency() async {
        guard isPanelPresented else { return }
        await runRefresh {
            let client = try self.clientOrThrow()
            if self.activeMenuTab == .proxy {
                async let versionTask: VersionInfo = client.request(.version)
                async let configTask: ConfigSnapshot = client.request(.getConfigs)
                async let groupsTask: ProxyGroupsResponse = client.request(.proxies)

                let (version, config, groupsResponse) = try await (versionTask, configTask, groupsTask)
                self.version = version.version
                self.applyRuntimeConfigSnapshot(config)
                self.applyProxyGroupsResponse(groupsResponse)
            } else {
                async let versionTask: VersionInfo = client.request(.version)
                async let configTask: ConfigSnapshot = client.request(.getConfigs)

                let (version, config) = try await (versionTask, configTask)
                self.version = version.version
                self.applyRuntimeConfigSnapshot(config)
            }
        }
    }

    func fetchRuntimeConfigSnapshot() async throws -> ConfigSnapshot {
        let client = try clientOrThrow()
        let config: ConfigSnapshot = try await client.request(.getConfigs)
        applyRuntimeConfigSnapshot(config)
        return config
    }

    func applyRuntimeConfigSnapshot(_ config: ConfigSnapshot) {
        let remoteMode = normalizeMode(config.mode)
        if let remoteMode {
            currentMode = remoteMode
        }
        logLevel = config.logLevel ?? logLevel

        port = config.port
        socksPort = config.socksPort
        redirPort = config.redirPort
        tproxyPort = config.tproxyPort
        mixedPort = config.mixedPort ?? 0

        if let externalController = config.externalController {
            applyExternalControllerFromConfig(externalController)
        }
        syncEditableSettings(from: config)
    }

    func resetTrafficPresentation() {
        traffic = TrafficSnapshot(up: 0, down: 0)
        clearTrafficPresentationHistory()
    }

    func clearTrafficPresentationHistory() {
        displayUpTotal = 0
        displayDownTotal = 0
        trafficHistoryUp = []
        trafficHistoryDown = []
        lastTrafficSampleAt = nil
    }

    func releasePanelCachedData() {
        connectionsCount = 0
        connections.removeAll(keepingCapacity: false)

        memory = MemorySnapshot(inuse: 0)

        proxyGroups.removeAll(keepingCapacity: false)
        groupLatencyLoading.removeAll(keepingCapacity: false)
        groupLatencies.removeAll(keepingCapacity: false)
        proxyHistoryLatestDelay.removeAll(keepingCapacity: false)

        providerProxyCount = 0
        providerRuleCount = 0
        rulesCount = 0
        proxyProvidersDetail.removeAll(keepingCapacity: false)
        expandedProxyProviders.removeAll(keepingCapacity: false)
        providerNodeLatencies.removeAll(keepingCapacity: false)
        providerNodeTesting.removeAll(keepingCapacity: false)
        providerBatchTesting.removeAll(keepingCapacity: false)
        providerUpdating.removeAll(keepingCapacity: false)
        ruleProviders.removeAll(keepingCapacity: false)
        ruleItems.removeAll(keepingCapacity: false)
    }

    func appendTrafficHistory(up: Int64, down: Int64) {
        trafficHistoryUp.append(max(0, up))
        trafficHistoryDown.append(max(0, down))

        if trafficHistoryUp.count > historyMaxPoints {
            trafficHistoryUp.removeFirst(trafficHistoryUp.count - historyMaxPoints)
        }
        if trafficHistoryDown.count > historyMaxPoints {
            trafficHistoryDown.removeFirst(trafficHistoryDown.count - historyMaxPoints)
        }
    }

    func updateTrafficTotals(from snapshot: TrafficSnapshot) {
        if let upTotal = snapshot.upTotal, let downTotal = snapshot.downTotal {
            displayUpTotal = max(0, upTotal)
            displayDownTotal = max(0, downTotal)
            lastTrafficSampleAt = Date()
            return
        }

        let now = Date()
        if let last = lastTrafficSampleAt {
            let delta = max(0, now.timeIntervalSince(last))
            displayUpTotal += Int64(Double(max(0, snapshot.up)) * delta)
            displayDownTotal += Int64(Double(max(0, snapshot.down)) * delta)
        }
        lastTrafficSampleAt = now
    }

    func refreshLowFrequency() async {
        guard isPanelPresented else { return }
        switch activeMenuTab {
        case .proxy:
            await refreshProvidersAndRules()
            await refreshSystemProxyStatus()
        case .rules:
            await refreshProvidersAndRules()
        case .system:
            await refreshSystemProxyStatus()
        case .activity, .logs:
            break
        }
    }

    func refreshProxyGroups() async {
        await runRefresh {
            let client = try self.clientOrThrow()
            let groupsResponse: ProxyGroupsResponse = try await client.request(.proxies)
            self.applyProxyGroupsResponse(groupsResponse)
        }
    }

    func applyProxyGroupsResponse(_ response: ProxyGroupsResponse) {
        proxyGroups = response.proxies.values
            .filter { !$0.all.isEmpty && ($0.type == "Selector" || $0.type == "URLTest" || $0.type == "Fallback" || $0.type == nil) }
            .sorted { lhs, rhs in
                let lhsPriority = proxyGroupTypePriority(lhs.type)
                let rhsPriority = proxyGroupTypePriority(rhs.type)
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.name < rhs.name
            }
            .map { group in
                ProxyGroup(
                    name: group.name,
                    type: group.type,
                    now: group.now,
                    all: group.all,
                    hidden: group.hidden,
                    latestDelay: nil
                )
            }

        var historyMap: [String: Int] = [:]
        for proxy in response.proxies.values where proxy.hidden != true {
            if let latest = proxy.latestDelay {
                historyMap[proxy.name] = latest
            }
        }
        proxyHistoryLatestDelay = historyMap
    }

    func proxyGroupTypePriority(_ type: String?) -> Int {
        switch type {
        case "Selector":
            return 0
        case "URLTest":
            return 1
        default:
            return 2
        }
    }

    func refreshConnections() async {
        let policy = desiredDataAcquisitionPolicy(panelPresented: isPanelPresented, activeTab: activeMenuTab)
        guard policy.enableConnectionsStream else {
            cancelStream(.connections)
            return
        }
        startConnectionsStream(intervalMilliseconds: policy.connectionsIntervalMilliseconds)
    }

    func refreshSystemProxyStatus() async {
        do {
            isSystemProxyEnabled = try await readSystemProxyEnabledState()
        } catch {
            appendLog(level: "error", message: tr("log.system_proxy.read_failed", systemProxyErrorMessage(error)))
        }
    }

    private func applyStreamPolicy(_ policy: DataAcquisitionPolicy) {
        syncStream(.traffic, enabled: policy.enableTrafficStream) { startTrafficStream() }
        syncStream(.memory, enabled: policy.enableMemoryStream) { startMemoryStream() }
        syncConnectionsStream(
            enabled: policy.enableConnectionsStream,
            intervalMilliseconds: policy.connectionsIntervalMilliseconds
        )
        syncStream(.logs, enabled: policy.enableLogsStream) { startLogsStream() }
    }

    private func syncConnectionsStream(enabled: Bool, intervalMilliseconds: Int?) {
        syncStream(
            .connections,
            enabled: enabled,
            forceRestart: currentConnectionsStreamIntervalMilliseconds != intervalMilliseconds
        ) {
            startConnectionsStream(intervalMilliseconds: intervalMilliseconds)
        }
    }

    private func syncStream(
        _ kind: StreamKind,
        enabled: Bool,
        forceRestart: Bool = false,
        start: () -> Void
    ) {
        guard enabled else {
            cancelStream(kind)
            return
        }
        guard forceRestart || webSocketTask(for: kind) == nil else { return }
        start()
    }
}
