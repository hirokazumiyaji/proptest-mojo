# セットアップ

## 前提

- [pixi](https://pixi.sh/): ツールチェーン (Mojo nightly) の管理に使います。
  `pixi.toml` の `platforms` は `osx-arm64` と `linux-64` です。
- Mojo を直接呼ばず、必ず `pixi run mojo ...` 経由で実行します。

## 手順

```sh
git clone https://github.com/hirokazumiyaji/proptest-mojo.git
cd proptest-mojo
pixi install
```

## 実行方法

| 目的 | コマンド |
|------|----------|
| テスト | `pixi run test` (`tests/**/test_*.mojo` を全実行) |
| example 実行 | `pixi run mojo run -I src examples/basic.mojo < /dev/null` |
| フォーマット | `pixi run format` |
| フォーマット検査 | `pixi run format-check` |

`for_all` は標準入力を読みませんが、CI と同じ条件にするため
`< /dev/null` を付ける運用です。

## 自分のテストで使う

このリポジトリ内で試す場合、`src` を `-I` で通せば
`from proptest import ...` で import できます。

```sh
pixi run mojo run -I src path/to/my_property_test.mojo < /dev/null
```

`std.testing.TestSuite` の中で使う場合は、`for_all(prop)` が反例つきの
`Error` を送出するので、そのままテスト失敗として扱えます
(詳細は [basics](basics.md) と [Specs: ランナー](../specs/runner.md))。

## CI での回し方

生成数を増やしたいときはコードを変えずに環境変数で上書きできます
(明示した値は環境変数より優先されます)。

```sh
PROPTEST_MAX_EXAMPLES=1000 PROPTEST_SEED=42 pixi run test
```

- `PROPTEST_MAX_EXAMPLES`: `Settings` の既定の生成数を上書きする。
- `PROPTEST_SEED`: `Settings(seed=None)` のときのシードを固定する。
  詳細は [replay](replay.md)。
