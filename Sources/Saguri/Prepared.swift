/// 前もって文字に分け、正規化しておいた候補。`Matcher.match(_:)` に渡す。
///
/// `match(_ candidate: String)` は呼ぶたびに、候補を文字（`Character`）に分け、
/// 大文字小文字とかなをそろえ、文字の種類を調べる。ランチャーは打つたびに同じ数千の候補を採点するので、
/// この下ごしらえを候補ごとに 1 回で済ませると、採点が数倍速くなる。
///
/// ```swift
/// let prepared = titles.map { Prepared($0) }   // 候補が変わったときだけ作る
/// let matcher = Matcher("ghd")
/// let hits = prepared.compactMap { matcher.match($0) }
/// ```
///
/// 文字の配列を 2 本持つので、元の文字列のおよそ 30 倍のメモリを使う（1 文字あたり 33 バイトほど）。
public struct Prepared: Sendable {
    /// 元の文字列
    public let text: String
    /// かなの扱い。`Matcher` の `Options.kanaInsensitive` と違えば、`text` から採点し直す
    public let kanaInsensitive: Bool
    /// 大文字小文字を区別するときの文字（かなだけをそろえたもの）
    let exact: [Character]
    /// 区別しないときの文字（小文字にしたもの）
    let folded: [Character]
    /// 各文字の種類（正規化前の文字で決める）
    let classes: [CharClass]

    public init(_ text: String, kanaInsensitive: Bool = true) {
        self.text = text
        self.kanaInsensitive = kanaInsensitive
        let original = Array(text)
        exact = original.map { normalize($0, caseSensitive: true, kanaInsensitive: kanaInsensitive) }
        folded = exact.map { normalize($0, caseSensitive: false, kanaInsensitive: false) }
        classes = original.map(CharClass.init)
    }
}
