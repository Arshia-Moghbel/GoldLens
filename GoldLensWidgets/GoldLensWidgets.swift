import AppIntents
import Foundation
import SwiftUI
import WidgetKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { .placeholder }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        await makeEntry(configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let entry = await makeEntry(configuration: configuration)
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func makeEntry(configuration: ConfigurationAppIntent) async -> SimpleEntry {
        SimpleEntry(date: .now, configuration: configuration, quotes: await WidgetMarketClient.fetchQuotes())
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let quotes: [WidgetQuote]

    static let placeholder = SimpleEntry(
        date: .now,
        configuration: ConfigurationAppIntent(),
        quotes: [
            WidgetQuote(title: "طلای ۱۸ عیار", icon: "circle.hexagongrid.fill", value: "در حال دریافت"),
            WidgetQuote(title: "دلار آزاد", icon: "dollarsign.circle.fill", value: "در حال دریافت")
        ]
    )
}

struct GoldLensWidgetsEntryView: View {
    let entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("GoldLens", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if entry.quotes.isEmpty {
                ContentUnavailableView("نرخ در دسترس نیست", systemImage: "wifi.exclamationmark")
                    .font(.caption)
            } else {
                ForEach(entry.quotes) { quote in
                    HStack(spacing: 8) {
                        Image(systemName: quote.icon)
                            .foregroundStyle(quote.icon == "circle.hexagongrid.fill" ? .orange : .blue)
                        Text(quote.title).font(.caption)
                        Spacer(minLength: 4)
                        Text(quote.value)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "goldlens://market"))
    }
}

struct GoldLensWidgets: Widget {
    let kind = "GoldLensWidgets"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            GoldLensWidgetsEntryView(entry: entry)
        }
        .configurationDisplayName("نبض بازار")
        .description("آخرین نرخ طلای ۱۸ عیار و دلار آزاد")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetQuote: Identifiable {
    let title: String
    let icon: String
    let value: String
    var id: String { title }
}

enum WidgetMarketClient {
    static func fetchQuotes() async -> [WidgetQuote] {
        guard let url = URL(string: "https://call.tgju.org/ajax.json") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("GoldLens/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            let current = root["current"] as? [String: Any] ?? root
            let gold = price(from: current["price_geram18"])
                ?? price(from: current["price_geram18k"])
                ?? price(from: current["price_gold_18k"])
            let dollar = price(from: current["price_dollar_rl"])

            return [
                gold.map { WidgetQuote(title: "طلای ۱۸ عیار", icon: "circle.hexagongrid.fill", value: toman($0)) },
                dollar.map { WidgetQuote(title: "دلار آزاد", icon: "dollarsign.circle.fill", value: toman($0)) }
            ].compactMap { $0 }
        } catch {
            return []
        }
    }

    private static func price(from input: Any?) -> Double? {
        if let number = input as? NSNumber { return number.doubleValue / 10 }
        guard let string = input as? String else { return nil }
        let latin = string
            .replacingOccurrences(of: "٬", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "٫", with: ".")
            .applyingTransform(.toLatin, reverse: false) ?? string
        guard let value = Double(latin) else { return nil }
        return value / 10
    }

    private static func toman(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fa_IR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return (formatter.string(from: value as NSNumber) ?? "—") + " تومان"
    }
}
