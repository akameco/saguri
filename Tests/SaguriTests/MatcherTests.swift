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

    @Test func 後ろ向きの走査で範囲を短くする() throws {
        let m = try #require(Matcher("ab").match("a_a_b"))
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

    /// v1 の弱点を記録しておく。v2 にしたら positions が [4, 5]、score が 62 になるはず。
    @Test func v1は最善の一致を見逃すことがある() throws {
        let m = try #require(Matcher("ab").match("a_b ab"))
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
