# DuoDesk iOSビルド

確認日: 2026-10-26。Ubuntu上で構成を編集・検査した。macOS CI、iOSシミュレーター、実機でのビルド・起動・接続は未実施。

## 既存構成と今回の選択

既存の `.github/workflows/flutter-build.yml` はFlutter 3.24.5、Rust 1.75、`macos-latest`でiOSをビルドする。Xcode/SDKは固定していない。Rustは`flutter,hwcodec`機能の`aarch64-apple-ios`静的ライブラリを生成し、Xcodeプロジェクトが`target/aarch64-apple-ios/release/liblibrustdesk.a`をリンクする。FFI生成物は既存の`bridge.yml`から復元する。IPAアップロード工程はコメントアウトされている。

[Appleの対応表](https://developer.apple.com/xcode/system-requirements)ではXcode 27.1がiOS 27.1 SDKを提供する。[GitHubの告知](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)と[ランナー収録内容](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)を確認し、独立した手動ワークフロー `.github/workflows/duodesk-ios.yml` を追加した。

| 項目 | DuoDeskの構成 |
|---|---|
| 起動 | `workflow_dispatch`と`feat/duodesk-mvp`限定push。自動公開・署名なし |
| ランナー | `xcode-27`、Apple Silicon |
| Xcode / SDK | `/Applications/Xcode_27.1.app`、iOS 27.1。開始時にバージョンを検査 |
| Flutter | 3.44.9 stable。Dartは同梱版を使いログへ出力 |
| Rust | 1.75.0、`aarch64-apple-ios`、既存と同じ機能 |
| vcpkg | 既存と同じ`9e593bb18ea69cc5095e012465dcd675a822ed0d`、`arm64-ios` |
| 対象OS | このワークフロー内でiOS 27.1以降へ設定 |
| 成果物 | `duodesk-ios-unsigned`内の`DuoDesk.xcarchive.zip`と`DuoDesk-unsigned.ipa`、保持7日 |

全プラットフォームのFlutterを更新せず、既存の3.44用互換パッチと`bridge-artifact-flutter-3.44`を再利用する。[Flutterの変更履歴](https://github.com/flutter/flutter/blob/master/CHANGELOG.md)には3.44.8でXcode 27のlipo検証問題を修正した記録がある。最新系列への移行を広げず、その修正を含む既存の3.44.9を選んだ。

ツールチェーンとRustの依存解決は固定する。新しいFlutterに合わせた`flutter pub get`とCocoaPodsの解決はCIの一時checkoutで行うため、依存配布物まで含む完全な同一バイナリ再現性は保証しない。ローカルの既存`pubspec.lock`変更には手を加えない。

## UIScene

[Apple](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)と[Flutterの移行手順](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)では、iOS 27 SDKでビルドするUIKitアプリはUISceneが必須。現行のAppDelegateは音声設定とRustシンボル参照を持つため、自動移行に任せない。

`AppDelegate.swift`に`DUODESK_UI_SCENE`条件付きで`FlutterImplicitEngineDelegate`への適合を追加し、プラグイン登録を`didInitializeImplicitFlutterEngine`で行う。この条件がない既存ビルドは以前と同じ登録経路を使う。音声設定とRust参照は維持する。

固定版3.44.9の[FlutterEngine.h](https://github.com/flutter/flutter/blob/3.44.9/engine/src/flutter/shell/platform/darwin/ios/framework/Headers/FlutterEngine.h#L449)でも、このプロトコルと`pluginRegistry`を確認した。[FlutterEngine.mm](https://github.com/flutter/flutter/blob/3.44.9/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm#L954)はAppDelegateの適合を検査して登録コールバックを呼ぶ。LinuxにはUIKitとiOS用Flutter frameworkがないため、この照合はSwiftの実SDK型検査の代わりにはならない。

手動ワークフローの「Prepare iOS-only Flutter and UIScene configuration」が、Release設定へ条件を追加し、Info.plistへ`FlutterSceneDelegate`と`Main`ストーリーボードを指定する単一sceneのmanifestを追加する。同じ工程で表示名をDuoDesk、配備対象を27.1へ設定する。これらはCI作業コピーだけの変更で、旧FlutterのiOS構成や他OSには適用しない。折りたたみ角度APIや複数sceneには依存しない。

## 未署名ビルドの実行

コードを対象リポジトリへ反映した後、GitHub Actionsから **DuoDesk iOS (unsigned)** を選び、対象ブランチの **Run workflow** を実行する。初回P0実装ではpush・CI起動を行わなかった。継続作業では専用ブランチへのpushとCI実行が承認されている。デフォルトブランチへ追加せず起動するため、この開発ブランチ限定のpushトリガーも用意した。

ワークフローは既存のLinux用FFI生成ジョブを呼び、macOSで以下を実行する。

1. Xcode/SDKを検査し、Flutter互換パッチとUIScene設定を適用する。
2. 生成済みFFIを復元し、Flutter依存解決と`test/duodesk_*_test.dart`を実行する。
3. vcpkgで既存の映像・音声依存をビルドする。
4. `cargo build --locked --features flutter,hwcodec --release --target aarch64-apple-ios --lib`を実行する。
5. `flutter build ipa --release --no-codesign`で未署名archiveを生成する。
6. archiveと、その`Runner.app`を`Payload`へ入れた未署名IPAをアップロードする。

未署名IPAの作成はAppleの署名済みexportではない。端末へ直接インストールできない。シミュレーター向けRustライブラリは生成しない。

## 署名と実機インストール（別工程・未実施）

[Flutter公式のiOS配布手順](https://docs.flutter.dev/deployment/ios)を参照する。署名には利用者自身のApple Account、証明書、適切なプロビジョニングが必要。現在のXcodeプロジェクトにはupstreamのBundle IdentifierとTeam IDが残っており、そのまま自分のアカウントで配布できるとは限らない。

確実な経路は、Mac上の同じソースにワークフローの互換パッチ・UIScene準備を適用し、同じFFIとRustライブラリを用意してから、`flutter/ios/Runner.xcworkspace`を開く方法。RunnerのBundle Identifierを自分が使える値にし、Signing & Capabilitiesで自分のTeamとプロビジョニングを選ぶ。iOS 27.1以降の端末へXcodeから実行するか、ArchiveからDevelopment/Ad Hoc等の用途に合う署名済みIPAをexportしてインストールする。証明書・秘密鍵・認証情報・プロビジョニングをリポジトリへ保存しない。

ダウンロードした未署名archiveを再署名・exportする場合も、識別子、証明書、プロビジョニングの整合性が必要。手元の権限で一致させられない場合は上記のソースからの署名ビルドを使う。TestFlight/App Storeへの送信は今回の工程に含めない。

## 検証と残作業

- ローカル: YAML解析、埋め込みシェルの`bash -n`、準備工程の一時コピー上での実行、生成manifest・配備対象・Swift条件の確認に合格した。`swiftc -frontend -parse`も`DUODESK_UI_SCENE`あり・なしで合格した。これは構文と設定生成の検査であり、Flutter SDKとの型検査ではない。
- 未検証: macOSでの依存ビルド、SwiftのFlutter SDKを使った型検査、Xcode archive生成、署名、インストール、UIScene起動、折りたたみ・回転時の実機挙動、実接続。
- Rust 1.75で読めるlock形式v3を保持しているが、全依存を同版でコンパイルする検証は未実施。既存のFFmpeg用iOS overlayに残る`-mios-version-min=8.0`、`-fembed-bitcode`等を含め、新SDKでのネイティブ依存互換性は最初のCI実行で確認する。
- CI失敗時は依存ビルド、FFI、Flutter、Xcode、署名を分けて調べる。未署名CIの合格を実機操作の合格とは扱わない。
- [RustDesk Issue #16527](https://github.com/rustdesk/rustdesk/issues/16527)はopen（2026-10-26確認）。iOS→macOSでCJKの確定単文字がキーストローク経路へ流れる問題が報告されている。DuoDeskは既存の標準キーボード・IME経路を利用し、この問題を解決したとは扱わない。日本語・中国語・韓国語の確定入力、削除、貼り付けを実機で比較する。ホストのIMEや入力方式まで変える修正は独立課題とする。
