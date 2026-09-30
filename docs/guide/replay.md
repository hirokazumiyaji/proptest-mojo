# 再現

実行は決定的です。同じシードでは同じ example 列が生成され、
同じ反例が同じ報告になります。

## シード固定

報告書の `Seed:` 行の値を使います。

```mojo
for_all(prop, Settings(seed=UInt64(3)))
```

環境変数でも固定できます。`Settings(seed=None)` (既定) のときだけ有効で、
コードで明示した値は環境変数より優先されます。

```sh
PROPTEST_SEED=3 pixi run mojo run -I src examples/basic.mojo < /dev/null
```

## 生成数を変える

既定の `max_examples` (100) は `PROPTEST_MAX_EXAMPLES` で上書きできます。
CI で回数を増やす用途です。コードで明示した値は優先されます。

```sh
PROPTEST_MAX_EXAMPLES=1000 pixi run test
```

## 計画中のもの

- `Settings(replay=...)`: 報告された選択列を直接再生する (M4)。
  現時点ではシード固定で再現してください。
- example database (`.proptest-mojo/`): 一度見つけた反例を次回最初に
  再試行する (M4)。現時点では見つけた反例を回帰テストとして別途保存し、
  `just` や固定シードの `for_all` で回してください。

最新状況は [Specs: ランナー](../specs/runner.md) を参照してください。
