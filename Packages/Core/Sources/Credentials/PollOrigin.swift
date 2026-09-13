/// Who set a poll going.
///
/// It decides one thing: whether the keychain may put its access dialog on
/// screen while the poll runs. Reading the item Claude Code owns is the only
/// read that can raise one, and `CredentialStore` opens that item only while
/// something still depends on it — or while the person is explicitly granting
/// the read, which is what `allowingAccess` is.
///
/// Written as an argument rather than sibling methods because the two methods
/// were called `refresh` and `refreshNow`, and the menu's Refresh picked the
/// wrong one: the same command as the window's button, quietly unable to do
/// what the button does. A name one letter apart is not a choice anybody
/// makes on purpose.
public enum PollOrigin: Sendable, Hashable {
    /// The five-minute timer, a wake from sleep, a settings change: nobody is
    /// watching, so nothing may block on a dialog.
    case timer

    /// A person pressed Refresh — the popover's button, the menu's command or
    /// the hot key. They asked for fresh numbers, and fresh numbers are not
    /// consent to a password dialog: this case once carried that consent, and
    /// with every account signed in through the browser, a machine watched
    /// each press of Refresh demand the login keychain password for an item
    /// nothing needed any more.
    case person

    /// A person pressed "Allow access…", the button whose whole purpose is
    /// the dialog: they are granting the read and watching for it.
    case allowingAccess

    /// The one decision. Only the explicit grant may ask — a timer's poll
    /// would block on an answer that never comes, and a person's Refresh
    /// means the numbers, not the item.
    public var mayRaiseTheKeychainDialog: Bool { self == .allowingAccess }
}
