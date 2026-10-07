# ADR-0011: Example database の永続化形式と name の明示指定

- 状態: Accepted
- 日付: 2026-09-30
- 関連: Issue #26、[specs/runner.md](../specs/runner.md)（Example database）

## 文脈

Spec は縮小後の選択列を `{database_dir}/{sha256(name)の先頭16桁}/{選択列のハッシュ}`
に保存し、次回実行で生成前に再生することを定めている。
加えて `name` の既定値を呼び出し位置から自動導出できるか（Mojo の
`call_location` 相当の機能の有無）を M4 で調査することになっていた。

Mojo 1.2.0.dev2026092605 の stdlib を検証した結果、呼び出し位置の取得手段は
見つからなかった。試したもの: `__file__`、`std.source_location`、
`std.sys.call_location`、`std.compile.current_file`、`std.reflect`、
`std.debug`、`std.defines`（いずれも未定義かモジュール自体が存在しない）。
comptime の型名文字列化（`type_of`）は存在するが、表示用 API がなく、
同一クロージャの別呼び出し位置を区別できる保証もない。

stdlib のファイル I/O は `std.os`（`mkdir`・`remove`・`listdir`）と
`std.pathlib.Path`（`write_text`・`read_text`・`exists`・`is_dir`・
`is_file`・`listdir`・`/` 結合）で足りることを確認した。`std.os.remove`
はディレクトリを削除できないが、削除対象は選択列ファイルだけなので問題
ない。ハッシュ用の stdlib API（`std.hash`・`std.hashlib` の素朴な利用）は
使えなかった。

## 決定

- `settings.name` は明示指定のままにする。空文字列は database を使わない
  ことを表し、既定値とする。呼び出し位置の自動導出は行わない。
- 配置は Spec 通り `{database_dir}/{sha256(name)[:16]}/{sha256(replay)}`
  とする。ファイル名は replay 文字列（Base64 は `/` を含み得るためその
  ままでは使えない）の SHA-256 hex 全 64 桁とし、内容は replay 文字列
  そのものとする。
- SHA-256 はリポジトリ内で純粋関数として実装する（`database.mojo` の
  `sha256_hex`）。stdlib に依存せず、FIPS 180-4 の既知ベクターで検証する。
- `load` はデコードせずファイル内容の列をソートして返す。検証はランナー
  が再生時に行い、デコード失敗・非 INTERESTING のファイルは列挙時の実名
  で削除する（内容ハッシュでは消せない場合があるため）。

## 検討した代替案

- comptime の型名から `name` を自動導出する: 型名の文字列化 API がなく、
  別位置の同一クロージャを区別できる保証もない。採用しない。
- 環境変数で `name` の既定値を与える: 暗黙のグローバル状態であり、
  coding-guidelines の方針に反する。採用しない。
- ファイル名に replay 文字列をそのまま使う: `/` がパス区切りと衝突する。
  Base64URL への置換も考えられるが、固定長ハッシュの方が衝突時の挙動が
  明確で一覧性も高い。採用しない。
- FNV-1a 等の短い独自ハッシュで代用する: 実装は楽だが Spec の sha256
  指定と食い違う。SHA-256 の自前実装は約 100 行で済むため Spec 通りにする。

## 結果

- `for_all` の呼び出し側は反例を永続化したい場合に `name` を付ける必要が
  ある。付けなければ従来通り何も保存されない。
- `.proptest-mojo/` は `.gitignore` 済みのため、既定のまま使う分には作業
  ツリーを汚さない。コミットすれば回帰テストになる。
- コンパイラが呼び出し位置取得（`call_location` 相当）を備えたら、この
  ADR を Superseded にして自動導出を再検討する。
