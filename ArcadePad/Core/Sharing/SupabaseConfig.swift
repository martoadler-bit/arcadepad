import Foundation

/// Supabase project settings for kit sharing. The anon key is meant to be embedded in
/// client apps (it's not a secret — access is controlled by Storage/RLS policies on the
/// `share` bucket), so it's fine as a plain constant rather than a bundled plist.
enum SupabaseConfig {
    static let projectURL = "https://beswmaogyjtbymgwgyft.supabase.co"
    static let anonKey = "sb_publishable_2gTWVmmQdRtFdzaC0qZCow_LIohEg9q"

    static var isConfigured: Bool {
        !projectURL.hasPrefix("REPLACE_") && !anonKey.hasPrefix("REPLACE_")
    }
}
