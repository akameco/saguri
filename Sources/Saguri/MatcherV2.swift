/// fzf の FuzzyMatchV2（src/algo/algo.go）。動的計画法で「もっとも点数の高い一致」を探す。
///
/// v1 は「前から見つけた最初の一致」を採点するだけなので、"a_b ab" に "ab" だと
/// 先頭の a と b（あいだに _）を選んでしまう。v2 はすべての並べ方を表で比べ、
/// 後ろの "ab"（連続していて、空白のあとの単語の先頭）を選ぶ。
///
/// 表は「パターンの i 文字目までを、候補の j 文字目までで一致させたときの最高点」。
/// 行がパターンの文字、列が候補の文字。Smith-Waterman（遺伝子の配列のあわせ方）と同じ形をしている。
///
/// 計算量は O(パターンの長さ × 一致する範囲の長さ)。ランチャーの候補（数十文字）なら十分に速い。
extension Matcher {
    /// 表が大きくなりすぎるときは v1 に戻す（fzf も同じ。メモリを守るため）
    static let v2CellLimit = 100_000

    func matchV2(text: [Character], original: [Character]) -> Match? {
        let m = chars.count
        let n = text.count
        guard n >= m else { return nil }

        // --- 1. 候補を 1 回なめて、表の 1 行目と、各文字のボーナスと、行ごとの開始位置を作る ---

        // bonus[j]: j 文字目で一致したときのボーナス（直前の文字の種類で決まる）
        var bonus = [Int](repeating: 0, count: n)
        // h0[j]: パターンの 1 文字目だけを、j 文字目で終わるように一致させたときの点
        var h0 = [Int](repeating: 0, count: n)
        // c0[j]: そこまで連続して一致している文字数（1 行目なので 1 か 0）
        var c0 = [Int](repeating: 0, count: n)
        // first[i]: パターンの i 文字目が、順番どおりに最初に現れる位置。表の i 行目はここより左を計算しない
        var first = [Int](repeating: 0, count: m)

        var pidx = 0
        var lastIdx = 0
        var prevClass: CharClass = .white
        var prevH0 = 0
        var inGap = false
        var maxScore = 0
        var maxPos = 0

        for j in 0..<n {
            let cls = CharClass(original[j])
            bonus[j] = Score.bonus(prev: prevClass, curr: cls)
            prevClass = cls

            let c = text[j]
            // パターンの文字を左から順に探す（v1 の前向きの走査と同じ）。
            // 最後の文字が最後に現れた位置 lastIdx が、表の右端になる
            if c == chars[min(pidx, m - 1)] {
                if pidx < m {
                    first[pidx] = j
                    pidx += 1
                }
                lastIdx = j
            }

            if c == chars[0] {
                let score = Score.match + bonus[j] * Score.firstCharMultiplier
                h0[j] = score
                c0[j] = 1
                // パターンが 1 文字なら、表は 1 行だけ。最高点の位置を覚える
                if m == 1, score > maxScore {
                    maxScore = score
                    maxPos = j
                    // 境界でのボーナス以上は、これより右で上回れない（境界ボーナスが最大の部類なので打ち切る）
                    if bonus[j] >= Score.boundary { break }
                }
                inGap = false
            } else {
                // 一致しない文字はすき間。点は 0 より下げない（ここから先で始め直せばよいので）
                h0[j] = max(prevH0 + (inGap ? Score.gapExtension : Score.gapStart), 0)
                c0[j] = 0
                inGap = true
            }
            prevH0 = h0[j]
        }

        // パターンの文字がすべて順番どおりに現れなかった
        guard pidx == m else { return nil }
        if m == 1 { return Match(score: maxScore, positions: [maxPos]) }

        // --- 2. 表を埋める ---
        //
        // 表は width 列 × m 行。2 次元配列（[[Int]]）にせず、1 本の配列に行を並べる（行 i の列 j は h[i * width + j - f0]）。
        // Swift の [[Int]] は行ごとに別の配列を持つので、1 本にまとめたほうがメモリが連続して速い。

        let f0 = first[0]
        let width = lastIdx - f0 + 1
        // 大きすぎるなら v1 の結果を返す（呼び出し側で判断）
        guard width * m <= Self.v2CellLimit else { return nil }

        // h[i * width + (j - f0)]: パターンの i 文字目を、候補の j 文字目で一致させて終わるときの最高点（すき間で終わるのも含む）
        var h = [Int](repeating: 0, count: width * m)
        // c[...]: その一致で、連続している文字数（0 ならすき間）
        var c = [Int](repeating: 0, count: width * m)
        // 1 行目は手順 1 の結果をそのまま写す。
        // replaceSubrange は配列の一部を置き換える（TypeScript の splice、Rust の copy_from_slice に近い）
        h.replaceSubrange(0..<width, with: h0[f0...lastIdx])
        c.replaceSubrange(0..<width, with: c0[f0...lastIdx])

        for i in 1..<m {
            let pchar = chars[i]
            let row = i * width
            let f = first[i]
            inGap = false
            // 左隣（この行の 1 つ左）を 0 から始める
            h[row + f - f0 - 1] = 0

            for j in f...lastIdx {
                let col = j - f0
                // 左から来る（すき間を広げる）
                let s2 = h[row + col - 1] + (inGap ? Score.gapExtension : Score.gapStart)
                var s1 = 0
                var consecutive = 0

                if pchar == text[j] {
                    // 左上から来る（1 つ前のパターンの文字で一致したあと、続けてこの文字で一致する）
                    s1 = h[row - width + col - 1] + Score.match
                    var b = bonus[j]
                    consecutive = c[row - width + col - 1] + 1
                    if consecutive > 1 {
                        // 連続した一致の途中では、塊の先頭のボーナスを引き継ぐ（v1 と同じ考え方）
                        let fb = bonus[j - consecutive + 1]
                        if b >= Score.boundary, b > fb {
                            // ここが塊の先頭より強い境界なら、ここから新しい塊として数え直す
                            consecutive = 1
                        } else {
                            b = max(b, Score.consecutive, fb)
                        }
                    }
                    if s1 + b < s2 {
                        // すき間で来たほうが高いなら、連続は切る
                        s1 += bonus[j]
                        consecutive = 0
                    } else {
                        s1 += b
                    }
                }
                c[row + col] = consecutive
                inGap = s1 < s2
                let score = max(s1, s2, 0)
                // 最後の行で、いちばん点の高い列が一致の終わり
                if i == m - 1, score > maxScore {
                    maxScore = score
                    maxPos = j
                }
                h[row + col] = score
            }
        }

        // --- 3. 終わりから表をさかのぼって、一致した位置を取り出す ---
        //
        // 「この点は左上（一致）から来たのか、左（すき間）から来たのか」を見て戻る。
        // 同点なら、連続している側（一致）を選ぶ
        var positions: [Int] = []
        positions.reserveCapacity(m)
        var i = m - 1
        var j = maxPos
        var preferMatch = true
        while true {
            let row = i * width
            let col = j - f0
            let s = h[row + col]
            let s1 = i > 0 && j >= first[i] ? h[row - width + col - 1] : 0
            let s2 = j > first[i] ? h[row + col - 1] : 0
            if s > s1, s > s2 || (s == s2 && preferMatch) {
                positions.append(j)
                if i == 0 { break }
                i -= 1
            }
            // 連続の途中なら、次も一致を選ぶ
            preferMatch = c[row + col] > 1 || (row + width + col + 1 < c.count && c[row + width + col + 1] > 0)
            j -= 1
        }
        // 後ろから集めたので逆にする
        return Match(score: maxScore, positions: positions.reversed())
    }
}
