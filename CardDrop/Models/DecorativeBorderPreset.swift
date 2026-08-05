import SwiftUI

struct DecorativeBorderPreset: Identifiable {
    let id: String
    let name: String
    let text: String
    let color: Color
    let fontName: String

    static let all: [DecorativeBorderPreset] = [

        // MARK: Timeless
        .init(id: "love",
              name: "Love",
              text: "♥  ♥  ♥",
              color: Color(red: 0.82, green: 0.15, blue: 0.22),
              fontName: "Georgia"),

        .init(id: "stars",
              name: "Stars",
              text: "★  ·  ★  ·",
              color: Color(red: 0.85, green: 0.70, blue: 0.12),
              fontName: "Futura-Medium"),

        .init(id: "starburst",
              name: "Starburst",
              text: "✦  ✧  ✦  ✧",
              color: Color(red: 0.15, green: 0.20, blue: 0.55),
              fontName: "Futura-Medium"),

        .init(id: "flowers",
              name: "Wildflowers",
              text: "✿  ❀  ✿  ❀",
              color: Color(red: 0.65, green: 0.25, blue: 0.72),
              fontName: "Georgia"),

        .init(id: "music",
              name: "Music",
              text: "♩  ♪  ♬",
              color: Color(red: 0.12, green: 0.18, blue: 0.38),
              fontName: "Georgia"),

        .init(id: "fleur",
              name: "Fleur de Lis",
              text: "⚜  ·  ⚜  ·",
              color: Color(red: 0.72, green: 0.58, blue: 0.12),
              fontName: "Georgia"),

        .init(id: "geometric",
              name: "Geometric",
              text: "◆  ◇  ·  ◆  ◇  ·",
              color: Color(red: 0.10, green: 0.52, blue: 0.58),
              fontName: "Futura-Medium"),

        .init(id: "lights",
              name: "String of Lights",
              text: "◉  ◉  ◉  ◉",
              color: Color(red: 0.95, green: 0.78, blue: 0.20),
              fontName: "HelveticaNeue"),

        .init(id: "suits",
              name: "Suit & Tie",
              text: "♥  ♦  ♣  ♠",
              color: Color(red: 0.10, green: 0.10, blue: 0.10),
              fontName: "Georgia"),

        .init(id: "newbaby",
              name: "New Baby",
              text: "✦  ○  ✦  ○",
              color: Color(red: 0.40, green: 0.72, blue: 0.90),
              fontName: "Futura-Medium"),

        // MARK: Seasonal / Holiday
        .init(id: "snowflakes",
              name: "Snowflakes",
              text: "❄  ·  ❅  ·",
              color: Color(red: 0.40, green: 0.70, blue: 0.92),
              fontName: "HelveticaNeue"),

        .init(id: "shamrock",
              name: "St. Patrick's",
              text: "☘  ·  ☘  ·",
              color: Color(red: 0.08, green: 0.55, blue: 0.20),
              fontName: "Georgia"),

        .init(id: "faith",
              name: "Faith",
              text: "✝  ·  ✝  ·",
              color: Color(red: 0.70, green: 0.55, blue: 0.10),
              fontName: "Georgia"),

        .init(id: "hanukkah",
              name: "Hanukkah",
              text: "✡  ·  ✡  ·",
              color: Color(red: 0.08, green: 0.28, blue: 0.78),
              fontName: "Georgia"),

        .init(id: "celebration",
              name: "Celebration",
              text: "✦  ✧  ·  ✦  ✧  ·",
              color: Color(red: 0.72, green: 0.12, blue: 0.18),
              fontName: "Futura-Medium"),
    ]
}
