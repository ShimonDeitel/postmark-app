import Foundation
import SwiftData

/// One scanned/saved stamp in the user's album.
@Model
final class StampItem {
    var country: String
    var issue: String
    var year: Int
    var denomination: String
    var variety: String
    var valueLowUsed: Double
    var valueHighUsed: Double
    var valueLowMint: Double
    var valueHighMint: Double
    /// Model confidence in the identification, 0...1.
    var confidence: Double
    /// The eBay-friendly search term produced by the vision model.
    var searchTerm: String
    var notes: String
    /// Album page / grouping, free text for now.
    var albumPage: String
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date
    /// Flag for potential high-value varieties worth professional
    /// expertizing. Auto-set on save (see convenience init), user-editable.
    var worthExpertizing: Bool

    init(
        country: String,
        issue: String = "",
        year: Int = 0,
        denomination: String = "",
        variety: String = "",
        valueLowUsed: Double = 0,
        valueHighUsed: Double = 0,
        valueLowMint: Double = 0,
        valueHighMint: Double = 0,
        confidence: Double = 0,
        searchTerm: String = "",
        notes: String = "",
        albumPage: String = "",
        photoData: Data? = nil,
        createdAt: Date = .now,
        worthExpertizing: Bool = false
    ) {
        self.country = country
        self.issue = issue
        self.year = year
        self.denomination = denomination
        self.variety = variety
        self.valueLowUsed = valueLowUsed
        self.valueHighUsed = valueHighUsed
        self.valueLowMint = valueLowMint
        self.valueHighMint = valueHighMint
        self.confidence = confidence
        self.searchTerm = searchTerm
        self.notes = notes
        self.albumPage = albumPage
        self.photoData = photoData
        self.createdAt = createdAt
        self.worthExpertizing = worthExpertizing
    }

    convenience init(result: StampResult, photoData: Data?) {
        self.init(
            country: result.country,
            issue: result.issue,
            year: result.year,
            denomination: result.denomination,
            variety: result.variety,
            valueLowUsed: result.valueLowUsed,
            valueHighUsed: result.valueHighUsed,
            valueLowMint: result.valueLowMint,
            valueHighMint: result.valueHighMint,
            confidence: result.confidence,
            searchTerm: result.searchTerm,
            photoData: photoData,
            worthExpertizing: max(result.valueHighUsed, result.valueHighMint) >= 100
                && result.confidence >= 0.5
        )
    }

    /// Best display name for lists: "1918 USA 24c Inverted Jenny"-style line.
    var displayName: String {
        var parts: [String] = []
        if year > 0 { parts.append(String(year)) }
        if !country.isEmpty { parts.append(country) }
        if !denomination.isEmpty { parts.append(denomination) }
        if !issue.isEmpty { parts.append(issue) }
        return parts.isEmpty ? "Unidentified stamp" : parts.joined(separator: " ")
    }

    /// One-tap link to real eBay SOLD listings for the identified term.
    var ebaySoldListingsURL: URL? {
        var components = URLComponents(string: "https://www.ebay.com/sch/i.html")
        components?.queryItems = [
            URLQueryItem(name: "_nkw", value: searchTerm.isEmpty ? displayName : searchTerm),
            URLQueryItem(name: "LH_Sold", value: "1"),
            URLQueryItem(name: "LH_Complete", value: "1"),
        ]
        return components?.url
    }
}
