import SwiftUI
import Preferences
import StatusUI

/// The control that sets the day an account's subscription is paid.
///
/// No provider says when it bills, so the person enters it; the statistics strips
/// then draw a dot on that day. Three pickers, the later ones shown only when
/// they mean something: a day (or "Not set"), whether it repeats monthly or
/// yearly, and for yearly the month.
struct BillingControl: View {
    @ObservedObject var model: PreferencesModel
    let accountID: String

    @ObservedObject private var loc = Localization.shared

    private var schedule: BillingSchedule? { model.value.billing[accountID] }

    var body: some View {
        HStack(spacing: 6) {
            Text(loc("Payment day"))
                .font(.system(size: 11)).foregroundStyle(.secondary)

            Picker(loc("Day"), selection: day) {
                Text(loc("Not set")).tag(0)
                ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .fixedSize()

            if let schedule {
                Picker(loc("Payment day"), selection: yearly) {
                    Text(loc("Monthly")).tag(false)
                    Text(loc("Yearly")).tag(true)
                }
                .labelsHidden()
                .fixedSize()

                if case .yearly = schedule.period {
                    Picker(loc("Month"), selection: month) {
                        ForEach(Array(monthNames.enumerated()), id: \.offset) { index, name in
                            Text(name).tag(index + 1)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .controlSize(.small)
    }

    /// 0 means none, which is how a `Picker` spells "no selection".
    private var day: Binding<Int> {
        Binding(
            get: { schedule?.dayOfMonth ?? 0 },
            set: { chosen in
                model.update { prefs in
                    guard chosen > 0 else { prefs.billing[accountID] = nil; return }
                    let period = prefs.billing[accountID]?.period ?? .monthly
                    prefs.billing[accountID] = BillingSchedule(dayOfMonth: chosen, period: period)
                }
            }
        )
    }

    private var yearly: Binding<Bool> {
        Binding(
            get: { if case .yearly = schedule?.period { true } else { false } },
            set: { isYearly in
                model.update { prefs in
                    guard let current = prefs.billing[accountID] else { return }
                    // A yearly plan needs a month; this month is a better first
                    // guess than January, and a one-click fix if it is wrong.
                    let month = Calendar.current.component(.month, from: Date())
                    prefs.billing[accountID] = BillingSchedule(
                        dayOfMonth: current.dayOfMonth,
                        period: isYearly ? .yearly(month: month) : .monthly)
                }
            }
        )
    }

    private var month: Binding<Int> {
        Binding(
            get: { if case .yearly(let m) = schedule?.period { m } else { 1 } },
            set: { chosen in
                model.update { prefs in
                    guard let current = prefs.billing[accountID] else { return }
                    prefs.billing[accountID] = BillingSchedule(
                        dayOfMonth: current.dayOfMonth, period: .yearly(month: chosen))
                }
            }
        )
    }

    private var monthNames: [String] {
        let formatter = DateFormatter()
        formatter.locale = loc.activeLocale
        return formatter.standaloneMonthSymbols
    }
}
