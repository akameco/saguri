/// 1 文字の「種類」。境界（単語の先頭など）を判定するのに使う。
///
/// Swift の `enum` は TypeScript の文字列リテラルの union や Rust の enum に近い。
/// `Int` を raw value に持たせ、`Comparable` にすると `<` で比べられる。
/// 並び順に意味を持たせていて、`nonWord` より後ろは「単語を作る文字」になる
/// （fzf の charClass と同じ考え方）。
enum CharClass: Int, Comparable {
    case white       // 空白
    case nonWord     // 記号（区切り以外）
    case delimiter   // パスなどの区切り: / , : ; |
    case lower       // 小文字の英字
    case upper       // 大文字の英字
    case letter      // 英字以外の文字（日本語など）
    case number      // 数字

    static func < (lhs: CharClass, rhs: CharClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// 単語を作る文字か。
    var isWord: Bool { self > .delimiter }

    /// `Character` は Swift の「書記素クラスタ」（見た目の 1 文字）。
    /// 絵文字や結合文字も 1 つの `Character` になる。種類は先頭の Unicode スカラーで決める。
    init(_ c: Character) {
        if c.isWhitespace {
            self = .white
        } else if "/,:;|".contains(c) {
            self = .delimiter
        } else if c.isNumber {
            self = .number
        } else if c.isLowercase {
            self = .lower
        } else if c.isUppercase {
            self = .upper
        } else if c.isLetter {
            self = .letter
        } else {
            self = .nonWord
        }
    }
}

/// 比べる前に文字をそろえる。
///
/// - 大文字小文字を区別しないなら小文字にする
/// - かなを区別しないなら、カタカナをひらがなにする
@inline(__always)
func normalize(_ c: Character, caseSensitive: Bool, kanaInsensitive: Bool) -> Character {
    var c = c
    if !caseSensitive, c.isUppercase {
        // lowercased() は String を返す（ドイツ語の ß のように 1 文字が複数になることがあるため）。
        // 1 文字に収まったときだけ置き換える。
        let lower = c.lowercased()
        if lower.count == 1 { c = Character(lower) }
    }
    if kanaInsensitive, c.unicodeScalars.count == 1, let scalar = c.unicodeScalars.first,
       (0x30A1...0x30F6).contains(scalar.value),
       let hira = Unicode.Scalar(scalar.value - 0x60)
    {
        // カタカナ「ァ」(U+30A1)〜「ヶ」(U+30F6) は、ひらがなより 0x60 だけ後ろにある。
        c = Character(hira)
    }
    return c
}
