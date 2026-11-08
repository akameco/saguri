/// 採点の定数。fzf（src/algo/algo.go）と同じ値にしている。
///
/// 考え方: 1 文字一致するごとに `match` 点を足し、一致の間にすき間があれば引く。
/// 単語の先頭など「人が狙って打ちそうな位置」で一致したら、ボーナスを足す。
///
/// Swift では名前空間だけが欲しいとき、ケースのない `enum` を使う
/// （インスタンスを作れないので、誤って `Score()` と書けない）。
enum Score {
    static let match = 16
    static let gapStart = -3
    static let gapExtension = -1

    /// 単語の境界（記号のあと）で一致した
    static let boundary = match / 2  // 8
    /// 空白のあと。もっとも強い境界
    static let boundaryWhite = boundary + 2  // 10
    /// / , : ; | のあと
    static let boundaryDelimiter = boundary + 1  // 9
    /// 記号そのものに一致した
    static let nonWord = match / 2  // 8
    /// camelCase の大文字や、数字の始まり（fooBar の B、foo123 の 1）
    static let camel123 = boundary + gapExtension  // 7
    /// 連続して一致している間は、最低でもこれだけ足す
    static let consecutive = -(gapStart + gapExtension)  // 4
    /// パターンの 1 文字目のボーナスは 2 倍にする
    static let firstCharMultiplier = 2

    /// 直前の文字の種類 `prev` と、一致した文字の種類 `curr` から、ボーナスを決める。
    static func bonus(prev: CharClass, curr: CharClass) -> Int {
        // 空白以外（記号や区切りも含む）が境界のあとに来たら、境界のボーナス（fzf の bonusFor の class >= charNonWord）。
        // パターンに - や / を入れたときも、空白のあとの記号を単語の先頭とみなす
        if curr >= .nonWord {
            switch prev {
            case .white: return boundaryWhite
            case .delimiter: return boundaryDelimiter
            case .nonWord: return boundary
            default: break
            }
        }
        if (prev == .lower && curr == .upper) || (prev != .number && curr == .number) {
            return camel123
        }
        switch curr {
        case .nonWord, .delimiter: return nonWord
        case .white: return boundaryWhite
        default: return 0
        }
    }
}
