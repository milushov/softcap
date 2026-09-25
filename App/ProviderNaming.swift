import ProviderKit

/// What each service is called where a person is choosing between them.
///
/// `ProviderID.title` is the caption an account row carries — `Claude`, `Codex`
/// — and it is deliberately short, because it sits beside a plan name in a row
/// twenty points high. A menu offering somebody a sign-in is the other case:
/// there the full product name is what they will recognise from the thing they
/// already pay for.
///
/// It lives in the app rather than beside `title` in Core for the reason the
/// architecture rule gives: Core returns identifiers, and the one exception
/// already made there is as far as that goes. These are brand names and are not
/// translated, which is why they are a mapping and not a catalogue key.
///
/// Written once because two screens need it — the Accounts menu and the
/// Services list — and two copies of a product name are two things to forget to
/// rename the day a service is renamed.
extension ProviderID {
    var productName: String {
        switch self {
        case .claude:  "Claude Code"
        case .codex:   "OpenAI Codex"
        case .copilot: "GitHub Copilot"
        case .cursor:  "Cursor"
        case .gemini:  "Gemini"
        case .glm:     "GLM Coding Plan"
        case .kimi:    "Kimi Code"
        }
    }
}
