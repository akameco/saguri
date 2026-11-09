import Foundation
import Testing

@testable import Saguri

/// Swift Testing（Swift 6 から標準）。`@Test` を付けた関数がテストになり、`#expect` で確かめる。
/// Jest の `test()` と `expect()`、Rust の `#[test]` と `assert!` に当たる。
struct MatcherTests {
    @Test func 空のパターンはすべてに一致する() {
        #expect(Matcher("").match("anything") == Match(score: 0, positions: []))
    }

    @Test func 順番どおりに含まれていれば一致する() {
        #expect(Matcher("ghb").match("GitHub") != nil)
        #expect(Matcher("bhg").match("GitHub") == nil)
        #expect(Matcher("xyz").match("GitHub") == nil)
    }

    @Test func v1は後ろ向きの走査で範囲を短くする() throws {
        let m = try #require(Matcher("ab", options: Options(algorithm: .v1)).match("a_a_b"))
        #expect(m.positions == [2, 4])
    }

    @Test func smartcaseはパターンに大文字があるときだけ区別する() {
        #expect(Matcher("hub").match("GitHub") != nil)
        #expect(Matcher("Hub").match("GitHub") != nil)
        #expect(Matcher("HUB").match("GitHub") == nil)
        #expect(Matcher("HUB", options: Options(caseMode: .insensitive)).match("GitHub") != nil)
    }

    @Test func カタカナとひらがなを同一視する() {
        #expect(Matcher("ぎっと").match("ギットハブ") != nil)
        #expect(Matcher("ぎっと", options: Options(kanaInsensitive: false)).match("ギットハブ") == nil)
    }

    @Test func 単語の先頭での一致を高く採点する() throws {
        // "gd" は、語の途中の g と d（Bigdata）より、語の先頭の G と D（GitHub Desktop）を上にする
        let head = try #require(Matcher("gd").match("GitHub Desktop"))
        let middle = try #require(Matcher("gd").match("Bigdata"))
        #expect(head.score > middle.score)
    }

    @Test func 連続した一致はすき間のある一致より高い() throws {
        let tight = try #require(Matcher("term").match("terminal"))
        let loose = try #require(Matcher("term").match("the_exterior_main"))
        #expect(tight.score > loose.score)
    }

    @Test func camelCaseの境界にボーナスが付く() throws {
        let camel = try #require(Matcher("b").match("fooBar"))
        let plain = try #require(Matcher("b").match("foobar"))
        #expect(camel.score > plain.score)
    }

    @Test func 一致した位置を文字列の範囲に直せる() throws {
        let candidate = "日本語のPR"
        let m = try #require(Matcher("のp").match(candidate))
        #expect(m.positions == [3, 4])
        let picked = m.ranges(in: candidate).map { String(candidate[$0]) }
        #expect(picked == ["の", "P"])
    }

    /// v1 の弱点を記録しておく。v2 では [4, 5] / 62 になる（MatcherV2Tests の 最善の一致を選ぶ）
    @Test func v1は最善の一致を見逃すことがある() throws {
        let m = try #require(Matcher("ab", options: Options(algorithm: .v1)).match("a_b ab"))
        #expect(m.positions == [0, 2])
        #expect(m.score == 57)
    }

    /// 点数の内訳を手で計算した値と比べる。
    /// "foo bar" に "obr" → 後ろ向きの走査で o は 2 文字目（添字 2）に寄る。
    @Test func 点数が手計算と合う() throws {
        let m = try #require(Matcher("obr").match("foo bar"))
        #expect(m.positions == [2, 4, 6])
        // o: 16 + 0*2 = 16、gap -3、b: 16 + 10（空白のあと）= 26、gap -3、r: 16 = 16 → 52
        #expect(m.score == 52)
    }
}

/// v2（動的計画法）のテスト
struct MatcherV2Tests {
    @Test func 最善の一致を選ぶ() throws {
        // v1 は先頭の a と b（あいだに _）を選ぶが、v2 は後ろの "ab"（空白のあと・連続）を選ぶ
        let m = try #require(Matcher("ab").match("a_b ab"))
        #expect(m.positions == [4, 5])
        // a: 16 + 空白のあとの境界 10 × 2 = 36、b: 16 + 連続 max(0, 4, 10) = 26 → 62
        #expect(m.score == 62)
    }

    @Test func 先頭の文字のボーナスが大きい位置を選ぶ() throws {
        // "a_a_b": 先頭の a（境界 10 × 2）を使うほうが、_ のあとの a（8 × 2）より高い（fzf と同じ）
        let m = try #require(Matcher("ab").match("a_a_b"))
        #expect(m.positions == [0, 4])
        // 位置 [0, 4] を手で数えると 36 - 5 + 24 = 55 だが、fzf の v2 は 1 行目を
        // 「パターンの 1 文字目が現れるたびに、その位置から始め直した点」にするので、
        // 2 つ目の a（32）から数えた 32 - 3 + 24 = 53 になる。fzf と同じ並び順にするため、この癖も写している
        #expect(m.score == 53)
    }

    @Test func 一致しなければnil() {
        #expect(Matcher("xyz").match("GitHub") == nil)
        #expect(Matcher("ba").match("ab") == nil)
    }

    @Test func 一文字のパターンは境界の位置を選ぶ() throws {
        // "xax a": 空白のあとの a（境界）を選ぶ
        let m = try #require(Matcher("a").match("xax a"))
        #expect(m.positions == [4])
    }

    @Test func camelCaseの頭文字に合わせる() throws {
        // "gh" は GitHub の G と H（どちらも単語の先頭）に合う
        let m = try #require(Matcher("gh").match("GitHub Desktop"))
        #expect(m.positions == [0, 3])
    }

    @Test func 三文字以上でも連続と境界を選ぶ() throws {
        // a_b_c: どれも _ のあとの境界
        #expect(try #require(Matcher("abc").match("a_b_c")).positions == [0, 2, 4])
        // fooBar: f と B（camelCase の境界）
        #expect(try #require(Matcher("fb").match("fooBar")).positions == [0, 3])
        // "xabc abc": 後ろの、空白のあとで連続した abc
        #expect(try #require(Matcher("abc").match("xabc abc")).positions == [5, 6, 7])
    }

    @Test func 大文字のパターンは大文字だけに当たる() throws {
        // smart case: B が大文字なので、小文字の b には当たらない
        #expect(try #require(Matcher("aB").match("ab aB")).positions == [3, 4])
        #expect(Matcher("aB").match("ab ab") == nil)
    }

    @Test func 表が大きすぎるときはv1で答える() throws {
        // 6 万文字 × 2 行は 10 万マスを超えるので、v1 の走査と採点に戻る
        let long = String(repeating: "a", count: 60000) + "b"
        let m = try #require(Matcher("ab").match(long))
        #expect(m.positions == [59999, 60000])
    }

    /// 乱数で作った文字列で、v2 の性質を確かめる（プロパティテスト）。
    /// - v2 の点は、ほとんどの場合 v1 以上。ただし必ずではない。連続のボーナスは「どこから連続しているか」
    ///   で決まり、表の 1 マスに 1 つの経路しか覚えないので、fzf の v2 も最適を保証しない（下の割合で確かめる）
    /// - 位置は増えていき、そこの文字はパターンの文字と同じ
    @Test func v2はv1以上の点で正しい位置を返す() {
        // 乱数の種を固定して、毎回同じ文字列で試す（失敗したときに再現できるように）
        var rng = SplitMix64(seed: 42)
        let alphabet = Array("abAB_ /1")
        let v1 = Options(algorithm: .v1)
        var worse = 0
        var total = 0
        for _ in 0..<3000 {
            let text = String((0..<Int.random(in: 1...16, using: &rng)).map { _ in alphabet.randomElement(using: &rng)! })
            let pattern = String((0..<Int.random(in: 1...4, using: &rng)).map { _ in "abAB".randomElement(using: &rng)! })
            let a = Matcher(pattern, options: v1).match(text)
            let b = Matcher(pattern).match(text)
            // 一致するかどうかは、どちらも同じ
            #expect((a == nil) == (b == nil), "\(pattern) / \(text)")
            guard let a, let b else { continue }
            total += 1
            if b.score < a.score { worse += 1 }
            #expect(b.positions == b.positions.sorted() && Set(b.positions).count == b.positions.count)
            let chars = Array(text)
            let smart = pattern.contains(where: \.isUppercase)
            for (p, i) in zip(pattern, b.positions) {
                let t = chars[i]
                #expect(smart ? t == p : t.lowercased() == p.lowercased(), "\(pattern) / \(text)")
            }
        }
        // v1 を下回るのは、ごくまれ
        #expect(Double(worse) / Double(total) < 0.02, "v1 を下回った: \(worse) / \(total)")
    }
}

/// 種を決められる乱数（標準の SystemRandomNumberGenerator は種を決められない）。
/// RandomNumberGenerator プロトコルに従えば、randomElement(using:) などに渡せる
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    // &+ と &* は「あふれても落ちない」足し算と掛け算（Rust の wrapping_add に当たる）
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// fzf が入っていれば、fzf と同じ並び順になるかを確かめる。
/// fzf は点数を出さないので、`fzf -f <パターン> --tiebreak=index` の出力順（点数の高い順、同点は入力の順）と比べる。
struct FzfCompareTests {
    static let fzf: String? = ["/opt/homebrew/bin/fzf", "/usr/local/bin/fzf", "/usr/bin/fzf"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// `.enabled(if:)` で、条件を満たさないときはテストを飛ばす（fzf が無い CI でも落ちない）
    @Test(.enabled(if: fzf != nil)) func fzfと同じ並び順になる() throws {
        var rng = SplitMix64(seed: 2026)
        // パターンに記号（- / _ .）も入れる。^ ' ! $ と空白は fzf の検索構文になるので入れない
        let textAlphabet = Array("abAB_-/ .1")
        let patternAlphabet = Array("abAB_-/.")
        var mismatches: [String] = []
        for _ in 0..<150 {
            let candidates = (0..<40).map { _ in
                String((0..<Int.random(in: 1...14, using: &rng)).map { _ in textAlphabet.randomElement(using: &rng)! })
            }
            let pattern = String((0..<Int.random(in: 1...4, using: &rng)).map { _ in patternAlphabet.randomElement(using: &rng)! })
            let matcher = Matcher(pattern)
            // 自分の並び: 点数の高い順、同点は入力の順
            let mine = candidates.enumerated()
                .compactMap { i, c in matcher.match(c).map { (i, $0.score) } }
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
                .map(\.0)
            let theirs = try runFzf(pattern: pattern, candidates: candidates)
            if mine != theirs { mismatches.append("\(pattern): \(mine) / fzf \(theirs)") }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(3))")
    }

    /// fzf に候補を渡し、出力された行が何番目の候補かを返す（重複しないよう、行の頭に番号を付けて渡す）
    func runFzf(pattern: String, candidates: [String]) throws -> [Int] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Self.fzf!)
        // --nth=2.. と --delimiter で、番号の列を検索の対象から外す
        p.arguments = ["-f", pattern, "--tiebreak=index", "--algo=v2", "--delimiter=\t", "--nth=2.."]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        try p.run()
        let lines = candidates.enumerated().map { "\($0)\t\($1)" }.joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(lines.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { Int($0.split(separator: "\t").first ?? "") }
    }
}

struct PreparedTests {
    static let candidates = [
        "GitHub Desktop", "github.com/akameco/saguri", "a_b ab", "fooBar_baz", "カタカナ ひらがな", "Ｆｕｌｌ ｗｉｄｔｈ",
        "Safari Technology Preview", "😀 grinning face", "Straße", "src/algo/algo.go", "", "x",
        String(repeating: "ab", count: 600),
    ]
    static let patterns = ["", "g", "ghd", "GH", "ab", "fb", "かた", "カナ", "sfr", "STP", "😀", "ß", "algo", "xyz"]

    @Test(arguments: [Options(), Options(caseMode: .sensitive), Options(caseMode: .insensitive),
                      Options(kanaInsensitive: false), Options(algorithm: .v1)])
    func 前もって分けても文字列で採点したのと同じ(options: Options) {
        let prepared = Self.candidates.map { Prepared($0) }
        for pattern in Self.patterns {
            let m = Matcher(pattern, options: options)
            for (text, p) in zip(Self.candidates, prepared) {
                #expect(m.match(p) == m.match(text), "\(pattern) / \(text)")
            }
        }
    }

    @Test func かなの扱いが違えば文字列から採点し直す() {
        let p = Prepared("カタカナ", kanaInsensitive: false)
        #expect(Matcher("かた").match(p) != nil)
        #expect(Matcher("かた", options: Options(kanaInsensitive: false)).match(p) == nil)
    }
}
