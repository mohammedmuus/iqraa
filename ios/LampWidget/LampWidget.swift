import SwiftUI
import WidgetKit

/// Home screen light. It glows bright while the reader opens Iqraa, then dims over a week away,
/// and the verse beside it grows firmer as it dims. The app writes its data to the shared app group.
private let appGroup = "group.tz.or.iqraa"
private let dataKey = "lamp"

struct LampEntry: TimelineEntry {
  let date: Date
  let stage: Int
  let label: String
  let verse: String
  let reference: String
  let rtl: Bool
}

struct LampProvider: TimelineProvider {
  func placeholder(in context: Context) -> LampEntry {
    LampEntry(date: Date(), stage: 0, label: "", verse: emptyText(), reference: "", rtl: false)
  }

  func getSnapshot(in context: Context, completion: @escaping (LampEntry) -> Void) {
    completion(entry(at: Date()))
  }

  /// One entry now and one at each of the next seven midnights, so the light dims even while the app stays closed.
  func getTimeline(in context: Context, completion: @escaping (Timeline<LampEntry>) -> Void) {
    let calendar = Calendar.current
    var entries = [entry(at: Date())]
    var day = calendar.startOfDay(for: Date())
    for _ in 0..<7 {
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
      entries.append(entry(at: day))
    }
    completion(Timeline(entries: entries, policy: .atEnd))
  }

  private func entry(at date: Date) -> LampEntry {
    guard
      let text = UserDefaults(suiteName: appGroup)?.string(forKey: dataKey),
      let raw = text.data(using: .utf8),
      let data = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
    else {
      return LampEntry(date: date, stage: 3, label: "", verse: emptyText(), reference: "", rtl: false)
    }
    let calendar = Calendar.current
    let openedMs = (data["opened"] as? NSNumber)?.doubleValue ?? 0
    let opened = calendar.startOfDay(for: Date(timeIntervalSince1970: openedMs / 1000))
    let days = max(0, calendar.dateComponents([.day], from: opened, to: calendar.startOfDay(for: date)).day ?? 0)
    let stage = days <= 1 ? 0 : days <= 3 ? 1 : days <= 6 ? 2 : 3
    let labels = data["labels"] as? [String: String] ?? [:]
    let template: String
    switch days {
    case 0: template = labels["today"] ?? ""
    case 1: template = labels["one"] ?? ""
    default: template = (stage < 3 ? labels["days"] : labels["out"]) ?? ""
    }
    var verse = ""
    var reference = ""
    if let stages = data["stages"] as? [[[String: String]]], stage < stages.count, !stages[stage].isEmpty {
      let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
      let pick = stages[stage][dayOfYear % stages[stage].count]
      verse = pick["text"] ?? ""
      reference = pick["ref"] ?? ""
    }
    if verse.isEmpty {
      verse = labels["empty"] ?? emptyText()
    }
    return LampEntry(
      date: date,
      stage: stage,
      label: template.replacingOccurrences(of: "{n}", with: String(days)),
      verse: verse,
      reference: reference,
      rtl: data["rtl"] as? Bool ?? false
    )
  }

  private func emptyText() -> String {
    let language = Locale.preferredLanguages.first?.prefix(2) ?? "en"
    switch language {
    case "sw": return "Fungua Iqraa uwashe taa yako"
    case "ar": return "افتح اقرأ ليضيء مصباحك"
    default: return "Open Iqraa to turn your light on"
    }
  }
}

private struct Look {
  let card: Color
  let heading: Color
  let words: Color
  let small: Color

  static let stages = [
    Look(card: Color(hex: 0xFFFDF7), heading: Color(hex: 0x1F6B4A), words: Color(hex: 0x0B0B0C), small: Color(hex: 0x6E6E68)),
    Look(card: Color(hex: 0xF6EEDC), heading: Color(hex: 0x8A6A2E), words: Color(hex: 0x2B2925), small: Color(hex: 0x6E6E68)),
    Look(card: Color(hex: 0x2B2925), heading: Color(hex: 0xE3CF9F), words: .white, small: Color(hex: 0xC9C6BC)),
    Look(card: Color(hex: 0x0B0B0C), heading: Color(hex: 0xE3CF9F), words: .white, small: Color(hex: 0xA3A39E)),
  ]
}

struct LampView: View {
  let entry: LampEntry

  var body: some View {
    let look = Look.stages[min(max(entry.stage, 0), 3)]
    HStack(spacing: 12) {
      LampDrawing(stage: entry.stage)
        .frame(width: 60, height: 60)
      VStack(alignment: .leading, spacing: 3) {
        if !entry.label.isEmpty {
          Text(entry.label).font(.system(size: 12, weight: .bold)).foregroundColor(look.heading).lineLimit(1)
        }
        Text(entry.verse).font(.system(size: 13.5)).foregroundColor(look.words).lineLimit(4)
        if !entry.reference.isEmpty {
          Text(entry.reference).font(.system(size: 11)).foregroundColor(look.small).lineLimit(1).padding(.top, 1)
        }
      }
      Spacer(minLength: 0)
    }
    .environment(\.layoutDirection, entry.rtl ? .rightToLeft : .leftToRight)
    .lampBackground(look.card)
  }
}

/// The same light bulb as the Android widget, drawn on an 84 by 84 grid. It glows while the reader keeps
/// coming back and goes dark after a week away.
struct LampDrawing: View {
  let stage: Int

  private var glass: Color { [Color(hex: 0xFFE7A3), Color(hex: 0xFBEFC9), Color(hex: 0xE9E2CF), Color(hex: 0x5A5A55)][min(max(stage, 0), 3)] }
  private var rim: Color { [Color(hex: 0xC9A86A), Color(hex: 0xC9A86A), Color(hex: 0xB8B2A2), Color(hex: 0xA3A39E)][min(max(stage, 0), 3)] }
  private var filament: Color { [Color(hex: 0xE9A23B), Color(hex: 0xD9963A), Color(hex: 0xC2702B), Color(hex: 0x8E8C85)][min(max(stage, 0), 3)] }

  var body: some View {
    ZStack {
      if stage == 0 {
        LampPath { $0.addEllipse(in: CGRect(x: 12, y: 2, width: 60, height: 60)) }.fill(Color(hex: 0xF2B544).opacity(0.22))
        LampPath { p in
          for (from, to) in [((42, 3), (42, 7)), ((15, 10), (18, 13)), ((69, 10), (66, 13)), ((8, 32), (12, 32)), ((76, 32), (72, 32))] {
            p.move(to: CGPoint(x: from.0, y: from.1))
            p.addLine(to: CGPoint(x: to.0, y: to.1))
          }
        }.stroke(Color(hex: 0xF2B544), style: StrokeStyle(lineWidth: 2, lineCap: .round))
      } else if stage == 1 {
        LampPath { $0.addEllipse(in: CGRect(x: 18, y: 8, width: 48, height: 48)) }.fill(Color(hex: 0xF2B544).opacity(0.12))
      }
      LampPath(draw: bulb).fill(glass)
      LampPath(draw: bulb).stroke(rim, lineWidth: 1.4)
      LampPath { p in
        p.move(to: CGPoint(x: 36, y: 53))
        p.addLine(to: CGPoint(x: 36, y: 41))
        p.addLine(to: CGPoint(x: 39, y: 35))
        p.addLine(to: CGPoint(x: 42, y: 41))
        p.addLine(to: CGPoint(x: 45, y: 35))
        p.addLine(to: CGPoint(x: 48, y: 41))
        p.addLine(to: CGPoint(x: 48, y: 53))
      }.stroke(filament, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
      LampPath { $0.addRect(CGRect(x: 31, y: 54, width: 22, height: 4)) }.fill(Color(hex: 0xA3A39E))
      LampPath { $0.addRect(CGRect(x: 32, y: 59, width: 20, height: 3)) }.fill(Color(hex: 0x8C8C86))
      LampPath { p in
        p.move(to: CGPoint(x: 36, y: 63))
        p.addLine(to: CGPoint(x: 48, y: 63))
        p.addLine(to: CGPoint(x: 46, y: 67))
        p.addLine(to: CGPoint(x: 38, y: 67))
        p.closeSubpath()
      }.fill(Color(hex: 0x6E6E68))
    }
  }

  private func bulb(_ p: inout Path) {
    p.move(to: CGPoint(x: 30, y: 46))
    p.addCurve(to: CGPoint(x: 22, y: 32), control1: CGPoint(x: 26, y: 42), control2: CGPoint(x: 22, y: 38))
    p.addCurve(to: CGPoint(x: 42, y: 13), control1: CGPoint(x: 22, y: 21), control2: CGPoint(x: 31, y: 13))
    p.addCurve(to: CGPoint(x: 62, y: 32), control1: CGPoint(x: 53, y: 13), control2: CGPoint(x: 62, y: 21))
    p.addCurve(to: CGPoint(x: 54, y: 46), control1: CGPoint(x: 62, y: 38), control2: CGPoint(x: 58, y: 42))
    p.addLine(to: CGPoint(x: 52, y: 53))
    p.addLine(to: CGPoint(x: 32, y: 53))
    p.closeSubpath()
  }
}

/// A path drawn on the 84 by 84 grid and scaled to the space it is given.
private struct LampPath: Shape {
  let draw: (inout Path) -> Void

  func path(in rect: CGRect) -> Path {
    var path = Path()
    draw(&path)
    return path.applying(CGAffineTransform(scaleX: rect.width / 84, y: rect.height / 84))
  }
}

private extension View {
  @ViewBuilder func lampBackground(_ color: Color) -> some View {
    if #available(iOS 17.0, *) {
      self.containerBackground(color, for: .widget)
    } else {
      self.padding(14).background(color)
    }
  }
}

private extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

@main
struct IqraaLampWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "IqraaLamp", provider: LampProvider()) { entry in
      LampView(entry: entry)
    }
    .configurationDisplayName("Iqraa light")
    .description("A light that dims when you stay away, with a verse to bring you back.")
    .supportedFamilies([.systemMedium])
  }
}
