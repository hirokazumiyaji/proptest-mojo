# ADR-0009: TestCase.draw のために testcase と strategy の参照循環を許す

- 状態: Accepted
- 日付: 2026-09-30
- 関連: Issue #6、[specs/choice-sequence.md](../specs/choice-sequence.md)（TestCase.draw）、[specs/architecture.md](../specs/architecture.md)

## 文脈

Spec は `tc.draw(strategy)` を `TestCase` のメソッドとして定めている。
メソッドのシグネチャ `draw[S: Strategy](mut self, strategy: S, ...)` は
`Strategy` トレイトの名前を必要とするため、`testcase.mojo` は
`strategy.mojo` を import しなければならない。
一方 `Strategy.draw` のシグネチャは `TestCase` を必要とするため、
`strategy.mojo` は `testcase.mojo` を import しなければならない。
2 モジュール間の参照循環は避けられない構造になっている。

Mojo 1.2.0.dev2026092605 で循環 import を検証した結果、コンパイル・実行・
`precompile` のいずれも問題なく通ることを確認した。

## 決定

- `testcase.mojo` と `strategy.mojo`（および将来の `strategies/` 配下）の間の参照循環を許す。これを唯一の例外とし、他の層間の依存は一方向に保つ。
- `testcase` から `strategy` への依存は `TestCase.draw` のジェネリック境界のためだけに使う。`TestCase` の本体（選択の供給・記録・span・状態）は `Strategy` の詳細を知らない。
- 実行時の呼び出し方向はシェルからコアへの一方向（`TestCase.draw` → `Strategy.draw` → `draw_integer` 等）のまま保つ。

## 検討した代替案

- `draw` を `strategy.mojo` の自由関数 `draw(tc, strategy)` にする: 循環は消えるが、Spec の `tc.draw` という API を変えることになる。採用しない。
- `Strategy` トレイトを `testcase.mojo` に移す: 循環は消えるが、責務（選択の供給と値の生成器）が 1 モジュールに混ざり、architecture の配置と矛盾する。採用しない。

## 結果

- Spec 通りの `tc.draw(strategy, label)` API が使える。
- 循環の範囲がこの 2 モジュールに限定されることを、architecture の依存方向の節に明記する。
- コンパイラが循環 import を拒むようになった場合は、この ADR を見直し、自由関数案への切り替えを検討する。
