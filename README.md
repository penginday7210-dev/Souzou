# Souzou — Node.js不要のゲーム投稿サイト

静的HTML/CSS/JavaScriptで動作します。ビルド工程もNode.jsサーバーも不要です。ホスティングはCloudflare Pages、認証・データベース・ファイル保管はSupabaseを使います。

## ファイル

- `index.html` — ページ構造、ログイン・投稿・ゲーム・評価モーダル
- `styles.css` — レスポンシブデザイン
- `config.js` — Supabaseの公開URLとanon/public keyを設定するファイル
- `js/app.js` — Supabase接続、ログイン、投稿、検索、いいね、レビュー
- `supabase_setup.sql` — DBテーブル、ビュー、RLS、Storageバケット、いいねRPCの作成SQL
- `_headers` — Cloudflare Pages用の基本セキュリティヘッダー

## 1. Supabaseを準備する

1. https://supabase.com/ でアカウントを作成し、New projectでプロジェクトを作ります。
2. プロジェクトの **SQL Editor** を開き、`supabase_setup.sql` の内容を貼り付けて Run します。
3. **Project Settings → API**（画面によっては Connect / API Keys）からProject URLと `anon` / `publishable` の公開キーを取得します。
4. `config.js` の値を置き換えます。

```js
window.SOUZOU_CONFIG = {
  SUPABASE_URL: "https://あなたのプロジェクトID.supabase.co",
  SUPABASE_ANON_KEY: "あなたのanonまたはpublishable公開キー"
};
```

**絶対に `service_role` / secret key をブラウザー側のファイルに入れないでください。** このサイトはRLSポリシーに依存します。SQL実行後、SupabaseのTable Editorで `games`、`reviews`、`game_likes` とビュー `games_public` / `reviews_public` ができていることを確認します。

### メール認証設定

Supabaseの **Authentication → URL Configuration** で、公開後のサイトURLを Site URL と Redirect URLs に登録します。デプロイ前はローカルでの認証メールリンクが期待通り戻らない場合があります。公開URLを取得してから必ず設定を更新してください。開発中はメール確認が有効な場合、登録後にメール内リンクを開く必要があります。

## 2. Cloudflare Pagesに公開する（無料URL）

### かんたんな方法：GitHub連携

1. GitHubで新しいリポジトリを作り、**このフォルダの中身**をリポジトリのルートへアップロードします。`index.html` がリポジトリの最上位にあるようにしてください。
2. https://dash.cloudflare.com/ を開き、**Workers & Pages → Create → Pages → Connect to Git**（表示名は変更される場合があります）へ進みます。
3. GitHubを接続してSouzouのリポジトリを選びます。
4. Framework preset は **None**、Build command は空欄、Build output directory は `/` または `.`（ダッシュボードの入力規則に従う）にします。ルート直下の静的ファイルをそのまま配信する構成です。
5. Deployを押します。`https://プロジェクト名.pages.dev` のような無料URLが発行されます。

### Gitを使わない方法

Cloudflareのダッシュボードに **Direct Upload** が表示されていれば、ファイルをアップロードして公開することもできます。Pagesプロジェクトの作成画面で選べる方式を確認してください。Git連携とDirect Uploadは作成後に切り替えられない場合があるため、後から自動更新したいならGit連携がおすすめです。

## 3. 公開後に必ず設定すること

1. Supabaseの **Authentication → URL Configuration** に `https://プロジェクト名.pages.dev` をSite URLとRedirect URLとして登録します。
2. 公開URLでアカウント登録し、ログインできるか確認します。
3. ログイン後、HTMLゲームファイルを投稿します。投稿者以外の別ブラウザーでも一覧から開けること、評価が保存されることを確認します。
4. デプロイ後に `config.js` を変更した場合は、そのファイルを再デプロイしてください。

## 機能

- メールアドレス＋パスワードで新規登録 / ログイン / ログアウト
- HTMLシングルファイルゲーム投稿（10MBまで）とカバー画像（3MBまで）
- タイトル・説明・カテゴリ検索、カテゴリ絞り込み、新着 / 高評価 / 人気順
- いいね（ログイン必須、同一ユーザーはトグル）
- 1ゲームにつき1ユーザー1件の評価（再送信で更新）、コメント、平均評価表示
- モバイル対応レイアウト

## 制限とセキュリティ上の重要事項

- **現時点ではスターター実装です。** 管理者画面、通報・モデレーション、スパム対策、アップロードのウイルススキャン、ゲームの編集・削除UI、複数ファイルやZIP形式、ユーザープロフィールは含みません。
- HTMLゲームはJavaScriptを実行できるため、投稿前に信頼できるファイルだけを受け入れる運用を推奨します。iframeは `sandbox="allow-scripts"` にしてありますが、これだけで全リスクがなくなるわけではありません。ユーザー数を増やす前に、投稿ゲームを専用の別ドメインで配信し、厳格なCSP、容量・レート制限、通報・削除手順を整えてください。
- Supabaseの公開キーはフロントエンドで使う前提ですが、**安全性はRLSポリシーが担います**。サービスロールキーを公開しないこと。SQLの実行後にRLSが有効であることを確認してください。
- 公開前にプライバシーポリシー、利用規約、著作権侵害コンテンツの削除方針を用意してください。
- Google FontsとSupabase JS SDKは外部サービスから読み込まれます。利用環境によってはアクセス制限の影響を受けることがあります。
- Supabaseの無料枠には容量・通信量・非アクティブプロジェクト等の制限があり、料金・仕様は変更される可能性があります。公開前に公式の最新条件を確認してください。

## トラブルシューティング

- 「プレビュー表示中」から変わらない：`config.js` のURLと公開キーが正しいか、再デプロイしたかを確認。
- ログインや投稿でエラー：SQL全体が成功したか、Supabase AuthのURL設定、ブラウザーConsoleのエラーを確認。
- ゲーム投稿が失敗：StorageバケットとStorageポリシーが作成されているか、HTML 10MB以下か確認。
- ゲーム一覧が空：Supabaseの `games_public` ビューが存在し、SQL Editorでエラーなく作成されたか確認。
- ローカルで試す場合：`file://` で開くのではなく、静的ファイルサーバーを使ってください。公開後はPages URLでテストするのが最も確実です。
