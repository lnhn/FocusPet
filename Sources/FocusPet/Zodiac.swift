import Foundation

/// 十二星座：日期判定 + 宠物与主人的配对指数
enum Zodiac: Int, CaseIterable {
    case aries, taurus, gemini, cancer, leo, virgo
    case libra, scorpio, sagittarius, capricorn, aquarius, pisces

    var name: String {
        switch self {
        case .aries: return "白羊座"; case .taurus: return "金牛座"
        case .gemini: return "双子座"; case .cancer: return "巨蟹座"
        case .leo: return "狮子座"; case .virgo: return "处女座"
        case .libra: return "天秤座"; case .scorpio: return "天蝎座"
        case .sagittarius: return "射手座"; case .capricorn: return "摩羯座"
        case .aquarius: return "水瓶座"; case .pisces: return "双鱼座"
        }
    }

    var emoji: String {
        switch self {
        case .aries: return "♈️"; case .taurus: return "♉️"
        case .gemini: return "♊️"; case .cancer: return "♋️"
        case .leo: return "♌️"; case .virgo: return "♍️"
        case .libra: return "♎️"; case .scorpio: return "♏️"
        case .sagittarius: return "♐️"; case .capricorn: return "♑️"
        case .aquarius: return "♒️"; case .pisces: return "♓️"
        }
    }

    /// 四象：同象默契，风火/土水相生
    private var element: Int { rawValue / 3 }   // 0火 1土 2风 3水

    /// 按公历生日判定星座
    static func of(_ date: Date) -> Zodiac {
        let cal = Calendar.current
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        let md = m * 100 + d
        switch md {
        case 321...419: return .aries
        case 420...520: return .taurus
        case 521...621: return .gemini
        case 622...722: return .cancer
        case 723...822: return .leo
        case 823...922: return .virgo
        case 923...1023: return .libra
        case 1024...1122: return .scorpio
        case 1123...1221: return .sagittarius
        case 1222...1231, 101...119: return .capricorn
        case 120...218: return .aquarius
        default: return .pisces
        }
    }

    /// 配对指数（0~100，对称）+ 评语
    static func match(_ a: Zodiac, _ b: Zodiac) -> (score: Int, comment: String) {
        let base: Int
        if a.element == b.element {
            base = 90                                   // 同象：天生投缘
        } else {
            let pair = Set([a.element, b.element])
            if pair == [0, 2] || pair == [1, 3] {       // 火风 / 土水：相生
                base = 94
            } else if pair == [0, 1] || pair == [2, 3] {
                base = 76                               // 相邻：互补
            } else {
                base = 58                               // 火水 / 土风：要磨合
            }
        }
        // 确定性微调：同一对组合分数固定（±5），不同组合有差异感
        let tweak = ((a.rawValue * 7 + b.rawValue * 13) % 11) - 5
        let score = max(35, min(99, base + tweak))
        let comment: String
        switch score {
        case 90...99: comment = "天生一对，默契满分 💞"
        case 80..<90: comment = "越处越合拍，它超黏你 🥰"
        case 70..<80: comment = "稳稳的幸福，细水长流 🙂"
        case 60..<70: comment = "性格互补，多陪它就亲 😊"
        default: comment = "欢喜冤家，打打闹闹也是爱 😹"
        }
        return (score, comment)
    }
}
