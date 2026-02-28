import SwiftUI

extension MenuBarRoot {
    var nativeAccent: Color { Color(nsColor: .controlAccentColor) }
    var nativeInfo: Color { Color(nsColor: .systemBlue) }
    var nativePositive: Color { Color(nsColor: .systemGreen) }
    var nativeWarning: Color { Color(nsColor: .systemOrange) }
    var nativeCritical: Color { Color(nsColor: .systemRed) }
    var nativeTeal: Color { Color(nsColor: .systemTeal) }
    var nativeIndigo: Color { Color(nsColor: .systemIndigo) }
    var nativePurple: Color { Color(nsColor: .systemPurple) }
    var nativePrimaryLabel: Color { Color(nsColor: .labelColor) }
    var nativeSecondaryLabel: Color { Color(nsColor: .secondaryLabelColor) }
    var nativeTertiaryLabel: Color { Color(nsColor: .tertiaryLabelColor) }
    var nativeSeparator: Color { Color(nsColor: .separatorColor).opacity(0.55) }
    var nativeControlFill: Color { Color(nsColor: .controlBackgroundColor).opacity(0.62) }
    var nativeControlBorder: Color { Color(nsColor: .separatorColor).opacity(0.45) }
    var nativeCardFill: Color { Color(nsColor: .controlBackgroundColor).opacity(0.56) }
    var nativeCardBorder: Color { Color(nsColor: .separatorColor).opacity(0.40) }
    var nativeHoverFill: Color { Color(nsColor: .selectedContentBackgroundColor).opacity(0.20) }
    var nativeBadgeFill: Color { Color(nsColor: .quaternaryLabelColor).opacity(0.16) }

    func nativeSectionCard(cornerRadius: CGFloat = 10) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(nativeCardFill)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(nativeCardBorder, lineWidth: 0.6)
            }
    }

    func nativeHoverRowBackground(_ hovered: Bool, cornerRadius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(hovered ? nativeHoverFill : .clear)
    }

    func nativeBadgeCapsule() -> some View {
        Capsule(style: .continuous)
            .fill(nativeBadgeFill)
    }

    func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(nativeSecondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .menuRowPadding()
            .background(nativeSectionCard(cornerRadius: 8))
    }

    var footerBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(nativeSeparator)
                .frame(height: MenuBarLayoutTokens.hairline)
                .padding(.bottom, MenuBarLayoutTokens.vDense)

            HStack(spacing: MenuBarLayoutTokens.hDense) {
                if let mihomoRepositoryURL {
                    footerInfoLink(
                        tr("ui.footer.core_mihomo", appState.version),
                        url: mihomoRepositoryURL,
                        iconSystemName: footerMihomoSymbol,
                        alignment: .leading
                    )
                } else {
                    footerInfoText(
                        tr("ui.footer.core_mihomo", appState.version),
                        iconSystemName: footerMihomoSymbol,
                        alignment: .leading
                    )
                }

                Spacer(minLength: 0)

                if let clashBarRepositoryURL {
                    footerInfoLink(
                        tr("ui.footer.version", appVersionText),
                        url: clashBarRepositoryURL,
                        iconSystemName: footerGitHubSymbol,
                        alignment: .trailing
                    )
                } else {
                    footerInfoText(
                        tr("ui.footer.version", appVersionText),
                        iconSystemName: footerGitHubSymbol,
                        alignment: .trailing
                    )
                }
            }
            .padding(.horizontal, MenuBarLayoutTokens.hRow)
            .padding(.vertical, MenuBarLayoutTokens.vDense + 2)
            .background(footerSurfaceBackground)
        }
    }

    var footerSurfaceBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(nativeControlFill.opacity(0.86))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(nativeControlBorder.opacity(0.9), lineWidth: 0.6)
            }
            .shadow(color: Color(nsColor: .shadowColor).opacity(0.16), radius: 10, x: 0, y: -3)
    }

    func footerInfoText(_ text: String, iconSystemName: String? = nil, alignment: Alignment) -> some View {
        footerInfoLabel(text, iconSystemName: iconSystemName, alignment: alignment)
    }

    func footerInfoLink(_ text: String, url: URL, iconSystemName: String? = nil, alignment: Alignment) -> some View {
        Link(destination: url) {
            footerInfoLabel(text, iconSystemName: iconSystemName, alignment: alignment)
        }
        .buttonStyle(.plain)
    }

    func footerInfoLabel(_ text: String, iconSystemName: String?, alignment: Alignment) -> some View {
        HStack(spacing: 4) {
            if let iconSystemName {
                Image(systemName: iconSystemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(nativeSecondaryLabel)
            }

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(nativeSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    var footerMihomoSymbol: String { "antenna.radiowaves.left.and.right" }
    var footerGitHubSymbol: String { "chevron.left.forwardslash.chevron.right" }

    var mihomoRepositoryURL: URL? {
        URL(string: "https://github.com/MetaCubeX/mihomo")
    }

    var clashBarRepositoryURL: URL? {
        URL(string: "https://github.com/Sitoi/ClashBar")
    }

    var statusColor: Color {
        switch appState.runtimeVisualStatus {
        case .runningHealthy: return nativePositive.opacity(0.95)
        case .runningDegraded: return nativeWarning.opacity(0.95)
        case .starting: return nativeInfo.opacity(0.95)
        case .failed: return nativeCritical.opacity(0.95)
        case .stopped: return nativeSecondaryLabel
        }
    }

    var runtimeBadgeText: String {
        switch appState.runtimeVisualStatus {
        case .runningHealthy, .runningDegraded:
            return tr("ui.header.status.running")
        case .starting:
            return tr("ui.header.status.starting")
        case .failed:
            return tr("ui.header.status.failed")
        case .stopped:
            return tr("ui.header.status.stopped")
        }
    }

    var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let short, !short.isEmpty { return short }
        if let build, !build.isEmpty { return build }
        return "0.0.1"
    }

    func sortedProviderNodes(provider: String, detail: ProviderDetail?) -> [String] {
        guard let proxies = detail?.proxies else { return [] }

        let names = Array(Set(proxies.map(\.name)))
        return names.sorted { lhs, rhs in
            let left = providerNodeSortWeight(provider: provider, node: lhs)
            let right = providerNodeSortWeight(provider: provider, node: rhs)
            if left != right { return left < right }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    func providerNodeSortWeight(provider: String, node: String) -> Int {
        guard let value = appState.providerNodeLatencies[provider]?[node] else { return Int.max }
        if value == 0 { return Int.max - 1 }
        return value
    }

    func providerNodeDelayColor(provider: String, node: String) -> Color {
        guard let value = appState.providerNodeLatencies[provider]?[node] else {
            return nativeTertiaryLabel
        }
        if value == 0 { return nativeCritical.opacity(0.9) }
        if value <= 400 { return nativePositive.opacity(0.9) }
        return nativeWarning.opacity(0.9)
    }

    func sortedGroupNodes(_ group: ProxyGroup) -> [String] {
        group.all.sorted { lhs, rhs in
            let left = sortWeight(group: group.name, node: lhs)
            let right = sortWeight(group: group.name, node: rhs)
            if left != right { return left < right }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    func sortWeight(group: String, node: String) -> Int {
        guard let value = appState.delayValue(group: group, node: node) else { return Int.max }
        if value == 0 { return Int.max - 1 }
        return value
    }

    func groupColor(for group: ProxyGroup) -> Color {
        let info = normalizedProxyGroupInfo(group)
        let lower = info.lowerName
        let compactType = info.compactType

        if compactType == "global" || lower.contains("global") { return nativeIndigo }
        if lower.contains("manual") { return nativeWarning }
        if lower.contains("media") { return nativePurple }
        if lower.contains("apple") { return nativeSecondaryLabel }

        switch compactType {
        case "selector", "select":
            return nativeAccent
        case "fallback":
            return nativeWarning
        case "urltest":
            return nativeTeal
        case "loadbalance":
            return nativePurple
        default:
            return nativeInfo
        }
    }

    func groupSymbol(for group: ProxyGroup) -> String {
        let info = normalizedProxyGroupInfo(group)
        let lower = info.lowerName
        let compactType = info.compactType

        if compactType == "global" || lower.contains("global") { return "globe.americas.fill" }

        switch compactType {
        case "selector", "select":
            return "list.bullet.circle"
        case "urltest":
            return "gauge"
        case "fallback":
            return "arrow.triangle.branch"
        case "loadbalance":
            return "shuffle"
        default:
            break
        }

        if lower.contains("apple") { return "apple.logo" }
        if lower.contains("media") { return "film.fill" }
        if lower.contains("manual") { return "hand.raised.fill" }
        return "point.3.filled.connected.trianglepath.dotted"
    }

    func normalizedProxyGroupInfo(_ group: ProxyGroup) -> (lowerName: String, compactType: String) {
        let lowerName = group.name.lowercased()
        let compactType = group.type?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "-", with: "") ?? ""
        return (lowerName, compactType)
    }

    func groupSelectionColor(for group: ProxyGroup) -> Color {
        nativeSecondaryLabel
    }

    func groupDelayColor(group: String, node: String) -> Color {
        guard let value = appState.delayValue(group: group, node: node) else {
            return nativeTertiaryLabel
        }
        if value == 0 { return nativeCritical.opacity(0.9) }
        if value <= 400 { return nativePositive.opacity(0.9) }
        return nativeWarning.opacity(0.9)
    }

    @ViewBuilder
    func asyncBorderedIconButton(
        symbol: String,
        label: String? = nil,
        fontSize: CGFloat = 11,
        frameSize: CGFloat = 12,
        controlSize: ControlSize = .small,
        tint: Color = .accentColor,
        isLoading: Bool = false,
        action: @escaping () async -> Void
    ) -> some View {
        if let label {
            baseAsyncBorderedIconButton(
                symbol: symbol,
                fontSize: fontSize,
                frameSize: frameSize,
                controlSize: controlSize,
                tint: tint,
                isLoading: isLoading,
                action: action
            )
            .accessibilityLabel(label)
        } else {
            baseAsyncBorderedIconButton(
                symbol: symbol,
                fontSize: fontSize,
                frameSize: frameSize,
                controlSize: controlSize,
                tint: tint,
                isLoading: isLoading,
                action: action
            )
        }
    }

    func roundedIconActionButton(
        symbol: String,
        size: CGFloat,
        foreground: Color,
        isLoading: Bool = false,
        action: @escaping () async -> Void
    ) -> some View {
        asyncBorderedIconButton(
            symbol: symbol,
            fontSize: 11,
            frameSize: max(12, size),
            controlSize: .mini,
            tint: foreground,
            isLoading: isLoading,
            action: action
        )
    }

    private func baseAsyncBorderedIconButton(
        symbol: String,
        fontSize: CGFloat,
        frameSize: CGFloat,
        controlSize: ControlSize,
        tint: Color,
        isLoading: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                Image(systemName: symbol)
                    .font(.system(size: fontSize, weight: .semibold))
                    .opacity(isLoading ? 0 : 1)

                ProgressView()
                    .controlSize(controlSize)
                    .opacity(isLoading ? 1 : 0)
            }
            .frame(width: max(12, frameSize), height: max(12, frameSize))
        }
        .buttonStyle(.bordered)
        .controlSize(controlSize)
        .tint(tint)
        .disabled(isLoading)
    }

}
