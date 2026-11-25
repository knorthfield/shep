import Foundation

/// The filter of the sidebar: the text that the user types to find a space or a machine.
enum SidebarFilter {
    /// A space shows when the filter is empty, or when its name or the name of its machine contains the filter.
    static func shows(spaceName: String, machineName: String, filter: String) -> Bool {
        filter.isEmpty || matches(spaceName, filter: filter) || matches(machineName, filter: filter)
    }

    static func matches(_ name: String, filter: String) -> Bool {
        name.localizedCaseInsensitiveContains(filter)
    }
}
