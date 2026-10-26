# DuoDesk MVP 作業記録

## 目的と実装方針

iOSの既存RustDeskセッションへ、Pointer / Terminal操作デッキとDesk / Canvas / Compact表示を追加する。通信、認証、描画、IME、クリップボードは既存実装を使い、接続先の改造は要求しない。レイアウトは利用可能領域で選び、手動でも切り替える。端末名、固定解像度、折りたたみ角度には依存しない。

既存のmobile remote pageにiOS限定の入口を置く。独立Widgetは入力の意図をcallbackで伝え、既存InputModel / CursorModelへ接続する。CanvasModelにはiOSの実表示領域だけを渡す。新プロトコル、FFI関数、レンダラー、独自IMEは追加しない。

## 作業順序と進捗

- [x] Git状態・現行入力・描画・CI構成の調査。
- [x] `duodesk_actions.dart`: OS / プロファイルごとの小さなキー割当とテスト。
- [x] `duodesk_workspace.dart`: 分割表示、手動切替、タッチパッド、修飾キー、標準キーボード。Widgetテストでサイズ変更、入力、中断を確認。
- [x] `remote_page.dart` / `model.dart`: iOS限定の既存入力・描画への接続。非iOSの既存経路を維持。
- [x] 手動起動の未署名iOS CIと署名・導入手順の記録。
- [x] 関連解析・テスト、差分最小化、独立レビュー、結果・未検証事項の記録。

## 検証で優先する条件

狭い領域とキーボード表示時に操作が届くこと。回転・サイズ変更でセッションと表示Widgetの状態を保持すること。デッキの操作がリモート面のジェスチャーに重複送信されないこと。ドラッグ中断・モード変更・背景移行・切断時に押下を解除すること。貼り付けなどのOS差を既存キー入力へ正しく変換すること。

## 作業開始時の状態

P0実装開始時のブランチは `master`。ユーザーの既存変更 `flutter/analysis_options.yaml` と `flutter/pubspec.lock` を保持する。P0初回作業ではコミット・push・CI起動は行わなかった。今回の継続依頼で専用ブランチへのコミット・pushとCI実行が承認された。master/upstreamへのpush、masterへのマージ、秘密登録は行わない。ローカルFlutter SDKは読み取り専用のため `/tmp/duodesk-flutter-sdk` の作業用コピーを使う。

## 対象外

Code / Focusモード、接続先設定保存、精密ポインタ、スマートズーム、自動アプリ認識、ホスト連携は実装しない。iOS実機とmacOSビルドは利用できなければ未検証として残す。

## 実装した操作

iOSで通常の接続を開始すると操作デッキが表示される。接続、認証、ホスト側のRustDeskは従来どおり。

- 自動レイアウトは利用可能高さ420未満でCanvas、それ以外の幅600未満でCompact、残りをDeskにする。これは論理ピクセルによる操作領域の判断で、端末の識別や固定画面解像度には依存しない。メニューで手動変更できる。
- Deskは上下に画面と大型タッチパッドを配置する。Compactは狭い領域に収め、キー列をスクロールできる。Canvasは画面を優先し、下端の小さな操作列からデッキを展開できる。
- 初期モードはPointer。1本指でポインタ移動、タップで左クリック、ボタンで右クリック、2本指で縦横スクロール。長押しして移動するとドラッグ、ロックボタンでも押下を維持できる。ロック中の左タップは解除、右クリックは解除後に送信する。
- 感度は0.5〜2倍。Ctrl / Alt / Shift / Super（macOSはCommand）は選択状態を表示する。キーボードボタンは既存のiOS標準キーボードを開閉する。
- TerminalにはEsc / Tab / Enter / 矢印、Ctrl+C / R / A / E、標準tmuxのCtrl+B prefixと次・前windowを用意した。tmux側でprefixを変更している場合は標準割当は使えない。

| 貼り付け | Pointer | Terminal |
|---|---|---|
| Linux（Ubuntuを含む） | Ctrl+V | Ctrl+Shift+V |
| macOS | Command+V | Command+V |
| Windows | Ctrl+V | Ctrl+V |

コピーも同じ修飾キーとCを使う。Terminalの割り込み・履歴検索・行頭・行末は全OSでCtrl+C / R / A / E。ホストアプリ側で割当を変更している場合はその設定が優先される。貼り付けは既存クリップボードとホストの貼り付けショートカットを使う。Waylandの既存テキスト入力確認を迂回しない。

## 既存実装への接続

`duodesk_workspace.dart`はジェスチャーと表示を担当し、`duodesk_actions.dart`がOS別キー列、`duodesk_input.dart`がデッキの押下状態と離散入力の送信順、`duodesk_session.dart`が既存セッションへの接続を担当する。ポインタ移動は`CursorModel.updatePan`、クリック・押下は既存InputModel、2軸スクロールは既存trackpad経路、キー列は既存`sessionInputKey`を使う。FRBの非同期workerで離散イベントが追い越さないようawaitで順序を守る。マウス入力、キー列、確定テキストを混同しない。確定文字と変換中の処理は元のiOSハンドラーを維持する。

表示領域の実制約をCanvasModelに渡し、サイズが変わると既存の倍率とオフセットを再計算する。モード変更・回転・背景移行・操作権限の喪失ではデッキのドラッグと修飾キーを解除する。既に閉じた画面のキューが次の接続へ入力を送らないよう、画面終了時にそのデッキの受付を閉じる。切断時にはiOS限定の既存Rust終了処理から左右ボタンの解除を送り、同じ送信経路でその後にcloseする。通信切断後の再送や新しい接続管理機構は加えない。

## 検証結果

ローカルはFlutter 3.47.8 / Dart 3.13.7。CIの3.44.9とは別版なので、ローカル合格をiOSビルド合格として扱わない。

- `flutter test --no-pub test/duodesk_actions_test.dart test/duodesk_input_test.dart test/duodesk_workspace_test.dart`: 10件合格。レイアウト変更中のviewport State保持、左右クリック、2軸スクロール、ドラッグ取消・ロック解除、モード変更、権限喪失後の解除、非同期押下と解除の順序、OS別キー割当、マウス解除メッセージがnativeの文字列マップ契約を満たすことを検査した。
- `dart analyze lib/mobile/duodesk test/duodesk_actions_test.dart test/duodesk_input_test.dart test/duodesk_workspace_test.dart`: 指摘なし。
- 変更した既存Dartファイルを含む解析: 生成済み`flutter/lib/generated_bridge.dart`がないため7エラー（未定義の生成型を含む）と既存API非推奨等が残る。新規部分の指摘は修正したが、native FFIを含む型検査完了とは扱わない。指示どおりcodegenは実行していない。
- `flutter test --no-pub`全体: 53件合格、1件skip、15 suiteのロード失敗。生成bridge未配置に加え、ローカル新Flutterと既存`DialogTheme` / `TabBarTheme` / `google_fonts 6.2.1`等の互換性エラー。今回の範囲で全プラットフォームの更新は行わない。iOS CIでは既存3.44互換パッチと生成bridgeを復元する。
- Widgetの実描画をDesk / Compact Terminal / Canvas / Canvas展開で目視確認した。リモート部分は検証用の代替表示であり、実接続画面の確認ではない。
- Rust: `rustfmt --edition 2021 --emit stdout --config skip_children=true src/flutter_ffi.rs`で構文解析できた。`cargo check --locked --offline --lib --no-default-features --features flutter`は`libs/hbb_common/Cargo.toml`未配置でmanifest読込み時に停止した。Rust変更をコンパイル確認済みとは扱わない。
- `git diff --check`: 合格。iOS構成の検査と出典は[ビルド記録](ios-build.md)を参照。

全体テストでロードできなかったsuite: `api_server_warning_test.dart`, `autocomplete_peer_merge_test.dart`, `cursor_default_test.dart`, `cursor_replay_test.dart`, `cursor_size_test.dart`, `download_path_test.dart`, `file_manager_navigation_keys_test.dart`, `file_model_test.dart`, `keyboard_shortcuts_test.dart`, `quality_monitor_transport_test.dart`, `server_settings_dialog_test.dart`, `shortcut_model_test.dart`, `terminal_alt_screen_scroll_test.dart`, `terminal_model_lifecycle_test.dart`, `terminal_mouse_handler_test.dart`。

SDKが読み取り専用の場合のローカル実行では、作業用コピーと`FLUTTER_SUPPRESS_ANALYTICS=true DASH__SUPPRESS_ANALYTICS=true`を使った。解析は`ANALYZER_STATE_LOCATION_OVERRIDE=/tmp/duodesk-dart-analysis`、テストはローカルsocketを利用できる環境が必要。

## 既存動作への影響範囲

- `flutter/lib/mobile/pages/remote_page.dart`: iOSの表示・操作領域と終了時処理。従来の仮想マウスとキー補助表示はデッキと競合するためiOSのみ表示しない。既存IME、認証、映像、メニューを再利用するため、この入口の変更が必要。
- `flutter/lib/models/model.dart`: iOSから明示したviewportサイズだけを使用し、既存のキー補助用縦オフセットを重ねない。実描画領域と座標を一致させるため必要。指定がない経路は従来どおり。
- `flutter/lib/models/input_model.dart`: iOSの新viewport内で受けた物理マウス座標からSafe Areaを二重控除しないための分岐。他OSと従来経路は維持。
- `src/flutter_ffi.rs`: iOSの通常リモート接続を閉じるとき、既存session senderへ左右ボタンの解除を送ってからcloseを投入する。既存の即時切断を遅らせず、ドラッグ中の切断で押下が残るのを防ぐため必要。ファイル転送等と非iOSには適用しない。新規FFIやホスト変更はない。
- `flutter/ios/Runner/AppDelegate.swift`: 新しい手動iOS CIでのみUIScene用プラグイン登録を使う。旧Flutterの通常ビルド経路は維持。

submodule、依存lock、通信プロトコル、サーバー、Android / Windows / macOS / Linux / Webのクライアントの動作は変更していない。開始時のユーザー変更2件は保持している。

## 未検証・次の確認

macOS CIでのunsigned archive、実署名、iOS 27.1実機への導入、Ubuntu / macOS / Windowsへの接続・入力・クリップボード、実機の開閉・回転・画面サイズ変更、物理マウスとキーボードの併用は未検証。Issue #16527のCJK確定入力・削除・貼り付けは既存版との比較が必要で、今回解決したとは扱わない。

次は手動iOS CIを実行し、依存ビルドとUIScene起動を確認したうえで、上記3OSへ同じ操作を試す。P1 / P2には拡張していない。コミット・push・CI起動は行っていない。

## 開発ブランチとCI検証（継続作業）

DuoDeskのベース兼開発ブランチは`feat/duodesk-mvp`。upstreamの取込み先はこのブランチとし、最終的にもmasterへマージしない。ユーザーの既存変更2件は作業ツリーへ残し、DuoDeskのコミットに含めない。実装、ビルド基盤、CIログに基づく修正を分けてコミットし、自分のフォーク`rsuwa/rustdesk`の同名ブランチだけへpushする。PRが必要になった場合もmaster向けには作成しない。

新規workflowはデフォルトブランチへ置かないため、`workflow_dispatch`に加えて`feat/duodesk-mvp`限定のpushトリガーを追加した。これにより開発ブランチだけで未署名iOS CIを検証する。ビルド結果と成果物は以下へ追記する。
