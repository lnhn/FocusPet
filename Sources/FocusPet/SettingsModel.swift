import Foundation

/// 设置模型：UserDefaults 持久化，变更时通过 onChange 通知 AppDelegate 即时生效
final class SettingsModel: ObservableObject {
    @Published var focusMinutes: Double {
        didSet { UserDefaults.standard.set(focusMinutes, forKey: Keys.focusMinutes); notify() }
    }
    @Published var shortRestMinutes: Double {
        didSet { UserDefaults.standard.set(shortRestMinutes, forKey: Keys.shortRestMinutes); notify() }
    }
    @Published var longRestMinutes: Double {
        didSet { UserDefaults.standard.set(longRestMinutes, forKey: Keys.longRestMinutes); notify() }
    }
    @Published var cycleCount: Double {
        didSet { UserDefaults.standard.set(cycleCount, forKey: Keys.cycleCount); notify() }
    }
    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin); notify() }
    }
    @Published var hotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: Keys.hotkeyEnabled); notify() }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Keys.soundEnabled); notify() }
    }
    @Published var selectedPet: String {
        didSet { UserDefaults.standard.set(selectedPet, forKey: Keys.selectedPet); notify() }
    }
    @Published var petSizePercent: Double {
        didSet { UserDefaults.standard.set(petSizePercent, forKey: Keys.petSizePercent); notify() }
    }

    // MARK: - 宠物与主人资料

    @Published var catName: String {
        didSet { UserDefaults.standard.set(catName, forKey: Keys.catName); notify() }
    }
    @Published var dogName: String {
        didSet { UserDefaults.standard.set(dogName, forKey: Keys.dogName); notify() }
    }
    @Published var catBirthday: Date? {
        didSet {
            saveOptional(catBirthday, key: Keys.catBirthday)
            notify()
        }
    }
    @Published var dogBirthday: Date? {
        didSet {
            saveOptional(dogBirthday, key: Keys.dogBirthday)
            notify()
        }
    }
    @Published var ownerBirthday: Date? {
        didSet {
            saveOptional(ownerBirthday, key: Keys.ownerBirthday)
            notify()
        }
    }
    /// 相遇纪念日：默认记为首次启动那天
    @Published var adoptionDate: Date? {
        didSet {
            saveOptional(adoptionDate, key: Keys.adoptionDate)
            notify()
        }
    }

    /// 当前宠物的名字/生日
    var currentPetName: String { selectedPet == "dog" ? dogName : catName }
    var currentPetBirthday: Date? { selectedPet == "dog" ? dogBirthday : catBirthday }

    /// AppDelegate 注入：任何设置变化后立即应用
    var onChange: (() -> Void)?

    private enum Keys {
        static let focusMinutes = "focusMinutes"
        static let shortRestMinutes = "shortRestMinutes"
        static let longRestMinutes = "longRestMinutes"
        static let cycleCount = "cycleCount"
        static let launchAtLogin = "launchAtLogin"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let soundEnabled = "soundEnabled"
        static let selectedPet = "selectedPet"
        static let petSizePercent = "petSizePercent"
        static let catName = "catName"
        static let dogName = "dogName"
        static let catBirthday = "catBirthday"
        static let dogBirthday = "dogBirthday"
        static let ownerBirthday = "ownerBirthday"
        static let adoptionDate = "adoptionDate"
    }

    private func saveOptional(_ date: Date?, key: String) {
        if let date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        focusMinutes = defaults.object(forKey: Keys.focusMinutes) as? Double ?? 25
        shortRestMinutes = defaults.object(forKey: Keys.shortRestMinutes) as? Double ?? 5
        longRestMinutes = defaults.object(forKey: Keys.longRestMinutes) as? Double ?? 15
        cycleCount = defaults.object(forKey: Keys.cycleCount) as? Double ?? 4
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        hotkeyEnabled = defaults.object(forKey: Keys.hotkeyEnabled) as? Bool ?? true
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        selectedPet = defaults.object(forKey: Keys.selectedPet) as? String ?? "cat"
        petSizePercent = defaults.object(forKey: Keys.petSizePercent) as? Double ?? 75

        catName = defaults.object(forKey: Keys.catName) as? String ?? "咪咪"
        dogName = defaults.object(forKey: Keys.dogName) as? String ?? "旺财"
        catBirthday = (defaults.object(forKey: Keys.catBirthday) as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        dogBirthday = (defaults.object(forKey: Keys.dogBirthday) as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        ownerBirthday = (defaults.object(forKey: Keys.ownerBirthday) as? TimeInterval).map(Date.init(timeIntervalSince1970:))
        // 首次启动默认把「今天」记为相遇日
        if let ts = defaults.object(forKey: Keys.adoptionDate) as? TimeInterval {
            adoptionDate = Date(timeIntervalSince1970: ts)
        } else {
            adoptionDate = Date()
        }
    }

    private func notify() {
        onChange?()
    }
}
