# GitHub Actions ワークフロー構文検証

以下の GitHub Actions ワークフローの変更が構文的に正しいか検証する bash スクリプトを作成してください。

## 検証したい変更パターン

### パターン 1: PR 作成と Assignee 追加

**変更前:**

```bash
PR_JSON=$(jq -n \
  --arg title "PR Title" \
  --arg head "feature-branch" \
  --arg base "main" \
  --arg body "PR Body" \
  '{title: $title, head: $head, base: $base, body: $body}')

PR_DATA=$(curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/owner/repo/pulls \
  -d "${PR_JSON}")

PR_NUMBER=$(echo "${PR_DATA}" | jq -r .number)

if [ "${ASSIGNEES}" != "" ]; then
  IFS=',' read -r -a ASSIGNEE_ARRAY <<< "${ASSIGNEES}"
  ASSIGNEES_STR=$(printf '"%s",' "${ASSIGNEE_ARRAY[@]}" | sed 's/,$//')
  ASSIGNEES_JSON="{\"assignees\":[${ASSIGNEES_STR}]}"
  curl -s -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/owner/repo/issues/${PR_NUMBER}/assignees \
    -d "${ASSIGNEES_JSON}"
fi
変更後:
PR_URL=$(gh pr create \
  --title "PR Title" \
  --head "feature-branch" \
  --base "main" \
  --body "PR Body" \
  --repo "owner/repo")

PR_DATA=$(gh pr view "${PR_URL}" --json number,title,url)
PR_NUMBER=$(echo "${PR_DATA}" | jq -r .number)

if [ "${ASSIGNEES}" != "" ]; then
  gh pr edit "${PR_NUMBER}" --add-assignee "${ASSIGNEES}"
fi
パターン2: レビュアー追加
変更前:
REVIEWERS_JSON="{\"reviewers\":[\"${AUTHOR}\"]}"
curl -s -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/owner/repo/pulls/123/requested_reviewers \
  -d "${REVIEWERS_JSON}"
変更後:
gh pr edit "123" --add-reviewer "${AUTHOR}"
パターン3: Repository Dispatch with 数値フィールド
変更前:
JSON_PAYLOAD=$(jq -n \
  --arg event_type "my-event" \
  --arg author "octocat" \
  --arg pr_number "123" \
  --arg pr_title "My PR" \
  '{
    event_type: $event_type,
    client_payload: {
      author: $author,
      pull_request: {
        number: ($pr_number | tonumber),
        title: $pr_title
      }
    }
  }')

curl -s -X POST \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/owner/repo/dispatches \
  -d "${JSON_PAYLOAD}"
変更後:
gh api repos/owner/repo/dispatches \
  --method POST \
  --field event_type="my-event" \
  --field client_payload[author]="octocat" \
  --raw-field client_payload[pull_request][number]=123 \
  --field client_payload[pull_request][title]="My PR"
作成してほしいテストスクリプト
要件
実際にGitHub APIを呼ばない（構文チェックのみ）
以下を検証:
gh CLI コマンドの構文が正しいか
Assignee処理: カンマ区切り文字列が正しく処理されるか
Reviewer追加: 特殊文字を含むユーザー名でも安全か
gh api の --field と --raw-field の違いを確認
数値フィールドが正しく型として扱われるか
テストケース:
単一assignee: "user1"
複数assignee: "user1,user2,user3"
特殊文字を含むユーザー名: 'user"with"quotes'
数値フィールドの型検証
比較検証:
修正前のコードで発生する問題（引用符付きCSV等）
修正後のコードが問題を解決することを確認
スクリプトの出力形式
==========================================
GitHub Actions ワークフロー構文検証
==========================================

Test 1: Assignee処理の検証
----------------------------
入力: user1,user2,user3
修正前の出力: "user1","user2","user3"
修正後の出力: user1,user2,user3
✓ PASS: 修正後は正しいフォーマット

Test 2: 特殊文字を含むユーザー名
----------------------------
ユーザー名: user"with"quotes
修正前: JSON構文エラー
修正後: 正常に処理
✓ PASS: 特殊文字も安全に処理

Test 3: gh CLI コマンド構文
----------------------------
✓ PASS: gh pr create の構文が正しい
✓ PASS: gh pr edit --add-assignee の構文が正しい
✓ PASS: gh pr edit --add-reviewer の構文が正しい
✓ PASS: gh api の構文が正しい

Test 4: 数値フィールドの型検証
----------------------------
--field での型: "string"
--raw-field での型: "number"
✓ PASS: --raw-field で数値型が保持される

==========================================
すべてのテストが成功しました
==========================================
注意事項
gh CLIのヘルプやバージョン確認は実行してOK
実際のPR作成やAPI呼び出しは行わない
JSON生成の正当性をjqで検証
カラー出力（緑=成功、赤=失敗、黄=警告）
このテストスクリプトを作成してください。実行可能な完全なbashスクリプトとして提供してください。
```
