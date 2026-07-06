import Foundation

/// DTO decoded from the vision model's structured JSON response.
/// Wire format uses snake_case for the value keys (see PostmarkAPI system
/// prompt).
struct StampResult: Codable, Equatable {
    var country: String
    var issue: String
    var year: Int
    var denomination: String
    var variety: String
    var valueLowUsed: Double
    var valueHighUsed: Double
    var valueLowMint: Double
    var valueHighMint: Double
    /// 0...1
    var confidence: Double
    var searchTerm: String

    enum CodingKeys: String, CodingKey {
        case country
        case issue
        case year
        case denomination
        case variety
        case valueLowUsed = "value_low_used"
        case valueHighUsed = "value_high_used"
        case valueLowMint = "value_low_mint"
        case valueHighMint = "value_high_mint"
        case confidence
        case searchTerm = "search_term"
    }
}
