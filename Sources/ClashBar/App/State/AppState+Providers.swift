import Foundation

@MainActor
extension AppState {
    var sortedProxyProviderNames: [String] {
        proxyProvidersDetail.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func updateRuleProvider(name: String) async {
        await runSingleProviderUpdate(
            actionName: tr("log.action_name.update_rule_provider", name),
            request: .updateRuleProvider(name: name)
        )
    }

    func refreshRuleProviders() async {
        guard !isRuleProvidersRefreshing else { return }
        isRuleProvidersRefreshing = true
        defer { isRuleProvidersRefreshing = false }

        do {
            let client = try clientOrThrow()
            let summary: ProviderSummary = try await client.request(.ruleProviders)
            let names = summary.providers.keys.sorted()

            for name in names {
                do {
                    try await client.requestNoResponse(.updateRuleProvider(name: name))
                } catch {
                    appendLog(level: "error", message: tr("log.providers.rule_update_failed", name, error.localizedDescription))
                }
            }
        } catch {
            appendLog(level: "error", message: tr("log.providers.fetch_rule_failed", error.localizedDescription))
        }

        await refreshProvidersAndRules()
    }

    func updateProxyProvider(name: String) async {
        guard !providerUpdating.contains(name) else { return }
        providerUpdating.insert(name)
        defer { providerUpdating.remove(name) }

        await runSingleProviderUpdate(
            actionName: tr("log.action_name.update_proxy_provider", name),
            request: .updateProxyProvider(name: name)
        )
    }

    func testProxyProviderNode(provider: String, node: String) async {
        let key = providerNodeKey(provider: provider, node: node)
        providerNodeTesting.insert(key)
        defer { providerNodeTesting.remove(key) }

        do {
            let client = try clientOrThrow()
            let response: DelayMeasurement = try await client.request(
                .proxyProviderProxyHealthcheck(
                    provider: provider,
                    proxy: node,
                    url: defaultHealthcheckURL,
                    timeout: defaultHealthcheckTimeoutMilliseconds
                )
            )
            if let value = response.value {
                setProviderNodeLatency(provider: provider, node: node, value: value)
            }
        } catch {
            appendLog(level: "error", message: tr("log.provider.node_test_failed", provider, node, error.localizedDescription))
        }
    }

    func testAllProxyProviderNodes(provider: String) async {
        providerBatchTesting.insert(provider)
        defer { providerBatchTesting.remove(provider) }

        if proxyProvidersDetail[provider]?.proxies == nil {
            await ensureProviderNodesLoaded(provider: provider)
        }

        guard let nodes = proxyProvidersDetail[provider]?.proxies, !nodes.isEmpty else {
            return
        }

        let nodeKeys = nodes.map { providerNodeKey(provider: provider, node: $0.name) }
        nodeKeys.forEach { providerNodeTesting.insert($0) }
        defer { nodeKeys.forEach { providerNodeTesting.remove($0) } }

        do {
            let client = try clientOrThrow()
            try await client.requestNoResponse(
                .proxyProviderHealthcheck(
                    name: provider,
                    url: defaultHealthcheckURL,
                    timeout: defaultHealthcheckTimeoutMilliseconds
                )
            )
            let refreshed: ProviderDetail = try await client.request(.proxyProvider(name: provider))
            applyRefreshedProviderDetail(provider: provider, detail: refreshed)
        } catch {
            appendLog(level: "error", message: tr("log.provider.healthcheck_failed", provider, error.localizedDescription))
        }
    }

    func providerNodeDelayText(provider: String, node: String) -> String {
        let key = providerNodeKey(provider: provider, node: node)
        guard !providerNodeTesting.contains(key) else { return tr("ui.common.testing") }
        guard let value = providerNodeLatencies[provider]?[node] else { return tr("ui.common.unknown") }
        return tr("ui.common.latency_ms", value)
    }

    func applyProviderHealthcheckDelays(provider: String, detail: ProviderDetail) {
        detail.proxies?
            .compactMap { proxy in
                latestProviderDelay(proxy.history).map { (name: proxy.name, delay: $0) }
            }
            .forEach { setProviderNodeLatency(provider: provider, node: $0.name, value: $0.delay) }
    }

    private func sanitizedProviderDetail(_ detail: ProviderDetail, includeNodes: Bool) -> ProviderDetail {
        let proxies = includeNodes ? detail.proxies?.map { ProviderProxyNode(name: $0.name, history: nil) } : nil
        // DRY: one detail sanitizer controls whether nodes are kept.
        return ProviderDetail(
            name: detail.name,
            vehicleType: detail.vehicleType,
            updatedAt: detail.updatedAt,
            ruleCount: detail.ruleCount,
            subscriptionInfo: detail.subscriptionInfo,
            proxies: proxies
        )
    }

    func ensureProviderNodesLoaded(provider: String) async {
        guard let current = proxyProvidersDetail[provider], current.proxies?.isEmpty != false else { return }

        do {
            let client = try clientOrThrow()
            let refreshed: ProviderDetail = try await client.request(.proxyProvider(name: provider))
            applyRefreshedProviderDetail(provider: provider, detail: refreshed)
        } catch {
            appendLog(level: "error", message: tr("log.providers.fetch_proxy_failed", error.localizedDescription))
        }
    }

    func pruneProviderNodeLatencies(provider: String, allowedNodes: Set<String>) {
        guard var existing = providerNodeLatencies[provider] else { return }
        existing = existing.filter { allowedNodes.contains($0.key) }
        providerNodeLatencies[provider] = existing
    }

    private func latestProviderDelay(_ history: [ProviderProxyDelayHistoryEntry]?) -> Int? {
        history?.lazy.reversed().compactMap(\.delay).first
    }

    func applyRefreshedProviderDetail(provider: String, detail: ProviderDetail) {
        proxyProvidersDetail[provider] = sanitizedProviderDetail(detail, includeNodes: true)
        applyProviderHealthcheckDelays(provider: provider, detail: detail)
        pruneProviderNodeLatencies(provider: provider, allowedNodes: Set(detail.proxies?.map(\.name) ?? []))
    }

    func enqueueProviderRefresh(trigger: ProviderRefreshTrigger) {
        cancelProviderRefresh(reason: "superseded")
        providerRefreshGeneration += 1
        let generation = providerRefreshGeneration
        providerRefreshTask = Task { [weak self] in
            await self?.runProviderRefreshInBackground(trigger: trigger, generation: generation)
        }
    }

    func cancelProviderRefresh(reason: String) {
        guard providerRefreshTask != nil else { return }
        providerRefreshTask?.cancel()
        providerRefreshTask = nil
        let localizedReason = providerRefreshCancelReason(reason)
        updateProviderRefreshStatus(
            phase: .cancelled,
            trigger: providerRefreshStatus.trigger,
            progressDone: providerRefreshStatus.progressDone,
            progressTotal: providerRefreshStatus.progressTotal,
            message: tr("app.provider_refresh.cancelled_reason", localizedReason),
            generation: providerRefreshGeneration
        )
    }

    func runProviderRefreshInBackground(trigger: ProviderRefreshTrigger, generation: Int) async {
        func checkpoint() -> Bool {
            if Task.isCancelled || generation != providerRefreshGeneration {
                updateProviderRefreshStatus(
                    phase: .cancelled,
                    trigger: trigger,
                    progressDone: providerRefreshStatus.progressDone,
                    progressTotal: providerRefreshStatus.progressTotal,
                    message: tr("app.provider_refresh.cancelled"),
                    generation: generation
                )
                return false
            }
            return true
        }

        guard checkpoint() else { return }

        do {
            let client = try clientOrThrow()
            func fetchProviderSummary(_ endpoint: Endpoint, onError: (Error) -> String) async -> ProviderSummary {
                do {
                    return try await client.request(endpoint)
                } catch {
                    appendLog(level: "error", message: onError(error))
                    return ProviderSummary(providers: [:])
                }
            }

            let proxyProviders = await fetchProviderSummary(.proxyProviders) {
                tr("log.providers.fetch_proxy_failed", $0.localizedDescription)
            }
            let ruleProviders = await fetchProviderSummary(.ruleProviders) {
                tr("log.providers.fetch_rule_failed", $0.localizedDescription)
            }

            let proxyNames = proxyProviders.providers.keys.sorted()
            let ruleNames = ruleProviders.providers.keys.sorted()
            let total = proxyNames.count + ruleNames.count
            var done = 0
            var failed = 0
            func publishUpdatingProgress() {
                updateProviderRefreshStatus(
                    phase: .updating,
                    trigger: trigger,
                    progressDone: done,
                    progressTotal: total,
                    message: tr("app.provider_refresh.updating", done, total),
                    generation: generation
                )
            }

            publishUpdatingProgress()

            do {
                try await client.requestNoResponse(.putConfigs(force: true))
                appendLog(level: "info", message: tr("log.providers.config_reload_success"))
            } catch {
                failed += 1
                appendLog(level: "error", message: tr("log.providers.config_reload_failed", error.localizedDescription))
            }

            guard checkpoint() else { return }

            func updateProviders(
                _ names: [String],
                request: (String) -> Endpoint,
                onError: (String, Error) -> String
            ) async -> Bool {
                for name in names {
                    guard checkpoint() else { return false }
                    do {
                        try await client.requestNoResponse(request(name))
                    } catch {
                        failed += 1
                        appendLog(level: "error", message: onError(name, error))
                    }
                    done += 1
                    publishUpdatingProgress()
                }
                return true
            }

            let proxyCompleted = await updateProviders(
                proxyNames,
                request: { .updateProxyProvider(name: $0) },
                onError: { name, error in
                    tr("log.providers.proxy_update_failed", name, error.localizedDescription)
                }
            )
            guard proxyCompleted else { return }

            let ruleCompleted = await updateProviders(
                ruleNames,
                request: { .updateRuleProvider(name: $0) },
                onError: { name, error in
                    tr("log.providers.rule_update_failed", name, error.localizedDescription)
                }
            )
            guard ruleCompleted else { return }

            let resultPhase: ProviderRefreshPhase = failed == 0 ? .succeeded : .failed
            let resultMessage = failed == 0
                ? tr("app.provider_refresh.updated")
                : tr("app.provider_refresh.partial_failed", failed)
            updateProviderRefreshStatus(
                phase: resultPhase,
                trigger: trigger,
                progressDone: done,
                progressTotal: total,
                message: resultMessage,
                generation: generation
            )
            providerRefreshTask = nil
        } catch {
            appendLog(level: "error", message: tr("log.providers.api_unavailable", error.localizedDescription))
            updateProviderRefreshStatus(
                phase: .failed,
                trigger: trigger,
                progressDone: 0,
                progressTotal: 0,
                message: tr("app.provider_refresh.failed"),
                generation: generation
            )
            providerRefreshTask = nil
        }
    }

    func updateProviderRefreshStatus(
        phase: ProviderRefreshPhase,
        trigger: ProviderRefreshTrigger?,
        progressDone: Int,
        progressTotal: Int,
        message: String?,
        generation: Int
    ) {
        guard generation == providerRefreshGeneration else { return }
        providerRefreshStatus = ProviderRefreshStatus(
            phase: phase,
            trigger: trigger,
            progressDone: progressDone,
            progressTotal: progressTotal,
            message: message,
            updatedAt: Date()
        )
    }

    func refreshProvidersAndRules() async {
        await runRefresh {
            let client = try self.clientOrThrow()
            async let proxyProvidersTask: ProviderSummary = client.request(.proxyProviders)
            async let ruleProvidersTask: ProviderSummary = client.request(.ruleProviders)
            async let rulesTask: RulesSummary = client.request(.rules)

            let (proxyProviders, ruleProviders, rules) = try await (proxyProvidersTask, ruleProvidersTask, rulesTask)

            let filteredProxyProviders = proxyProviders.providers.filter { _, detail in
                let vehicleType = detail.vehicleType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return vehicleType.caseInsensitiveCompare("Compatible") != .orderedSame
            }

            self.proxyProvidersDetail = filteredProxyProviders.mapValues { sanitizedProviderDetail($0, includeNodes: false) }
            self.ruleProviders = ruleProviders.providers
            self.ruleItems = rules.rules

            self.providerProxyCount = filteredProxyProviders.count
            self.providerRuleCount = ruleProviders.providers.count
            self.rulesCount = rules.rules.count

            let currentNames = Set(filteredProxyProviders.keys)
            self.expandedProxyProviders = self.expandedProxyProviders.intersection(currentNames)
            self.providerBatchTesting = self.providerBatchTesting.intersection(currentNames)
            self.providerUpdating = self.providerUpdating.intersection(currentNames)
            self.providerNodeLatencies = self.providerNodeLatencies.filter { currentNames.contains($0.key) }
            self.providerNodeTesting = Set(self.providerNodeTesting.filter { currentNames.contains($0.provider) })
        }
    }

    func providerNodeKey(provider: String, node: String) -> ProviderNodeKey {
        ProviderNodeKey(provider: provider, node: node)
    }

    private func setProviderNodeLatency(provider: String, node: String, value: Int) {
        // DRY: centralize map upsert logic for provider-node latency writes.
        var map = providerNodeLatencies[provider] ?? [:]
        map[node] = value
        providerNodeLatencies[provider] = map
    }

    func providerRefreshCancelReason(_ reason: String) -> String {
        switch reason {
        case "stop requested":
            return tr("app.provider_refresh.reason.stop_requested")
        case "restart requested":
            return tr("app.provider_refresh.reason.restart_requested")
        case "quit requested":
            return tr("app.provider_refresh.reason.quit_requested")
        case "config switch requested":
            return tr("app.provider_refresh.reason.config_switch_requested")
        case "superseded":
            return tr("app.provider_refresh.reason.superseded")
        default:
            return reason
        }
    }

    func runSingleProviderUpdate(actionName: String, request: Endpoint) async {
        await runNoResponseAction(actionName) {
            try await self.clientOrThrow().requestNoResponse(request)
            await self.refreshProvidersAndRules()
        }
    }

}
