import Charts
import ActivityKit
import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct ContentView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("alertThreshold") private var alertThreshold = 1.5
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.persian.rawValue
    @StateObject private var marketStore = MarketStore()
    private let isRunningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    var body: some View {
        TabView {
            MarketDashboardView(
                notificationsEnabled: $notificationsEnabled,
                alertThreshold: $alertThreshold,
                isRunningInPreview: isRunningInPreview,
                marketStore: marketStore
            )
            .tabItem { Label(appText("بازار", "Market"), systemImage: "chart.xyaxis.line") }

            PortfolioView(marketStore: marketStore)
                .tabItem { Label(appText("دارایی من", "Portfolio"), systemImage: "wallet.pass.fill") }

            SettingsView(
                notificationsEnabled: $notificationsEnabled,
                alertThreshold: $alertThreshold
            )
                .tabItem { Label(appText("تنظیمات", "Settings"), systemImage: "gearshape.fill") }
        }
        .tint(.indigo)
        .environment(\.layoutDirection, language.layoutDirection)
        .environment(\.locale, language.locale)
    }

    private var language: AppLanguage { AppLanguage(rawValue: appLanguage) ?? .persian }
}

private struct MarketDashboardView: View {
    @Binding var notificationsEnabled: Bool
    @Binding var alertThreshold: Double
    let isRunningInPreview: Bool
    @State private var selectedAsset: MarketAsset = .gold
    @State private var selectedRange: ChartRange = .week
    @State private var showAlertSheet = false
    @ObservedObject var marketStore: MarketStore

    private var asset: MarketSnapshot { marketStore.snapshot(for: selectedAsset) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    marketStatus
                    if let connectionMessage = marketStore.connectionMessage {
                        connectionNotice(connectionMessage)
                    }
                    assetPicker
                    priceCard
                    chartSection
                    signalsSection
                    analysisCard
                    alertsCard
                    latestAlerts
                    disclaimer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: refresh) { Image(systemName: "arrow.clockwise").fontWeight(.semibold) }
                    .disabled(marketStore.isRefreshing)
                    .accessibilityLabel("به‌روزرسانی قیمت‌ها")
                }
            }
        }
        .sheet(isPresented: $showAlertSheet) {
            AlertSettingsView(
                assetName: asset.name,
                isEnabled: $notificationsEnabled,
                threshold: $alertThreshold
            )
            .presentationDetents([.medium])
        }
        .task {
            guard !isRunningInPreview else { return }
            await marketStore.refresh(
                notificationsEnabled: notificationsEnabled,
                threshold: alertThreshold
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("نبض بازار")
                .font(.largeTitle.bold())
            Text("طلا و دلار را هوشمندانه دنبال کن")
                .foregroundStyle(.secondary)
            Text("آخرین به‌روزرسانی: \(marketStore.lastUpdated.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var marketStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: marketStore.isRefreshing ? "arrow.triangle.2.circlepath" : marketStore.connectionMessage == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(marketStore.isRefreshing ? .blue : marketStore.connectionMessage == nil ? .green : .orange)
            Text(marketStore.isRefreshing ? "در حال به‌روزرسانی" : marketStore.connectionMessage == nil ? "نرخ زنده دریافت شد" : "اطلاعات بازار در دسترس نیست")
            Spacer()
            Text(marketStore.sourceTitle)
                .foregroundStyle(.secondary)
        }
        .font(.caption.bold())
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.green.opacity(0.10), in: Capsule())
    }

    private var assetPicker: some View {
        Picker("دارایی", selection: $selectedAsset) {
            ForEach(MarketAsset.allCases) { market in
                Label(market.title, systemImage: market.snapshot.icon).tag(market)
            }
        }
        .pickerStyle(.segmented)
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(asset.name, systemImage: asset.icon)
                    .font(.headline)
                Spacer()
                Label(asset.changeText, systemImage: asset.change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.17), in: Capsule())
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(asset.price).font(.system(size: 36, weight: .bold, design: .rounded))
                Text("تومان").font(.headline).opacity(0.8)
            }
            Divider().overlay(.white.opacity(0.35))
            HStack {
                PriceFact(title: "بالاترین امروز", value: asset.high)
                Spacer()
                PriceFact(title: "پایین‌ترین امروز", value: asset.low)
                Spacer()
                PriceFact(title: "حجم معاملات", value: asset.volume)
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(asset.tint.gradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("نمودار قیمت").font(.headline)
                Spacer()
                Picker("بازه", selection: $selectedRange) {
                    ForEach(ChartRange.allCases) { range in Text(range.title).tag(range) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            Chart(asset.history(for: selectedRange)) { point in
                AreaMark(x: .value("زمان", point.label), y: .value("قیمت", point.value))
                    .foregroundStyle(asset.tint.opacity(0.16).gradient)
                LineMark(x: .value("زمان", point.label), y: .value("قیمت", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(asset.tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                if point.id == asset.history(for: selectedRange).last?.id {
                    PointMark(x: .value("زمان", point.label), y: .value("قیمت", point.value))
                        .foregroundStyle(asset.tint)
                        .symbolSize(65)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 8))
            .frame(height: 210)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("شاخص‌های روند").font(.headline)
            HStack(spacing: 10) {
                SignalTile(title: "قدرت روند", value: asset.trendStrength, icon: "waveform.path.ecg", tint: asset.outlookColor)
                SignalTile(title: "ریسک نوسان", value: asset.volatility, icon: "bolt.fill", tint: .orange)
                SignalTile(title: "حمایت بعدی", value: asset.support, icon: "arrow.down.to.line", tint: .blue)
            }
        }
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("تحلیل هوشمند", systemImage: "sparkles").font(.headline)
                Spacer()
                Text(asset.outlook)
                    .font(.caption.bold())
                    .foregroundStyle(asset.outlookColor)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(asset.outlookColor.opacity(0.12), in: Capsule())
            }
            HStack(spacing: 16) {
                ConfidenceRing(value: asset.confidence, tint: asset.outlookColor)
                Text(asset.analysis)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("برآورد الگوریتمی است، نه توصیهٔ خرید یا فروش.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var alertsCard: some View {
        Button { showAlertSheet = true } label: {
            HStack(spacing: 14) {
                Image(systemName: notificationsEnabled ? "bell.badge.fill" : "bell.slash")
                    .font(.title3).foregroundStyle(.orange)
                    .frame(width: 42, height: 42).background(.orange.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("هشدار نوسان قیمت").font(.headline).foregroundStyle(.primary)
                    Text(notificationsEnabled ? "تغییر بیش از \(alertThreshold.formatted(.number.precision(.fractionLength(1))))٪ را اطلاع بده" : "هشدارها غیرفعال هستند")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var latestAlerts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("آخرین رویدادها").font(.headline); Spacer(); Text("مشاهده همه").font(.caption).foregroundStyle(.indigo) }
            ForEach(marketStore.events) { event in
                HStack(spacing: 11) {
                    Image(systemName: event.icon).foregroundStyle(event.tint).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.subheadline.weight(.medium))
                        Text(event.time).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var disclaimer: some View {
        Text("تحلیل‌ها قطعی نیستند و توصیهٔ خرید یا فروش به‌شمار نمی‌آیند. پیش از هر تصمیم مالی، داده را از منبع معتبر بررسی کنید.")
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }

    private func refresh() {
        Task {
            await marketStore.refresh(
                notificationsEnabled: notificationsEnabled,
                threshold: alertThreshold
            )
        }
    }

    private func connectionNotice(_ message: String) -> some View {
        Label(message, systemImage: "wifi.exclamationmark")
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PortfolioView: View {
    @ObservedObject var marketStore: MarketStore
    @AppStorage("portfolioGoldGrams") private var goldGrams = 12.5
    @AppStorage("portfolioDollars") private var dollars = 300.0
    @FocusState private var focusedField: PortfolioField?

    private var goldValue: Double { max(0, goldGrams) * marketStore.snapshot(for: .gold).numericPrice }
    private var dollarValue: Double { max(0, dollars) * marketStore.snapshot(for: .dollar).numericPrice }
    private var totalValue: Double { goldValue + dollarValue }

    var body: some View {
        NavigationStack {
            Form {
                Section(appText("ارزش دارایی", "Portfolio value")) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(appText("مجموع تقریبی", "Estimated total")).font(.subheadline).foregroundStyle(.secondary)
                        Text(totalValue.formatted(.number.grouping(.automatic)) + appText(" تومان", " toman"))
                            .font(.title.bold()).foregroundStyle(.indigo)
                    }
                    .padding(.vertical, 6)
                }
                Section(appText("موجودی شما", "Your holdings")) {
                    HStack { Label(appText("طلای ۱۸ عیار", "18K gold"), systemImage: "circle.hexagongrid.fill").foregroundStyle(.orange); Spacer(); TextField(appText("گرم", "Grams"), value: $goldGrams, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad).focused($focusedField, equals: .gold); Text(appText("گرم", "g")).foregroundStyle(.secondary) }
                    HStack { Label(appText("دلار", "US dollar"), systemImage: "dollarsign.circle.fill").foregroundStyle(.blue); Spacer(); TextField(appText("تعداد", "Amount"), value: $dollars, format: .number).multilineTextAlignment(.trailing).keyboardType(.decimalPad).focused($focusedField, equals: .dollar); Text(appText("دلار", "USD")).foregroundStyle(.secondary) }
                }
                Section("ترکیب دارایی") {
                    PortfolioRow(title: "طلا", value: goldValue, total: totalValue, tint: .orange)
                    PortfolioRow(title: "دلار", value: dollarValue, total: totalValue, tint: .blue)
                }
                Section("یادآوری") {
                    Text("ارزش‌ها با نرخ‌های نمونه محاسبه می‌شوند و کارمزد خرید و فروش را دربرنمی‌گیرند.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { dismissKeyboard() }
            .onChange(of: goldGrams) { _, value in if value < 0 { goldGrams = 0 } }
            .onChange(of: dollars) { _, value in if value < 0 { dollars = 0 } }
            .navigationTitle(appText("دارایی من", "Portfolio"))
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(appText("انجام شد", "Done")) { focusedField = nil }
                }
            }
        }
    }
}

private enum PortfolioField: Hashable { case gold, dollar }

private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct SettingsView: View {
    @Binding var notificationsEnabled: Bool
    @Binding var alertThreshold: Double
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.persian.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section(appText("زبان", "Language")) {
                    Picker(appText("زبان برنامه", "App language"), selection: $appLanguage) {
                        Text("فارسی").tag(AppLanguage.persian.rawValue)
                        Text("English").tag(AppLanguage.english.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                Section("اعلان‌ها") {
                    Toggle("هشدار نوسان", isOn: $notificationsEnabled)
                    Button("آزمایش اعلان") {
                        Task {
                            await NotificationManager.shared.requestAuthorization()
                            await NotificationManager.shared.sendTestNotification()
                        }
                    }
                    if notificationsEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("آستانه هشدار: \(alertThreshold.formatted(.number.precision(.fractionLength(1))))٪")
                            Slider(value: $alertThreshold, in: 0.5...5, step: 0.5)
                        }
                    }
                }
                Section("منبع قیمت") {
                    LabeledContent("مرجع نرخ", value: "بازار آزاد")
                    LabeledContent("بازه پیشنهادی", value: "هر ۵ دقیقه")
                    Text("داده‌ها از منبع عمومی بازار دریافت می‌شوند. در صورت قطع اینترنت، آخرین قیمت نمایش‌داده‌شده حفظ می‌شود.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("درباره تحلیل") {
                    Text("امتیاز روند از جهت تغییرات اخیر، نوسان و فاصله تا محدودهٔ حمایتی محاسبه می‌شود. هیچ مدلی نمی‌تواند آیندهٔ قیمت را قطعی پیش‌بینی کند.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("تنظیمات")
            .onChange(of: notificationsEnabled) { _, enabled in
                if enabled { Task { await NotificationManager.shared.requestAuthorization() } }
            }
        }
    }
}

private struct PriceFact: View {
    let title: String
    let value: String
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).opacity(0.72); Text(value).font(.caption.bold()) } }
}

private struct SignalTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).font(.caption.bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(13)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ConfidenceRing: View {
    let value: Double
    let tint: Color
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle().trim(from: 0, to: value / 100).stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(Int(value))٪").font(.caption.bold())
        }
        .frame(width: 58, height: 58)
    }
}

private struct PortfolioRow: View {
    let title: String
    let value: Double
    let total: Double
    let tint: Color
    var portion: Double { total == 0 ? 0 : value / total }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Text(title); Spacer(); Text("\(Int(portion * 100))٪").foregroundStyle(.secondary) }
            ProgressView(value: portion).tint(tint)
        }
    }
}

private struct AlertSettingsView: View {
    let assetName: String
    @Binding var isEnabled: Bool
    @Binding var threshold: Double
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("اعلان‌ها") { Toggle("هشدار \(assetName)", isOn: $isEnabled) }
                Section("حساسیت") {
                    Slider(value: $threshold, in: 0.5...5, step: 0.5)
                    Text("هنگام تغییر بیش از \(threshold.formatted(.number.precision(.fractionLength(1))))٪ اطلاع می‌دهیم.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("تنظیم هشدار")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("انجام شد") { dismiss() } } }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private enum MarketAsset: String, CaseIterable, Identifiable {
    case gold, dollar
    var id: String { rawValue }
    var title: String { self == .gold ? "طلا" : "دلار" }
    var snapshot: MarketSnapshot { self == .gold ? .gold : .dollar }
}

private enum ChartRange: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return "۱روز"
        case .week: return "۷روز"
        case .month: return "۱ماه"
        }
    }
}

private enum AppLanguage: String {
    case persian = "fa"
    case english = "en"

    var locale: Locale { Locale(identifier: rawValue == "fa" ? "fa_IR" : "en_US") }
    var layoutDirection: LayoutDirection { self == .persian ? .rightToLeft : .leftToRight }
}

private func appText(_ persian: String, _ english: String) -> String {
    (AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "fa") ?? .persian) == .english ? english : persian
}

private struct MarketSnapshot {
    let name: String
    let icon: String
    let tint: Color
    let price: String
    let numericPrice: Double
    let chartDivisor: Double
    let high: String
    let low: String
    let volume: String
    let change: Double
    let changeText: String
    let outlook: String
    let outlookColor: Color
    let confidence: Double
    let trendStrength: String
    let volatility: String
    let support: String
    let analysis: String
    let series: [Int]

    func updated(price: Double) -> MarketSnapshot {
        let chartPrice = Int((price / chartDivisor).rounded())
        let priceChange = ((price - numericPrice) / numericPrice) * 100
        let newSeries = Array((series + [chartPrice]).suffix(30))
        return MarketSnapshot(
            name: name, icon: icon, tint: tint, price: MarketNumberFormatter.toman(price), numericPrice: price,
            chartDivisor: chartDivisor, high: MarketNumberFormatter.toman(max(price, numericPrice)),
            low: MarketNumberFormatter.toman(min(price, numericPrice)), volume: volume, change: priceChange,
            changeText: MarketNumberFormatter.percent(priceChange), outlook: priceChange >= 0 ? "متمایل به رشد" : "محتاطانه نزولی",
            outlookColor: priceChange >= 0 ? .green : .red, confidence: min(85, max(52, confidence + abs(priceChange) * 5)),
            trendStrength: priceChange >= 0 ? "مثبت" : "ضعیف", volatility: abs(priceChange) > 1 ? "زیاد" : "متوسط",
            support: support, analysis: priceChange >= 0 ? "آخرین به‌روزرسانی حرکت صعودی را نشان می‌دهد؛ روند را در بازه‌های بعدی نیز دنبال کنید." : "آخرین به‌روزرسانی افت قیمت را نشان می‌دهد؛ نوسان کوتاه‌مدت همچنان محتمل است.",
            series: newSeries
        )
    }

    func history(for range: ChartRange) -> [PricePoint] {
        let count = range == .day ? 6 : range == .week ? 7 : series.count
        return Array(series.suffix(count)).enumerated().map { offset, value in PricePoint(label: range == .day ? "ساعت \(offset * 4 + 1)" : "\(offset + 1)", value: value) }
    }

    static let gold = MarketSnapshot(
        name: "هر گرم طلای ۱۸ عیار", icon: "circle.hexagongrid.fill", tint: .orange, price: "۱۷٬۸۴۸٬۵۰۰", numericPrice: 17_848_500, chartDivisor: 1_000,
        high: "۱۷٬۹۰۰٬۰۰۰", low: "۱۷٬۷۰۰٬۰۰۰", volume: "متوسط", change: 1.8, changeText: "۱٫۸٪+", outlook: "متمایل به رشد", outlookColor: .green, confidence: 68,
        trendStrength: "مثبت", volatility: "متوسط", support: "۱۷٫۷ م", analysis: "شتاب کوتاه‌مدت مثبت است و قیمت بالاتر از میانگین هفته قرار دارد. نوسان همچنان بالاست.",
        series: [17_240, 17_350, 17_420, 17_310, 17_500, 17_460, 17_610, 17_540, 17_650, 17_570, 17_720, 17_690, 17_849]
    )
    static let dollar = MarketSnapshot(
        name: "دلار آزاد", icon: "dollarsign.circle.fill", tint: .blue, price: "۱۸۴٬۳۸۵", numericPrice: 184_385, chartDivisor: 1,
        high: "۱۸۵٬۲۰۰", low: "۱۸۳٬۹۰۰", volume: "زیاد", change: -0.6, changeText: "۰٫۶٪−", outlook: "محتاطانه نزولی", outlookColor: .red, confidence: 57,
        trendStrength: "ضعیف", volatility: "زیاد", support: "۱۸۴٬۲۰۰", analysis: "فشار فروش در دو روز اخیر بیشتر شده است. شکست محدودهٔ حمایتی می‌تواند افت بیشتری ایجاد کند.",
        series: [183_400, 183_700, 184_100, 184_300, 184_000, 184_700, 184_500, 184_200, 184_800, 184_100, 184_000, 184_600, 184_385]
    )
}

private struct PricePoint: Identifiable { let label: String; let value: Int; var id: String { label } }

@MainActor
private final class MarketStore: ObservableObject {
    @Published private(set) var lastUpdated = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var sourceTitle = "منبع عمومی"
    @Published private(set) var connectionMessage: String?
    @Published private(set) var events = MarketEvent.sample

    @Published private var snapshots: [MarketAsset: MarketSnapshot] = [
        .gold: .gold,
        .dollar: .dollar
    ]
    private var lastAlertDate: [MarketAsset: Date] = [:]

    func snapshot(for asset: MarketAsset) -> MarketSnapshot {
        snapshots[asset] ?? asset.snapshot
    }

    func refresh(notificationsEnabled: Bool, threshold: Double) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await MarketDataClient.fetchQuotes()
        guard case let .success(remoteQuotes) = result else {
            sourceTitle = "منبع قیمت در دسترس نیست"
            if case let .failure(error) = result {
                connectionMessage = "\(error.localizedDescription) آخرین نرخ موجود نمایش داده می‌شود."
            } else {
                connectionMessage = "ارتباط با منبع قیمت برقرار نشد؛ آخرین نرخ موجود نمایش داده می‌شود."
            }
            return
        }

        sourceTitle = "نرخ زنده"
        connectionMessage = nil

        for asset in MarketAsset.allCases {
            let current = snapshot(for: asset)
            guard let nextPrice = remoteQuotes[asset] else { continue }
            let updated = current.updated(price: nextPrice)
            snapshots[asset] = updated

            if asset == .gold {
                await MarketLiveActivityManager.shared.update(with: updated)
            }

            if notificationsEnabled,
               abs(updated.change) >= threshold,
               canSendAlert(for: asset) {
                await NotificationManager.shared.sendPriceAlert(for: updated)
                lastAlertDate[asset] = .now
            }

            let direction = updated.change >= 0 ? "افزایش" : "کاهش"
            events.insert(
                MarketEvent(
                    title: "\(direction) \(asset.title): \(updated.changeText)",
                    time: "همین حالا",
                    icon: updated.change >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                    tint: updated.outlookColor
                ),
                at: 0
            )
        }

        events = Array(events.prefix(8))
        lastUpdated = Date()
    }

    private func canSendAlert(for asset: MarketAsset) -> Bool {
        guard let date = lastAlertDate[asset] else { return true }
        return Date().timeIntervalSince(date) >= 20 * 60
    }
}

private enum MarketDataClient {
    private static let liveURL = URL(string: "https://call.tgju.org/ajax.json")!
    private static let dollarFallbackURL = URL(string: "https://api.tgju.org/v1/market/indicator/summary-table-data/price_dollar_rl")!
    private static let goldFallbackURL = URL(string: "https://api.tgju.org/v1/market/indicator/summary-table-data/price_geram18")!

    static func fetchQuotes() async -> Result<[MarketAsset: Double], Error> {
        do {
            let liveData = try await request(liveURL)
            let liveQuotes = try parseLiveQuotes(from: liveData)
            if liveQuotes.count == MarketAsset.allCases.count { return .success(liveQuotes) }

            async let dollarData = request(dollarFallbackURL)
            async let goldData = request(goldFallbackURL)
            let (dollarResponse, goldResponse) = try await (dollarData, goldData)
            return .success([
                .dollar: normalizeRial(try parseFirstPrice(from: dollarResponse)),
                .gold: normalizeRial(try parseFirstPrice(from: goldResponse))
            ])
        } catch {
            return .failure(error)
        }
    }

    private static func request(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("GoldLens/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw MarketDataError.unavailable
        }
        return data
    }

    private static func parseLiveQuotes(from data: Data) throws -> [MarketAsset: Double] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let current = root["current"] as? [String: Any] ?? root
        let dollar = number(from: current["price_dollar_rl"])
        let gold = number(from: current["price_geram18"])
            ?? number(from: current["price_geram18k"])
            ?? number(from: current["price_gold_18k"])
        var quotes: [MarketAsset: Double] = [:]
        if let dollar { quotes[.dollar] = normalizeRial(dollar) }
        if let gold { quotes[.gold] = normalizeRial(gold) }
        return quotes
    }

    private static func parseFirstPrice(from data: Data) throws -> Double {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let value = firstNumber(in: json) else { throw URLError(.cannotParseResponse) }
        return value
    }

    private static func firstNumber(in value: Any) -> Double? {
        if let number = number(from: value) { return number }
        if let array = value as? [Any] {
            return array.lazy.compactMap { firstNumber(in: $0) }.first
        }
        guard let dictionary = value as? [String: Any] else { return nil }
        for key in ["data", "p", "price", "value"] {
            if let item = dictionary[key], let number = firstNumber(in: item) { return number }
        }
        return nil
    }

    private static func number(from value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String else { return nil }
        let englishDigits = string
            .replacingOccurrences(of: "٬", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "٫", with: ".")
            .applyingTransform(.toLatin, reverse: false) ?? string
        return Double(englishDigits)
    }

    private static func normalizeRial(_ value: Double) -> Double {
        value > 200_000 ? value / 10 : value
    }
}

private enum MarketDataError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "منبع قیمت موقتاً در دسترس نیست."
        }
    }
}

private final class NotificationManager {
    static let shared = NotificationManager()

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func sendPriceAlert(for snapshot: MarketSnapshot) async {
        let content = UNMutableNotificationContent()
        content.title = "هشدار نوسان \(snapshot.name)"
        content.body = "قیمت به \(snapshot.price) تومان رسید (\(snapshot.changeText))."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func sendTestNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "آزمایش هشدار بازار"
        content.body = "اعلان‌های اپ با موفقیت آماده هستند."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

@available(iOS 16.1, *)
struct MarketLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var price: String
        var change: String
        var updatedAt: Date
    }

    var assetName: String
    var symbol: String
}

@MainActor
private final class MarketLiveActivityManager {
    static let shared = MarketLiveActivityManager()
    private var activity: Activity<MarketLiveActivityAttributes>?

    func update(with snapshot: MarketSnapshot) async {
        guard #available(iOS 16.1, *) else { return }
        let state = MarketLiveActivityAttributes.ContentState(price: snapshot.price, change: snapshot.changeText, updatedAt: .now)
        if let activity {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(300)))
        } else {
            let attributes = MarketLiveActivityAttributes(assetName: snapshot.name, symbol: snapshot.icon)
            activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(300)), pushType: nil)
        }
    }
}

private enum MarketNumberFormatter {
    private static let tomanFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fa_IR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func toman(_ value: Double) -> String {
        tomanFormatter.string(from: NSNumber(value: value)) ?? "۰"
    }

    static func percent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        return "\(tomanFormatter.string(from: NSNumber(value: abs(value))) ?? "۰")٪\(sign)"
    }
}

private struct MarketEvent: Identifiable {
    let title: String; let time: String; let icon: String; let tint: Color
    var id: String { title }
    static let sample = [
        MarketEvent(title: "طلا از مقاومت روزانه عبور کرد", time: "۱۲ دقیقه پیش", icon: "arrow.up.right.circle.fill", tint: .green),
        MarketEvent(title: "نوسان دلار به محدودهٔ هشدار رسید", time: "۴۵ دقیقه پیش", icon: "bell.badge.fill", tint: .orange),
        MarketEvent(title: "خلاصهٔ روزانه آماده است", time: "امروز، ۰۹:۰۰", icon: "doc.text.fill", tint: .blue)
    ]
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
