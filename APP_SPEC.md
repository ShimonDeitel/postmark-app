# Postmark - Stamp Identifier & Value

One-line: photograph any postage stamp, learn what it is and what it sells for, and mount it in a digital album.

## Why (queue slot 4)
CoinSnap playbook applied to a niche with near-zero quality competition: best incumbent (Colnect Stamp Identifier) rated 3.46 with 440k lifetime downloads. Smallest TAM of the queue; realistic ceiling $200-500k/yr. Cheapest to build (Attic's architecture with a different brain prompt and skin).

## Core loop
1. **Scan**: camera photo of stamp(s) -> vision LLM identifies country, issue, year, denomination, color variety. Same OpenRouter-compatible client as Attic (free-tier model in dev; funded proxy decision at submission).
2. **Value**: estimated sold range (mint/used) + one-tap eBay sold-listings link + "worth expertizing" flag for potential high-value varieties.
3. **Album**: digital stock book with country/era pages, want-list, collection total.

## Monetization
- Free: 3 identifications, full album browsing. Pro: unlimited + variety detection + album export.
- postmark_pro_monthly $4.99/mo, postmark_pro_yearly $29.99/yr. Paywall after first result.

## ASO
- Name: "Postmark - Stamp Identifier". Subtitle: "What stamp is it? What's it worth?"
- Keywords: stamp identifier, stamp value, philately, stamp collection, postage stamp.

## Design direction (bespoke - not Attic's attic, not parchment-first)
- Feel: a philatelist's desk lamp pool of light on deep green baize. Racing-green base, cream stamp frames, red cancellation-ink accent. Precise, calm, archival.
- Signature motion: cards have real perforated edges (die-cut shape); saving a find fires a rubber "postmark" cancellation that rolls across the corner with a thunk haptic; album pages turn with paper physics; a loupe hover magnifies grid thumbnails.

## Technical
- Native SwiftUI, iOS 26, XcodeGen, com.deitel.postmark, W7Q885Q59C, conventions from Attic.
- Reuse Attic's service-layer architecture (camera wrapper, OpenRouter client with stamp-specific system prompt + JSON schema: country, issue, year, denomination, variety, value_low_used, value_high_used, value_low_mint, value_high_mint, confidence, search_term), SwiftData album models.
- Camera permission in context; keyboard tap-outside dismiss; StoreKit 2 + .storekit config.

## Status
- 2026-07-06: spec written. Build starts after Clicker.
