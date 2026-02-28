import SwiftUI

struct TrafficSparklineView: View {
    let upValues: [Int64]
    let downValues: [Int64]

    var body: some View {
        GeometryReader { geo in
            let fallbackDown = [20, 13, 18, 10, 12, 6, 12, 5, 9, 7, 4, 14, 10, 15, 8, 11, 7, 9, 5, 12].map(Int64.init)
            let fallbackUp = [10, 7, 12, 8, 9, 4, 9, 3, 7, 5, 2, 10, 8, 11, 6, 8, 5, 7, 4, 9].map(Int64.init)
            let downPoints = downValues.isEmpty ? fallbackDown : downValues
            let upPoints = upValues.isEmpty ? fallbackUp : upValues
            let sharedCount = max(downPoints.count, upPoints.count)
            let normalizedDown = normalizePoints(downPoints, count: sharedCount)
            let normalizedUp = normalizePoints(upPoints, count: sharedCount)
            let maxY = max(1.0, Double(max(normalizedDown.max() ?? 0, normalizedUp.max() ?? 0)))
            let axisY = floor(geo.size.height * 0.5)
            let upperSpan = max(1, axisY - 2)
            let lowerSpan = max(1, geo.size.height - axisY - 2)

            ZStack {
                axisPath(width: geo.size.width, axisY: axisY)
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(0.55),
                        style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
                    )

                lineAreaPath(
                    for: normalizedUp,
                    width: geo.size.width,
                    axisY: axisY,
                    span: upperSpan,
                    maxY: maxY,
                    direction: .up
                )
                    .fill(
                        LinearGradient(
                            colors: [Color(nsColor: .controlAccentColor).opacity(0.22), Color(nsColor: .controlAccentColor).opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                lineAreaPath(
                    for: normalizedDown,
                    width: geo.size.width,
                    axisY: axisY,
                    span: lowerSpan,
                    maxY: maxY,
                    direction: .down
                )
                    .fill(
                        LinearGradient(
                            colors: [Color(nsColor: .systemGreen).opacity(0.24), Color(nsColor: .systemGreen).opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                linePath(
                    for: normalizedUp,
                    width: geo.size.width,
                    axisY: axisY,
                    span: upperSpan,
                    maxY: maxY,
                    direction: .up
                )
                    .stroke(
                        Color(nsColor: .controlAccentColor).opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )

                linePath(
                    for: normalizedDown,
                    width: geo.size.width,
                    axisY: axisY,
                    span: lowerSpan,
                    maxY: maxY,
                    direction: .down
                )
                    .stroke(
                        Color(nsColor: .systemGreen).opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                    )
            }
        }
    }

    private func normalizePoints(_ values: [Int64], count: Int) -> [Int64] {
        guard count > 0 else { return [] }
        guard !values.isEmpty else { return Array(repeating: 0, count: count) }
        if values.count == count { return values }
        if values.count > count { return Array(values.suffix(count)) }
        return Array(repeating: values.first ?? 0, count: count - values.count) + values
    }

    private func linePath(
        for values: [Int64],
        width: CGFloat,
        axisY: CGFloat,
        span: CGFloat,
        maxY: Double,
        direction: LineDirection
    ) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }

        let count = values.count
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) / CGFloat(max(count - 1, 1)) * width
            let y = yPosition(value, axisY: axisY, span: span, maxY: maxY, direction: direction)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private func lineAreaPath(
        for values: [Int64],
        width: CGFloat,
        axisY: CGFloat,
        span: CGFloat,
        maxY: Double,
        direction: LineDirection
    ) -> Path {
        var path = linePath(
            for: values,
            width: width,
            axisY: axisY,
            span: span,
            maxY: maxY,
            direction: direction
        )
        guard !values.isEmpty else { return path }

        path.addLine(to: CGPoint(x: width, y: axisY))
        path.addLine(to: CGPoint(x: 0, y: axisY))
        path.closeSubpath()
        return path
    }

    private func axisPath(width: CGFloat, axisY: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: axisY))
        path.addLine(to: CGPoint(x: width, y: axisY))
        return path
    }

    private func yPosition(_ value: Int64, axisY: CGFloat, span: CGFloat, maxY: Double, direction: LineDirection) -> CGFloat {
        let clamped = max(0.0, min(Double(value), maxY))
        let ratio = CGFloat(clamped / maxY)

        switch direction {
        case .up:
            return axisY - ratio * span
        case .down:
            return axisY + ratio * span
        }
    }

    private enum LineDirection {
        case up
        case down
    }
}
