/// あいまい検索の結果。
///
/// `struct` は値型（代入でコピーされる）。TypeScript のオブジェクトと違い、
/// 渡した先で書き換えられても元は変わらない。Rust の `#[derive(Clone)]` な struct に近い。
/// `Sendable` は「スレッドをまたいで渡してよい」という印で、Swift 6 の並行性チェックが見る。
public struct Match: Sendable, Equatable {
    /// 点数。大きいほどよく一致している
    public let score: Int
    /// 一致した文字の位置（候補の `Character` で数えた 0 始まりの添字）。強調表示に使う
    public let positions: [Int]

    /// 一致した位置を、候補の文字列の範囲（`Range<String.Index>`）に直す。
    ///
    /// Swift の String は整数で添字を引けない（UTF-8 で可変長なので O(1) で引けないため）。
    /// 画面で強調するときは、この範囲を `NSRange(range, in: candidate)` で AppKit の形に変える。
    public func ranges(in candidate: String) -> [Range<String.Index>] {
        let wanted = Set(positions)
        // indices は String.Index の列。zip で 0, 1, 2... と組にして、一致した位置だけ取り出す
        return zip(0..., candidate.indices)
            .filter { wanted.contains($0.0) }
            .map { _, index in index..<candidate.index(after: index) }
    }
}

/// 検索の設定。
public struct Options: Sendable {
    /// 大文字小文字の扱い
    public enum CaseMode: Sendable {
        /// パターンに大文字があるときだけ区別する（fzf の既定、smart case）
        case smart
        case sensitive
        case insensitive
    }

    /// 採点のやり方
    public enum Algorithm: Sendable {
        /// 前から見つけた一致を採点する。速いが、最善の一致を見逃すことがある（fzf の --algo=v1）
        case v1
        /// 動的計画法で最善の一致を探す（fzf の既定、--algo=v2）
        case v2
    }

    public var caseMode: CaseMode
    /// true ならカタカナとひらがなを同じ文字とみなす
    public var kanaInsensitive: Bool
    public var algorithm: Algorithm

    /// 引数の既定値を書いておくと、`Options()` とも `Options(kanaInsensitive: false)` とも呼べる。
    public init(caseMode: CaseMode = .smart, kanaInsensitive: Bool = true, algorithm: Algorithm = .v2) {
        self.caseMode = caseMode
        self.kanaInsensitive = kanaInsensitive
        self.algorithm = algorithm
    }
}

/// 1 つのパターンで、たくさんの候補を採点する。
///
/// ランチャーでは「1 回の入力 × 数千の候補」なので、パターンの前処理は作るときに 1 回だけ行う。
///
/// ```swift
/// let matcher = Matcher("gh iss")
/// let results = candidates.compactMap { c in matcher.match(c).map { (c, $0) } }
///     .sorted { $0.1.score > $1.1.score }
/// ```
public struct Matcher: Sendable {
    public let pattern: String
    public let options: Options

    // MatcherV2.swift（別のファイルの extension）から読むので private にしない。
    // Swift の private はファイルの中だけで見える（TypeScript の private はクラスの中だけ）
    let chars: [Character]
    let caseSensitive: Bool

    public init(_ pattern: String, options: Options = Options()) {
        self.pattern = pattern
        self.options = options
        switch options.caseMode {
        case .sensitive: caseSensitive = true
        case .insensitive: caseSensitive = false
        // contains(where:) は配列の some() に当たる。クロージャの $0 は 1 番目の引数
        case .smart: caseSensitive = pattern.contains(where: \.isUppercase)
        }
        // `\.isUppercase` はキーパス。`{ $0.isUppercase }` と同じ意味の短い書き方
        let cs = caseSensitive
        let kana = options.kanaInsensitive
        chars = pattern.map { normalize($0, caseSensitive: cs, kanaInsensitive: kana) }
    }

    /// 候補を採点する。一致しなければ nil。
    ///
    /// 戻り値の `Match?` は Optional。TypeScript の `Match | undefined`、Rust の `Option<Match>` に当たる。
    public func match(_ candidate: String) -> Match? {
        if chars.isEmpty { return Match(score: 0, positions: []) }

        let original = Array(candidate)
        let text = original.map {
            normalize($0, caseSensitive: caseSensitive, kanaInsensitive: options.kanaInsensitive)
        }
        // まず v1 の走査（O(n)）で、一致するかだけを安く確かめる。一致しない候補がほとんどなので、ここで多くを落とせる
        guard let (start, end) = findRange(in: text) else { return nil }
        if options.algorithm == .v2, let best = matchV2(text: text, original: original) {
            return best
        }
        // v1 か、v2 の表が大きすぎるとき
        return score(text: text, original: original, start: start, end: end)
    }

    /// fzf の FuzzyMatchV1 の前半。一致する範囲 `start..<end` を探す。
    ///
    /// 1. 前から順に、パターンの文字を左から 1 つずつ探す。最後の文字が見つかった所が終わり
    /// 2. そこから後ろ向きに、パターンを右から探し直す。これで始まりをできるだけ右に寄せ、範囲を短くする
    ///
    /// 例: パターン "ab"、候補 "a_a_b" → 前向きで 0...4、後ろ向きで 2...4 に縮む
    ///
    /// 計算量は O(候補の長さ)。ただし「最もよい一致」を探すわけではない（それは v2 の仕事）。
    private func findRange(in text: [Character]) -> (Int, Int)? {
        // `guard` は条件を満たさないとき早く抜けるための構文。TypeScript の early return と同じ
        guard text.count >= chars.count else { return nil }

        var pidx = 0
        var end = -1
        for (i, c) in text.enumerated() where c == chars[pidx] {
            pidx += 1
            if pidx == chars.count {
                end = i + 1
                break
            }
        }
        guard end >= 0 else { return nil }

        pidx = chars.count - 1
        var start = end - 1
        // stride(from:through:by:) は「後ろ向きの for」。for (let i = end-1; i >= 0; i--) に当たる
        for i in stride(from: end - 1, through: 0, by: -1) where text[i] == chars[pidx] {
            if pidx == 0 {
                start = i
                break
            }
            pidx -= 1
        }
        return (start, end)
    }

    /// fzf の calculateScore。範囲の中を左から見て、一致・すき間・ボーナスを足し合わせる。
    ///
    /// 種類（CharClass）は正規化前の `original` で見る。小文字にすると camelCase の境界が消えるため。
    private func score(text: [Character], original: [Character], start: Int, end: Int) -> Match {
        var pidx = 0
        var total = 0
        var inGap = false
        var consecutive = 0
        var firstBonus = 0
        var positions: [Int] = []
        positions.reserveCapacity(chars.count)

        var prevClass: CharClass = start > 0 ? CharClass(original[start - 1]) : .white

        for i in start..<end {
            let currClass = CharClass(original[i])
            if pidx < chars.count, text[i] == chars[pidx] {
                positions.append(i)
                total += Score.match
                var bonus = Score.bonus(prev: prevClass, curr: currClass)
                if consecutive == 0 {
                    firstBonus = bonus
                } else {
                    // 連続した一致の途中では、塊の先頭で得たボーナスを引き継ぐ。
                    // 例: "fooBar" に "bar" → B の camel ボーナスを a, r も受け取る
                    if bonus >= Score.boundary, bonus > firstBonus { firstBonus = bonus }
                    bonus = max(bonus, firstBonus, Score.consecutive)
                }
                total += pidx == 0 ? bonus * Score.firstCharMultiplier : bonus
                inGap = false
                consecutive += 1
                pidx += 1
            } else {
                total += inGap ? Score.gapExtension : Score.gapStart
                inGap = true
                consecutive = 0
                firstBonus = 0
            }
            prevClass = currClass
        }
        return Match(score: total, positions: positions)
    }
}
