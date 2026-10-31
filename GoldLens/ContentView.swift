import Charts
import ActivityKit
import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

struct ContentView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("alertThreshold") private var alertThreshold = 1.5
    @AppStorage("marketRefreshMinutes") private var marketRefreshMinutes = 5
    @AppStorage("marketRateMode") private var marketRateMode = MarketRateMode.live.rawValue
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.persian.rawValue
    @StateObject private var marketStore = MarketStore()
    @State private var selectedTab = AppTab.market
    @State private var selectedAsset = MarketAsset.gold
    private let isRunningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    var body: some View {
        TabView(selection: $selectedTab) {
            MarketDashboardView(
                notificationsEnabled: $notificationsEnabled,
                alertThreshold: $alertThreshold,
                refreshMinutes: $marketRefreshMinutes,
                rateMode: $marketRateMode,
                isRunningInPreview: isRunningInPreview,
                selectedAsset: $selectedAsset,
                marketStore: marketStore
            )
            .tabItem { Label(appText("بازار", "Market"), systemImage: "chart.xyaxis.line") }
            .tag(AppTab.market)

            PortfolioView(marketStore: marketStore)
                .tabItem { Label(appText("دارایی من", "Portfolio"), systemImage: "wallet.pass.fill") }
                .tag(AppTab.portfolio)

            SettingsView(
                notificationsEnabled: $notificationsEnabled,
                alertThreshold: $alertThreshold,
                refreshMinutes: $marketRefreshMinutes,
                rateMode: $marketRateMode
            )
                .tabItem { Label(appText("تنظیمات", "Settings"), systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(.indigo)
        // UIKit's Form caches semantic layout direction. Recreate the tab hierarchy
        // on a language change so English never remains mirrored after Persian.
        .id(appLanguage)
        .environment(\.layoutDirection, language.layoutDirection)
        .environment(\.locale, language.locale)
        .onChange(of: appLanguage) { _, _ in marketStore.resetEventsForCurrentLanguage() }
        .onOpenURL(perform: openDeepLink)
    }

    private var language: AppLanguage { AppLanguage(rawValue: appLanguage) ?? .persian }

    private func openDeepLink(_ url: URL) {
        guard url.scheme == "goldlens" else { return }
        selectedTab = .market
        if url.path.lowercased().contains("dollar") { selectedAsset = .dollar }
        if url.path.lowercased().contains("gold") { selectedAsset = .gold }
    }
}

private enum AppTab: Hashable { case market, portfolio, settings }

private struct MarketDashboardView: View {
    @Binding var notificationsEnabled: Bool
    @Binding var alertThreshold: Double
    @Binding var refreshMinutes: Int
    @Binding var rateMode: String
    let isRunningInPreview: Bool
    @Binding var selectedAsset: MarketAsset
    @State private var selectedRange: ChartRange = .week
    @State private var showAlertSheet = false
    @State private var showAllEvents = false
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
                    .accessibilityLabel(appText("به‌روزرسانی قیمت‌ها", "Refresh prices"))
                }
            }
        }
        .sheet(isPresented: $showAlertSheet) {
            AlertSettingsView(
                assetName: selectedAsset.displayName,
                isEnabled: $notificationsEnabled,
                threshold: $alertThreshold
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAllEvents) {
            EventHistoryView(events: marketStore.events)
        }
        .task(id: "\(refreshMinutes)-\(rateMode)-\(notificationsEnabled)-\(alertThreshold)") {
            guard !isRunningInPreview else { return }
            while !Task.isCancelled {
                await refreshMarket()
                try? await Task.sleep(for: .seconds(Double(refreshMinutes) * 60))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appText("نبض بازار", "Market pulse"))
                .font(.largeTitle.bold())
            Text(appText("طلا و دلار را هوشمندانه دنبال کن", "Track gold and USD with clarity"))
                .foregroundStyle(.secondary)
            Text(appText("آخرین به‌روزرسانی: ", "Last updated: ") + marketStore.lastUpdated.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var marketStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: marketStore.isRefreshing ? "arrow.triangle.2.circlepath" : marketStore.connectionMessage == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(marketStore.isRefreshing ? .blue : marketStore.connectionMessage == nil ? .green : .orange)
            Text(marketStore.isRefreshing ? appText("در حال به‌روزرسانی", "Refreshing") : marketStore.connectionMessage == nil ? appText("نرخ زنده دریافت شد", "Live rates received") : appText("اطلاعات بازار در دسترس نیست", "Market data unavailable"))
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
        Picker(appText("دارایی", "Asset"), selection: $selectedAsset) {
            ForEach(MarketAsset.allCases) { market in
                Label(market.title, systemImage: market.snapshot.icon).tag(market)
            }
        }
        .pickerStyle(.segmented)
    }

    private var priceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(selectedAsset.displayName, systemImage: asset.icon)
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
                Text(appText("تومان", "toman")).font(.headline).opacity(0.8)
            }
            Divider().overlay(.white.opacity(0.35))
            HStack {
                PriceFact(title: appText("بالاترین امروز", "Today's high"), value: asset.high)
                Spacer()
                PriceFact(title: appText("پایین‌ترین امروز", "Today's low"), value: asset.low)
                Spacer()
                PriceFact(title: appText("وضعیت داده", "Data status"), value: appText(asset.volume, "Available"))
            }
        }
        .padding(20)
        .foregroundStyle(.white)
        .background(asset.tint.gradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(appText("نمودار قیمت", "Price chart")).font(.headline)
                Spacer()
                Picker(appText("بازه", "Range"), selection: $selectedRange) {
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
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appText("شاخص‌های روند", "Trend indicators")).font(.headline)
            HStack(spacing: 10) {
                SignalTile(title: appText("روند ۷روزه", "7-day trend"), value: technicalAnalysis.trendLabel, icon: "waveform.path.ecg", tint: technicalAnalysis.tint)
                SignalTile(title: appText("نوسان", "Volatility"), value: technicalAnalysis.volatilityText, icon: "bolt.fill", tint: .orange)
                SignalTile(title: appText("حمایت ۱۴روزه", "14-day support"), value: technicalAnalysis.supportText(divisor: asset.chartDivisor), icon: "arrow.down.to.line", tint: .blue)
            }
        }
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label(appText("تحلیل داده‌محور", "Data-driven analysis"), systemImage: "sparkles").font(.headline)
                Spacer()
                Text(technicalAnalysis.trendLabel)
                    .font(.caption.bold())
                    .foregroundStyle(technicalAnalysis.tint)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(technicalAnalysis.tint.opacity(0.12), in: Capsule())
            }
            HStack(spacing: 16) {
                ConfidenceRing(value: technicalAnalysis.rsi ?? 50, tint: technicalAnalysis.tint)
                Text(technicalAnalysis.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(appText("برآورد الگوریتمی است، نه توصیهٔ خرید یا فروش.", "An algorithmic estimate, not investment advice."), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var alertsCard: some View {
        Button { showAlertSheet = true } label: {
            HStack(spacing: 14) {
                Image(systemName: notificationsEnabled ? "bell.badge.fill" : "bell.slash")
                    .font(.title3).foregroundStyle(.orange)
                    .frame(width: 42, height: 42).background(.orange.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(appText("هشدار نوسان قیمت", "Price movement alert")).font(.headline).foregroundStyle(.primary)
                    Text(notificationsEnabled ? appText("تغییر بیش از \(alertThreshold.formatted(.number.precision(.fractionLength(1))))٪ را اطلاع بده", "Notify on moves above \(alertThreshold.formatted(.number.precision(.fractionLength(1))))%") : appText("هشدارها غیرفعال هستند", "Alerts are off"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var latestAlerts: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(appText("آخرین رویدادها", "Latest events")).font(.headline)
                Spacer()
                Button(appText("مشاهده همه", "View all")) { showAllEvents = true }
                    .font(.caption).foregroundStyle(.indigo)
            }
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
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var disclaimer: some View {
        Text(appText("تحلیل‌ها قطعی نیستند و توصیهٔ خرید یا فروش به‌شمار نمی‌آیند. پیش از هر تصمیم مالی، داده را از منبع معتبر بررسی کنید.", "Analysis is not certain and is not investment advice. Verify data with a trusted source before financial decisions."))
            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
    }

    private func refresh() {
        Task {
            await refreshMarket()
        }
    }

    private func refreshMarket() async {
        await marketStore.refresh(
            notificationsEnabled: notificationsEnabled,
            threshold: alertThreshold,
            rateMode: MarketRateMode(rawValue: rateMode) ?? .live
        )
    }

    private var technicalAnalysis: MarketTechnicalAnalysis {
        MarketTechnicalAnalysis(series: asset.series, chartDivisor: asset.chartDivisor)
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
                Section(appText("ترکیب دارایی", "Allocation")) {
                    PortfolioRow(title: appText("طلا", "Gold"), value: goldValue, total: totalValue, tint: .orange)
                    PortfolioRow(title: appText("دلار", "USD"), value: dollarValue, total: totalValue, tint: .blue)
                }
                Section(appText("یادآوری", "Note")) {
                    Text(appText("ارزش‌ها با نرخ‌های زنده محاسبه می‌شوند و کارمزد خرید و فروش را دربرنمی‌گیرند.", "Values use live rates and exclude trading fees."))
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
    @Binding var refreshMinutes: Int
    @Binding var rateMode: String
    @AppStorage("appLanguage") private var appLanguage = AppLanguage.persian.rawValue
    @State private var notificationTestStatus: String?

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
                Section(appText("اعلان‌ها", "Notifications")) {
                    Toggle(appText("هشدار نوسان", "Movement alerts"), isOn: $notificationsEnabled)
                    Button(appText("آزمایش اعلان", "Test notification")) {
                        Task {
                            notificationTestStatus = await NotificationManager.shared.sendTestNotification()
                        }
                    }
                    if let notificationTestStatus {
                        Text(notificationTestStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    if notificationsEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appText("آستانه هشدار: ", "Alert threshold: ") + MarketNumberFormatter.decimal(alertThreshold) + "%")
                            Slider(value: $alertThreshold, in: 0.5...5, step: 0.5)
                        }
                    }
                }
                Section(appText("دادهٔ بازار", "Market data")) {
                    Picker(appText("مرجع نرخ", "Rate source"), selection: $rateMode) {
                        ForEach(MarketRateMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    Picker(appText("بازهٔ به‌روزرسانی", "Refresh interval"), selection: $refreshMinutes) {
                        Text(appText("۱ دقیقه", "1 minute")).tag(1)
                        Text(appText("۵ دقیقه", "5 minutes")).tag(5)
                        Text(appText("۱۵ دقیقه", "15 minutes")).tag(15)
                        Text(appText("۳۰ دقیقه", "30 minutes")).tag(30)
                    }
                    LabeledContent(appText("نوع نرخ", "Rate type"), value: appText("بازار آزاد", "Open market"))
                    Text(appText("هر دو حالت از TGJU استفاده می‌کنند: «زنده» نرخ لحظه‌ای را با تاریخچهٔ روزانه تطبیق می‌دهد و «تاریخچهٔ تأییدشده» فقط دادهٔ روزانه را نمایش می‌دهد.", "Both options use TGJU: Live validates a current quote with daily history, while Verified history uses only daily market data."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(appText("درباره تحلیل", "About analysis")) {
                    Text(appText("روند و نوسان از ۳۰ قیمت بسته‌شدن روزانهٔ منبع بازار محاسبه می‌شوند. هیچ مدلی نمی‌تواند آیندهٔ قیمت را قطعی پیش‌بینی کند.", "Trend and volatility are calculated from the market source's 30 daily closing prices. No model can predict future prices with certainty."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(appText("تنظیمات", "Settings"))
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
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct EventHistoryView: View {
    let events: [MarketEvent]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(events) { event in
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                        Text(event.time).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: event.icon).foregroundStyle(event.tint)
                }
            }
            .navigationTitle(appText("همهٔ رویدادها", "All events"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(appText("انجام شد", "Done")) { dismiss() } } }
        }
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
                Section(appText("اعلان‌ها", "Notifications")) { Toggle(appText("هشدار \(assetName)", "Alert for \(assetName)"), isOn: $isEnabled) }
                Section(appText("حساسیت", "Sensitivity")) {
                    Slider(value: $threshold, in: 0.5...5, step: 0.5)
                    Text(appText("هنگام تغییر بیش از \(threshold.formatted(.number.precision(.fractionLength(1))))٪ اطلاع می‌دهیم.", "You will be notified when the move exceeds \(threshold.formatted(.number.precision(.fractionLength(1))))%.")) .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(appText("تنظیم هشدار", "Alert settings"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(appText("انجام شد", "Done")) { dismiss() } } }
        }
    }
}

private enum MarketAsset: String, CaseIterable, Identifiable {
    case gold, dollar
    var id: String { rawValue }
    var title: String { self == .gold ? appText("طلا", "Gold") : appText("دلار", "USD") }
    var displayName: String { self == .gold ? appText("هر گرم طلای ۱۸ عیار", "18K gold (per gram)") : appText("دلار آزاد", "US dollar (open market)") }
    var snapshot: MarketSnapshot { self == .gold ? .gold : .dollar }
}

private enum ChartRange: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return appText("۱روز", "1D")
        case .week: return appText("۷روز", "7D")
        case .month: return appText("۱ماه", "1M")
        }
    }
}

private enum MarketRateMode: String, CaseIterable, Identifiable {
    case live, verifiedHistory
    var id: String { rawValue }
    var title: String {
        switch self {
        case .live: appText("TGJU زنده + تطبیق تاریخچه", "TGJU live + history check")
        case .verifiedHistory: appText("TGJU تاریخچهٔ تأییدشده", "TGJU verified history")
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

private var appUsesEnglish: Bool {
    (AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "fa") ?? .persian) == .english
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

    /// A transparent, on-device signal based on the visible price history.
    /// It deliberately does not claim to predict the market or require a remote AI service.
    var dataDrivenAnalysis: String {
        MarketInsight.summary(for: series, priceDivisor: chartDivisor, english: appUsesEnglish)
    }

    func updated(with quote: MarketQuote) -> MarketSnapshot {
        let chartPrice = Int((quote.price / chartDivisor).rounded())
        let priceChange = quote.changePercent ?? ((quote.price - numericPrice) / numericPrice) * 100
        let newSeries = quote.history.isEmpty
            ? Array((series + [chartPrice]).suffix(30))
            : quote.history.map { Int(($0 / chartDivisor).rounded()) }
        return MarketSnapshot(
            name: name, icon: icon, tint: tint, price: MarketNumberFormatter.toman(quote.price), numericPrice: quote.price,
            chartDivisor: chartDivisor, high: MarketNumberFormatter.toman(quote.high ?? quote.price),
            low: MarketNumberFormatter.toman(quote.low ?? quote.price), volume: volume, change: priceChange,
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

private enum MarketInsight {
    static func summary(for series: [Int], priceDivisor _: Double, english: Bool) -> String {
        guard let first = series.suffix(7).first, let last = series.last, first != 0 else {
            return english ? "Not enough market history is available to calculate a trend." : "دادهٔ کافی برای تحلیل روند هنوز در دسترس نیست."
        }
        let window = Array(series.suffix(7))
        let momentum = (Double(last - first) / Double(first)) * 100
        let mean = window.map(Double.init).reduce(0, +) / Double(window.count)
        let variance = window.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(window.count)
        let volatility = sqrt(variance) / max(mean, 1) * 100
        let direction = momentum >= 0 ? (english ? "upward" : "صعودی") : (english ? "downward" : "نزولی")
        let risk = volatility > 1.2 ? (english ? "Volatility is high" : "نوسان بالا") : (english ? "Volatility is contained" : "نوسان کنترل‌شده")
        let roundedMomentum = abs(momentum).formatted(.number.precision(.fractionLength(1)))
        return english
            ? "The recent seven-day trend is \(direction) (\(roundedMomentum)%). \(risk). This is calculated from market prices, not investment advice."
            : "روند هفت دادهٔ اخیر \(direction) است (\(roundedMomentum)٪). \(risk)؛ این نتیجه از تغییرات قیمت محاسبه می‌شود و توصیهٔ سرمایه‌گذاری نیست."
    }
}

/// Technical metrics calculated locally from the received closing-price series.
/// They are descriptive, never a trading recommendation.
private struct MarketTechnicalAnalysis {
    let series: [Int]
    let chartDivisor: Double

    init(series: [Int], chartDivisor: Double) {
        self.series = series
        self.chartDivisor = chartDivisor
    }

    private var recent: [Int] { Array(series.suffix(7)) }
    private var momentum: Double {
        guard let first = recent.first, let last = recent.last, first != 0 else { return 0 }
        return (Double(last - first) / Double(first)) * 100
    }
    private var average7: Double? {
        guard recent.count >= 2 else { return nil }
        return recent.map(Double.init).reduce(0, +) / Double(recent.count)
    }
    private var average30: Double? {
        guard series.count >= 14 else { return nil }
        return series.map(Double.init).reduce(0, +) / Double(series.count)
    }
    private var volatility: Double {
        guard recent.count >= 3 else { return 0 }
        let returns = zip(recent.dropFirst(), recent).compactMap { previous, current -> Double? in
            guard previous != 0 else { return nil }
            return (Double(current - previous) / Double(previous)) * 100
        }
        guard !returns.isEmpty else { return 0 }
        let mean = returns.reduce(0, +) / Double(returns.count)
        return sqrt(returns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(returns.count))
    }
    var rsi: Double? {
        let window = Array(series.suffix(15))
        guard window.count >= 15 else { return nil }
        let moves = zip(window.dropFirst(), window).map { Double($1 - $0) }
        let gains = moves.map { max($0, 0) }.reduce(0, +) / Double(moves.count)
        let losses = moves.map { max(-$0, 0) }.reduce(0, +) / Double(moves.count)
        guard losses > 0 else { return 100 }
        let relativeStrength = gains / losses
        return 100 - (100 / (1 + relativeStrength))
    }
    private var isUptrend: Bool {
        guard let average7, let average30 else { return momentum >= 0 }
        return average7 >= average30 && momentum >= 0
    }
    var tint: Color { momentum > 0.15 ? .green : momentum < -0.15 ? .red : .orange }
    var trendLabel: String {
        if momentum > 0.15 { return appText("صعودی", "Upward") }
        if momentum < -0.15 { return appText("نزولی", "Downward") }
        return appText("خنثی", "Neutral")
    }
    var volatilityText: String {
        let value = MarketNumberFormatter.decimal(volatility)
        return "\(value)%"
    }
    func supportText(divisor: Double) -> String {
        let support = Double(series.suffix(14).min() ?? series.last ?? 0) * divisor
        return MarketNumberFormatter.toman(support)
    }
    var summary: String {
        let move = MarketNumberFormatter.decimal(abs(momentum))
        let relationship: String
        if average30 == nil {
            relationship = appText("دادهٔ کافی برای مقایسهٔ میانگین بلندمدت هنوز نیست", "not enough history is available for a longer average")
        } else {
            relationship = isUptrend
                ? appText("میانگین ۷روزه بالاتر از میانگین تاریخچه است", "the 7-day average is above the historical average")
                : appText("میانگین ۷روزه پایین‌تر از میانگین تاریخچه است", "the 7-day average is below the historical average")
        }
        let rsiText = rsi.map { MarketNumberFormatter.decimal($0, digits: 0) } ?? "—"
        return appUsesEnglish
            ? "Seven-day movement: \(move)% \(momentum >= 0 ? "up" : "down"); \(relationship). RSI(14): \(rsiText), daily-return volatility: \(volatilityText)."
            : "تغییر هفت‌روزه: \(move)٪ \(momentum >= 0 ? "افزایش" : "کاهش")؛ \(relationship). RSI(۱۴): \(rsiText)، نوسان بازده روزانه: \(volatilityText)."
    }
}

private struct PricePoint: Identifiable { let label: String; let value: Int; var id: String { label } }

private struct MarketQuote {
    let price: Double
    let high: Double?
    let low: Double?
    let changePercent: Double?
    let history: [Double]
}

@MainActor
private final class MarketStore: ObservableObject {
    @Published private(set) var lastUpdated = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var sourceTitle = "منبع عمومی"
    @Published private(set) var connectionMessage: String?
    @Published private(set) var events = MarketEvent.sample()

    @Published private var snapshots: [MarketAsset: MarketSnapshot] = [
        .gold: .gold,
        .dollar: .dollar
    ]
    private var lastAlertDate: [MarketAsset: Date] = [:]

    init() {
        guard let cache = OfflineMarketCache.load() else { return }
        snapshots[.gold] = snapshots[.gold]?.updated(with: MarketQuote(price: cache.goldPrice, high: nil, low: nil, changePercent: nil, history: [])) ?? .gold
        snapshots[.dollar] = snapshots[.dollar]?.updated(with: MarketQuote(price: cache.dollarPrice, high: nil, low: nil, changePercent: nil, history: [])) ?? .dollar
        lastUpdated = cache.updatedAt
        sourceTitle = "آخرین دادهٔ ذخیره‌شده"
        connectionMessage = "حالت آفلاین: آخرین نرخ ذخیره‌شده نمایش داده می‌شود."
    }

    func snapshot(for asset: MarketAsset) -> MarketSnapshot {
        snapshots[asset] ?? asset.snapshot
    }

    func refresh(notificationsEnabled: Bool, threshold: Double, rateMode: MarketRateMode) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await MarketDataClient.fetchQuotes(mode: rateMode)
        guard case let .success(remoteQuotes) = result else {
            sourceTitle = "منبع قیمت در دسترس نیست"
            if case let .failure(error) = result {
                connectionMessage = "\(error.localizedDescription) آخرین نرخ موجود نمایش داده می‌شود."
            } else {
                connectionMessage = "ارتباط با منبع قیمت برقرار نشد؛ آخرین نرخ موجود نمایش داده می‌شود."
            }
            return
        }

        sourceTitle = rateMode.title
        connectionMessage = nil

        for asset in MarketAsset.allCases {
            let current = snapshot(for: asset)
            guard let quote = remoteQuotes[asset] else { continue }
            let hasMeaningfulPriceChange = current.numericPrice > 0 && abs(quote.price - current.numericPrice) / current.numericPrice >= 0.0001
            let updated = current.updated(with: quote)
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

            if hasMeaningfulPriceChange {
                let direction = updated.change >= 0 ? appText("افزایش", "Increase") : appText("کاهش", "Decrease")
                events.removeAll { $0.asset == asset }
                events.insert(
                    MarketEvent(
                        asset: asset,
                        title: "\(direction) \(asset.title): \(updated.changeText)",
                        time: appText("همین حالا", "Just now"),
                        icon: updated.change >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill",
                        tint: updated.outlookColor
                    ),
                    at: 0
                )
            }
        }

        events = Array(events.prefix(8))
        lastUpdated = Date()
        OfflineMarketCache.save(
            goldPrice: snapshot(for: .gold).numericPrice,
            dollarPrice: snapshot(for: .dollar).numericPrice,
            updatedAt: lastUpdated
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func canSendAlert(for asset: MarketAsset) -> Bool {
        guard let date = lastAlertDate[asset] else { return true }
        return Date().timeIntervalSince(date) >= 20 * 60
    }

    func resetEventsForCurrentLanguage() {
        events = MarketEvent.sample()
    }
}

private struct OfflineMarketCache: Codable {
    let goldPrice: Double
    let dollarPrice: Double
    let updatedAt: Date
    private static let key = "offlineMarketCache.v1"

    static func load() -> OfflineMarketCache? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OfflineMarketCache.self, from: data)
    }

    static func save(goldPrice: Double, dollarPrice: Double, updatedAt: Date) {
        let cache = OfflineMarketCache(goldPrice: goldPrice, dollarPrice: dollarPrice, updatedAt: updatedAt)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum MarketDataClient {
    private static let liveURL = URL(string: "https://call.tgju.org/ajax.json")!
    private static let dollarFallbackURL = URL(string: "https://api.tgju.org/v1/market/indicator/summary-table-data/price_dollar_rl")!
    private static let goldFallbackURL = URL(string: "https://api.tgju.org/v1/market/indicator/summary-table-data/geram18")!

    static func fetchQuotes(mode: MarketRateMode) async -> Result<[MarketAsset: MarketQuote], Error> {
        do {
            if mode == .live {
                let live = try parseLiveQuotes(from: await request(liveURL, timeout: 8))
                guard live.count == MarketAsset.allCases.count else { throw MarketDataError.unavailable }

                // Daily history is useful for local indicators, but it is much larger than
                // the live endpoint. A slow history response must never hide a valid live rate.
                async let dollarData: Data? = try? request(dollarFallbackURL, timeout: 8)
                async let goldData: Data? = try? request(goldFallbackURL, timeout: 8)
                let (dollarResponse, goldResponse) = await (dollarData, goldData)
                let fallback = [
                    MarketAsset.dollar: dollarResponse.flatMap { try? parseFallbackQuote(from: $0) },
                    MarketAsset.gold: goldResponse.flatMap { try? parseFallbackQuote(from: $0) }
                ]
                return .success(MarketAsset.allCases.reduce(into: [:]) { quotes, asset in
                    guard let liveQuote = live[asset] else { return }
                    let historyQuote = fallback[asset] ?? nil
                    quotes[asset] = MarketQuote(
                        price: liveQuote.price,
                        high: liveQuote.high,
                        low: liveQuote.low,
                        changePercent: liveQuote.changePercent,
                        history: historyQuote?.history ?? []
                    )
                })
            }

            async let dollarData = request(dollarFallbackURL)
            async let goldData = request(goldFallbackURL)
            let (dollarResponse, goldResponse) = try await (dollarData, goldData)
            let fallback = [
                MarketAsset.dollar: try parseFallbackQuote(from: dollarResponse),
                MarketAsset.gold: try parseFallbackQuote(from: goldResponse)
            ]
            return .success(fallback)
        } catch {
            return .failure(error)
        }
    }

    private static func request(_ url: URL, timeout: TimeInterval = 20) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("GoldLens/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw MarketDataError.unavailable
        }
        return data
    }

    private static func parseLiveQuotes(from data: Data) throws -> [MarketAsset: MarketQuote] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else { throw URLError(.cannotParseResponse) }
        let current = root["current"] as? [String: Any] ?? root
        let dollar = quote(from: current["price_dollar_rl"])
        let gold = quote(from: current["geram18"])
        var quotes: [MarketAsset: MarketQuote] = [:]
        if let dollar { quotes[.dollar] = normalizeRial(dollar) }
        if let gold { quotes[.gold] = normalizeRial(gold) }
        return quotes
    }

    private static func parseFallbackQuote(from data: Data) throws -> MarketQuote {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any],
              let rows = root["data"] as? [[Any]],
              let row = rows.first,
              row.count >= 4,
              let price = number(from: row[3]) else { throw URLError(.cannotParseResponse) }
        return normalizeRial(MarketQuote(
            price: price,
            high: row.count > 2 ? number(from: row[2]) : nil,
            low: row.count > 1 ? number(from: row[1]) : nil,
            changePercent: row.count > 5 ? number(from: row[5]) : nil,
            history: rows.prefix(30).reversed().compactMap { row in
                guard row.count > 3 else { return nil }
                return number(from: row[3])
            }
        ))
    }

    private static func quote(from value: Any?) -> MarketQuote? {
        guard let dictionary = value as? [String: Any],
              let price = number(from: dictionary["p"]) else { return nil }
        return MarketQuote(
            price: price,
            high: number(from: dictionary["h"]),
            low: number(from: dictionary["l"]),
            changePercent: number(from: dictionary["dp"]),
            history: []
        )
    }

    private static func number(from value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String else { return nil }
        let englishDigits = string
            .replacingOccurrences(of: "٬", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "٫", with: ".")
            .applyingTransform(.toLatin, reverse: false) ?? string
        if let direct = Double(englishDigits) { return direct }
        let numericCharacters = englishDigits.unicodeScalars.filter {
            CharacterSet(charactersIn: "0123456789.-").contains($0)
        }
        return Double(String(String.UnicodeScalarView(numericCharacters)))
    }

    private static func normalizeRial(_ quote: MarketQuote) -> MarketQuote {
        func toman(_ value: Double?) -> Double? {
            guard let value else { return nil }
            return value > 200_000 ? value / 10 : value
        }
        return MarketQuote(
            price: toman(quote.price) ?? quote.price,
            high: toman(quote.high),
            low: toman(quote.low),
            changePercent: quote.changePercent,
            history: quote.history.compactMap(toman)
        )
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

private final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func sendPriceAlert(for snapshot: MarketSnapshot) async {
        let content = UNMutableNotificationContent()
        content.title = appText("هشدار نوسان \(snapshot.name)", "Price movement alert")
        content.body = appText("قیمت به \(snapshot.price) تومان رسید (\(snapshot.changeText)).", "Price reached \(snapshot.price) toman (\(snapshot.changeText)).")
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func sendTestNotification() async -> String {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) == true
            guard granted else {
                return appText("مجوز اعلان داده نشده است؛ آن را از تنظیمات iPhone فعال کنید.", "Notification permission is off. Enable it in iPhone Settings.")
            }
            return await sendTestNotification()
        }
        let content = UNMutableNotificationContent()
        content.title = appText("آزمایش هشدار بازار", "Market alert test")
        content.body = appText("اعلان‌های اپ با موفقیت آماده هستند.", "App notifications are ready.")
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        do {
            try await center.add(request)
            return appText("اعلان آزمایشی ارسال شد.", "Test notification sent.")
        } catch {
            return appText("ارسال اعلان ناموفق بود.", "Could not send the test notification.")
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@available(iOS 16.1, *)
nonisolated struct MarketLiveActivityAttributes: ActivityAttributes {
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
    private static func formatter(maximumFractionDigits: Int = 0) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: appUsesEnglish ? "en_US_POSIX" : "fa_IR")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter
    }

    static func toman(_ value: Double) -> String {
        formatter().string(from: NSNumber(value: value)) ?? (appUsesEnglish ? "0" : "۰")
    }

    static func percent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        let number = formatter(maximumFractionDigits: 1).string(from: NSNumber(value: abs(value))) ?? "0"
        return appUsesEnglish ? "\(sign)\(number)%" : "\(number)٪\(sign)"
    }

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        formatter(maximumFractionDigits: digits).string(from: NSNumber(value: value)) ?? "0"
    }
}

private struct MarketEvent: Identifiable {
    let asset: MarketAsset?
    let title: String; let time: String; let icon: String; let tint: Color
    var id: String { "\(asset?.rawValue ?? "general")-\(title)" }
    static func sample() -> [MarketEvent] {
        [
        MarketEvent(asset: .gold, title: appText("طلا از مقاومت روزانه عبور کرد", "Gold crossed daily resistance"), time: appText("۱۲ دقیقه پیش", "12 minutes ago"), icon: "arrow.up.right.circle.fill", tint: .green),
        MarketEvent(asset: .dollar, title: appText("نوسان دلار به محدودهٔ هشدار رسید", "USD volatility reached the alert range"), time: appText("۴۵ دقیقه پیش", "45 minutes ago"), icon: "bell.badge.fill", tint: .orange),
        MarketEvent(asset: nil, title: appText("خلاصهٔ روزانه آماده است", "Daily summary is ready"), time: appText("امروز، ۰۹:۰۰", "Today, 09:00"), icon: "doc.text.fill", tint: .blue)
        ]
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
