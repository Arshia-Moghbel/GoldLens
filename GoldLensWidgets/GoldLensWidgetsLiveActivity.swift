import ActivityKit
import SwiftUI
import WidgetKit

struct MarketLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var price: String
        var change: String
        var updatedAt: Date
    }

    var assetName: String
    var symbol: String
}

struct GoldLensWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MarketLiveActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GoldLens • (context.attributes.assetName)")
                        .font(.caption.weight(.semibold))
                    Text(context.state.price + " تومان")
                        .font(.headline.monospacedDigit())
                }
                Spacer()
                Text(context.state.change)
                    .font(.subheadline.bold())
                    .foregroundStyle(context.state.change.contains("−") ? .red : .green)
            }
            .padding(.horizontal)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "circle.hexagongrid.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.change)
                        .font(.caption.bold())
                        .foregroundStyle(context.state.change.contains("−") ? .red : .green)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("طلای ۱۸ عیار")
                        Spacer()
                        Text(context.state.price + " تومان")
                            .font(.headline.monospacedDigit())
                    }
                }
            } compactLeading: {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.state.price)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "goldlens://market/gold"))
            .keylineTint(.orange)
        }
    }
}
