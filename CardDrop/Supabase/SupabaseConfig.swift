import Foundation

enum SupabaseConfig {
    static let projectURL = URL(string: Secrets.supabaseURL)!
    static let anonKey = Secrets.supabaseAnonKey
}
