import SwiftUI

/// 设置窗口内容
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 16) {
            GroupBox("番茄钟节奏") {
                VStack(spacing: 10) {
                    Stepper(
                        "专注时长：\(Int(model.focusMinutes)) 分钟",
                        value: $model.focusMinutes,
                        in: 5...120,
                        step: 5
                    )
                    Stepper(
                        "短休息：\(Int(model.shortRestMinutes)) 分钟",
                        value: $model.shortRestMinutes,
                        in: 1...30,
                        step: 1
                    )
                    Stepper(
                        "长休息：\(Int(model.longRestMinutes)) 分钟",
                        value: $model.longRestMinutes,
                        in: 5...60,
                        step: 5
                    )
                    Stepper(
                        "每 \(Int(model.cycleCount)) 轮专注一次长休",
                        value: $model.cycleCount,
                        in: 2...8,
                        step: 1
                    )
                }
                .padding(6)
            }

            GroupBox("系统") {
                VStack(spacing: 10) {
                    Picker("桌面宠物", selection: $model.selectedPet) {
                        Text("猫咪 🐱").tag("cat")
                        Text("狗狗 🐶").tag("dog")
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("宠物大小：\(Int(model.petSizePercent))%")
                        Slider(
                            value: $model.petSizePercent,
                            in: 50...150,
                            step: 5
                        )
                    }
                    Toggle("登录时自动启动", isOn: $model.launchAtLogin)
                    Toggle("全局快捷键 ⇧⌘P（开始 / 暂停 / 继续）", isOn: $model.hotkeyEnabled)
                    Toggle("宠物音效（叫声 / 进食 / 呼噜）", isOn: $model.soundEnabled)
                }
                .padding(6)
            }

            GroupBox("🐾 宠物资料（\(model.selectedPet == "dog" ? "狗狗" : "猫咪")）") {
                VStack(spacing: 10) {
                    HStack {
                        Text("名字")
                        Spacer()
                        TextField("给它起个名字", text: nameBinding)
                            .frame(width: 180)
                            .multilineTextAlignment(.trailing)
                    }
                    optionalDatePicker("生日", date: birthdayBinding) { date in
                        if let date {
                            let z = Zodiac.of(date)
                            Text("星座：\(z.emoji) \(z.name)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    optionalDatePicker("相遇纪念日", date: $model.adoptionDate) { date in
                        if let date {
                            Text("相伴 \(companionDays(from: date)) 天")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("🙋 主人资料") {
                VStack(spacing: 10) {
                    optionalDatePicker("你的生日", date: $model.ownerBirthday) { date in
                        if let date {
                            let z = Zodiac.of(date)
                            Text("星座：\(z.emoji) \(z.name)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let petBD = model.currentPetBirthday, let ownerBD = model.ownerBirthday {
                        let m = Zodiac.match(Zodiac.of(petBD), Zodiac.of(ownerBD))
                        HStack {
                            Text("💞 星座匹配度")
                            Spacer()
                            Text("\(m.score)% · \(m.comment)")
                                .foregroundStyle(.pink)
                        }
                    } else {
                        Text("设置双方生日后，看看你们的星座有多配 💕")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }

            Text("所有设置即时生效")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 400)
    }

    /// 当前宠物名字的绑定（随「桌面宠物」选择切换）
    private var nameBinding: Binding<String> {
        Binding(
            get: { self.model.selectedPet == "dog" ? self.model.dogName : self.model.catName },
            set: { newValue in
                if self.model.selectedPet == "dog" {
                    self.model.dogName = newValue
                } else {
                    self.model.catName = newValue
                }
            }
        )
    }

    private var birthdayBinding: Binding<Date?> {
        Binding(
            get: { self.model.selectedPet == "dog" ? self.model.dogBirthday : self.model.catBirthday },
            set: { newValue in
                if self.model.selectedPet == "dog" {
                    self.model.dogBirthday = newValue
                } else {
                    self.model.catBirthday = newValue
                }
            }
        )
    }

    private func companionDays(from date: Date) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 1)
    }

    /// 可选日期选择器：开关 + 日期；附加内容显示在右侧（星座/相伴天数）
    private func optionalDatePicker(
        _ label: String,
        date: Binding<Date?>,
        @ViewBuilder trailing: (Date?) -> some View
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Toggle(label, isOn: Binding(
                    get: { date.wrappedValue != nil },
                    set: { date.wrappedValue = $0 ? Date() : nil }
                ))
                Spacer()
                trailing(date.wrappedValue)
            }
            if date.wrappedValue != nil {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { date.wrappedValue ?? Date() },
                        set: { date.wrappedValue = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.stepperField)
                .labelsHidden()
            }
        }
    }
}
