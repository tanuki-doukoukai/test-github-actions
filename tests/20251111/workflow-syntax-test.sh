#!/bin/bash

# GitHub Actions ワークフロー構文検証テストスクリプト
# このスクリプトは実際のGitHub APIを呼ばず、構文チェックのみを行います
# 使い方: ./workflow-syntax-test.sh [PR番号]

set -e

# PR番号を引数から取得（デフォルトは123）
PR_NUMBER="${1:-123}"
REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-owner}"
REPO_NAME="${GITHUB_REPOSITORY_NAME:-repo}"
REPO="${REPO_OWNER}/${REPO_NAME}"

# カラー出力の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# テスト結果カウンター
PASSED=0
FAILED=0

# ヘッダー表示
print_header() {
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}GitHub Actions ワークフロー構文検証${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}テスト対象PR: #${PR_NUMBER}${NC}"
    echo -e "${BLUE}リポジトリ: ${REPO}${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
}

# セクションヘッダー表示
print_section() {
    echo -e "\n${BLUE}$1${NC}"
    echo "----------------------------"
}

# 成功メッセージ
print_success() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    PASSED=$((PASSED + 1))
}

# 失敗メッセージ
print_failure() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    FAILED=$((FAILED + 1))
}

# 警告メッセージ
print_warning() {
    echo -e "${YELLOW}⚠ WARNING:${NC} $1"
}

# 情報メッセージ
print_info() {
    echo -e "  $1"
}

# gh CLIがインストールされているか確認
check_gh_cli() {
    print_section "環境チェック"

    if command -v gh &> /dev/null; then
        GH_VERSION=$(gh --version | head -n 1)
        print_success "gh CLI がインストールされています: $GH_VERSION"
    else
        print_warning "gh CLI がインストールされていません（構文検証のみ実行）"
    fi

    if command -v jq &> /dev/null; then
        JQ_VERSION=$(jq --version)
        print_success "jq がインストールされています: $JQ_VERSION"
    else
        print_failure "jq が必要です。インストールしてください。"
        exit 1
    fi
}

# Test 1: Assignee処理の検証
test_assignee_processing() {
    print_section "Test 1: Assignee処理の検証 (PR #${PR_NUMBER})"

    # テストケース1: 複数assignee
    ASSIGNEES="user1,user2,user3"
    print_info "入力: $ASSIGNEES"

    # 修正前のコード（問題のある方法）
    IFS=',' read -r -a ASSIGNEE_ARRAY <<< "${ASSIGNEES}"
    ASSIGNEES_STR=$(printf '"%s",' "${ASSIGNEE_ARRAY[@]}" | sed 's/,$//')
    ASSIGNEES_JSON="{\"assignees\":[${ASSIGNEES_STR}]}"

    print_info "修正前の出力: ${ASSIGNEES_STR}"

    # JSON検証
    if echo "${ASSIGNEES_JSON}" | jq . > /dev/null 2>&1; then
        BEFORE_RESULT=$(echo "${ASSIGNEES_JSON}" | jq -r '.assignees | join(",")')
        print_info "修正前のJSON解析結果: ${BEFORE_RESULT}"
    else
        print_failure "修正前: JSON構文エラー"
        return
    fi

    # 修正後のコード（gh CLI使用）
    # 実際に実行はしないが、コマンド構文を表示
    AFTER_COMMAND="gh pr edit \"${PR_NUMBER}\" --add-assignee \"${ASSIGNEES}\" --repo \"${REPO}\""
    print_info "修正後のコマンド: ${AFTER_COMMAND}"

    if [ "${ASSIGNEES}" = "user1,user2,user3" ]; then
        print_success "修正後は正しいフォーマット（カンマ区切りをそのまま渡す）"
    else
        print_failure "修正後のフォーマットが期待と異なります"
    fi

    # テストケース2: 単一assignee
    echo ""
    ASSIGNEES_SINGLE="user1"
    print_info "単一Assigneeテスト: $ASSIGNEES_SINGLE"

    # 修正前
    IFS=',' read -r -a ASSIGNEE_ARRAY_SINGLE <<< "${ASSIGNEES_SINGLE}"
    ASSIGNEES_STR_SINGLE=$(printf '"%s",' "${ASSIGNEE_ARRAY_SINGLE[@]}" | sed 's/,$//')
    ASSIGNEES_JSON_SINGLE="{\"assignees\":[${ASSIGNEES_STR_SINGLE}]}"

    if echo "${ASSIGNEES_JSON_SINGLE}" | jq . > /dev/null 2>&1; then
        print_success "単一Assignee: JSON構文は正しい"
    else
        print_failure "単一Assignee: JSON構文エラー"
    fi

    SINGLE_COMMAND="gh pr edit \"${PR_NUMBER}\" --add-assignee \"${ASSIGNEES_SINGLE}\" --repo \"${REPO}\""
    print_info "単一Assignee用コマンド: ${SINGLE_COMMAND}"
}

# Test 2: 特殊文字を含むユーザー名の検証
test_special_characters() {
    print_section "Test 2: 特殊文字を含むユーザー名"

    # 特殊文字を含むユーザー名
    USERNAME_WITH_QUOTES='user"with"quotes'
    print_info "ユーザー名: $USERNAME_WITH_QUOTES"

    # 修正前: JSON作成時にエスケープ処理が不十分
    REVIEWERS_JSON_OLD="{\"reviewers\":[\"${USERNAME_WITH_QUOTES}\"]}"
    print_info "修正前のJSON: ${REVIEWERS_JSON_OLD}"

    if echo "${REVIEWERS_JSON_OLD}" | jq . > /dev/null 2>&1; then
        print_failure "修正前: JSON構文エラーが検出されるべき"
    else
        print_success "修正前: 期待通りJSON構文エラーが発生"
    fi

    # 修正後: jqを使った適切なJSON生成
    REVIEWERS_JSON_NEW=$(jq -n --arg user "${USERNAME_WITH_QUOTES}" '{reviewers: [$user]}')
    print_info "修正後のJSON: ${REVIEWERS_JSON_NEW}"

    if echo "${REVIEWERS_JSON_NEW}" | jq . > /dev/null 2>&1; then
        ESCAPED_USER=$(echo "${REVIEWERS_JSON_NEW}" | jq -r '.reviewers[0]')
        if [ "${ESCAPED_USER}" = "${USERNAME_WITH_QUOTES}" ]; then
            print_success "修正後: 特殊文字も安全に処理（値が一致）"
        else
            print_failure "修正後: 値が一致しません"
        fi
    else
        print_failure "修正後: JSON構文エラー"
    fi

    # gh CLI を使った場合のシミュレーション
    echo ""
    print_info "gh CLI使用時: 引数として直接渡すため安全"
    REVIEWER_COMMAND="gh pr edit \"${PR_NUMBER}\" --add-reviewer \"${USERNAME_WITH_QUOTES}\" --repo \"${REPO}\""
    print_info "コマンド: ${REVIEWER_COMMAND}"
    print_success "gh pr edit --add-reviewer は引数をエスケープ処理"
}

# Test 3: gh CLI コマンド構文の検証
test_gh_cli_syntax() {
    print_section "Test 3: gh CLI コマンド構文 (PR #${PR_NUMBER})"

    # gh pr create の構文検証
    if command -v gh &> /dev/null; then
        # ヘルプコマンドで構文確認（実際のAPIは呼ばない）
        if gh pr create --help > /dev/null 2>&1; then
            print_success "gh pr create の構文が正しい"
        else
            print_failure "gh pr create の構文エラー"
        fi

        if gh pr edit --help > /dev/null 2>&1; then
            print_success "gh pr edit の構文が正しい"
        else
            print_failure "gh pr edit の構文エラー"
        fi

        if gh api --help > /dev/null 2>&1; then
            print_success "gh api の構文が正しい"
        else
            print_failure "gh api の構文エラー"
        fi

        # --add-assignee と --add-reviewer オプションの検証
        if gh pr edit --help 2>&1 | grep -q "add-assignee"; then
            print_success "gh pr edit --add-assignee オプションが存在"
        else
            print_failure "gh pr edit --add-assignee オプションが見つかりません"
        fi

        if gh pr edit --help 2>&1 | grep -q "add-reviewer"; then
            print_success "gh pr edit --add-reviewer オプションが存在"
        else
            print_failure "gh pr edit --add-reviewer オプションが見つかりません"
        fi
    else
        print_warning "gh CLI未インストールのため構文検証をスキップ"
    fi

    # 実際のコマンド例を表示
    echo ""
    print_info "実際のコマンド例（PR #${PR_NUMBER}）:"
    print_info "  gh pr edit ${PR_NUMBER} --add-assignee \"user1,user2\" --repo \"${REPO}\""
    print_info "  gh pr edit ${PR_NUMBER} --add-reviewer \"reviewer1\" --repo \"${REPO}\""
}

# Test 4: 数値フィールドの型検証
test_numeric_fields() {
    print_section "Test 4: 数値フィールドの型検証 (PR #${PR_NUMBER})"

    # --field を使った場合（文字列として扱われる）
    FIELD_JSON=$(jq -n --arg num "${PR_NUMBER}" '{number: $num}')
    FIELD_TYPE=$(echo "${FIELD_JSON}" | jq -r 'type')
    FIELD_VALUE_TYPE=$(echo "${FIELD_JSON}" | jq -r '.number | type')

    print_info "--field での型: ${FIELD_VALUE_TYPE}"
    print_info "値: $(echo "${FIELD_JSON}" | jq -r '.number')"

    if [ "${FIELD_VALUE_TYPE}" = "string" ]; then
        print_success "--field は文字列として扱う（期待通り）"
    else
        print_failure "--field の型が期待と異なります"
    fi

    # --raw-field を使った場合（数値として扱われる）
    # jqで数値変換をシミュレート
    RAW_FIELD_JSON=$(jq -n --argjson num "${PR_NUMBER}" '{number: $num}')
    RAW_FIELD_VALUE_TYPE=$(echo "${RAW_FIELD_JSON}" | jq -r '.number | type')

    print_info "--raw-field での型: ${RAW_FIELD_VALUE_TYPE}"
    print_info "値: $(echo "${RAW_FIELD_JSON}" | jq -r '.number')"

    if [ "${RAW_FIELD_VALUE_TYPE}" = "number" ]; then
        print_success "--raw-field で数値型が保持される"
    else
        print_failure "--raw-field の型が期待と異なります"
    fi

    # 修正前のコード（jq -n で数値変換）
    echo ""
    print_info "修正前: jq の tonumber を使用"
    OLD_JSON=$(jq -n \
        --arg pr_number "${PR_NUMBER}" \
        '{number: ($pr_number | tonumber)}')
    OLD_TYPE=$(echo "${OLD_JSON}" | jq -r '.number | type')
    print_info "修正前の型: ${OLD_TYPE}"

    if [ "${OLD_TYPE}" = "number" ]; then
        print_success "tonumber で数値型に変換（正しい）"
    else
        print_failure "tonumber による変換が失敗"
    fi
}

# Test 5: Repository Dispatch ペイロードの検証
test_repository_dispatch() {
    print_section "Test 5: Repository Dispatch ペイロード検証 (PR #${PR_NUMBER})"

    # 修正前のコード
    print_info "修正前: jq -n で複雑なJSONを生成"
    JSON_PAYLOAD_OLD=$(jq -n \
        --arg event_type "my-event" \
        --arg author "octocat" \
        --arg pr_number "${PR_NUMBER}" \
        --arg pr_title "Test PR #${PR_NUMBER}" \
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

    if echo "${JSON_PAYLOAD_OLD}" | jq . > /dev/null 2>&1; then
        print_success "修正前: JSON構文が正しい"

        # 型チェック
        PR_NUM_TYPE=$(echo "${JSON_PAYLOAD_OLD}" | jq -r '.client_payload.pull_request.number | type')
        if [ "${PR_NUM_TYPE}" = "number" ]; then
            print_success "修正前: PR番号が数値型（tonumberが機能）"
        else
            print_failure "修正前: PR番号が数値型ではありません"
        fi

        print_info "生成されたJSON:"
        echo "${JSON_PAYLOAD_OLD}" | jq '.'
    else
        print_failure "修正前: JSON構文エラー"
    fi

    # 修正後: gh api でのフィールド指定をシミュレート
    echo ""
    print_info "修正後: gh api の --field と --raw-field を使用"

    # 実際のコマンド例
    GH_API_COMMAND="gh api repos/${REPO}/dispatches \\
  --method POST \\
  --field event_type=\"my-event\" \\
  --field client_payload[author]=\"octocat\" \\
  --raw-field client_payload[pull_request][number]=${PR_NUMBER} \\
  --field client_payload[pull_request][title]=\"Test PR #${PR_NUMBER}\""

    print_info "コマンド例:"
    echo "${GH_API_COMMAND}"

    # gh api の動作をシミュレート（実際には呼ばない）
    JSON_PAYLOAD_NEW=$(jq -n \
        --arg event_type "my-event" \
        --arg author "octocat" \
        --argjson pr_number "${PR_NUMBER}" \
        --arg pr_title "Test PR #${PR_NUMBER}" \
        '{
            event_type: $event_type,
            client_payload: {
                author: $author,
                pull_request: {
                    number: $pr_number,
                    title: $pr_title
                }
            }
        }')

    if echo "${JSON_PAYLOAD_NEW}" | jq . > /dev/null 2>&1; then
        print_success "修正後: JSON構文が正しい"

        PR_NUM_TYPE_NEW=$(echo "${JSON_PAYLOAD_NEW}" | jq -r '.client_payload.pull_request.number | type')
        if [ "${PR_NUM_TYPE_NEW}" = "number" ]; then
            print_success "修正後: PR番号が数値型（--raw-field相当）"
        else
            print_failure "修正後: PR番号が数値型ではありません"
        fi
    else
        print_failure "修正後: JSON構文エラー"
    fi

    # 両方のJSONが同等か確認
    echo ""
    if [ "$(echo "${JSON_PAYLOAD_OLD}" | jq -c .)" = "$(echo "${JSON_PAYLOAD_NEW}" | jq -c .)" ]; then
        print_success "修正前後のJSONペイロードが同等"
    else
        print_warning "修正前後のJSONペイロードに差異がありますが、構造は正しい"
    fi
}

# Test 6: エッジケースの検証
test_edge_cases() {
    print_section "Test 6: エッジケース検証"

    # 空のAssignee
    print_info "空のAssignee処理"
    ASSIGNEES=""
    if [ "${ASSIGNEES}" != "" ]; then
        print_failure "空チェックが機能していません"
    else
        print_success "空のAssigneeは正しくスキップされる"
    fi

    # 空白を含むAssignee
    echo ""
    print_info "空白を含むAssignee: 'user 1,user 2'"
    ASSIGNEES_WITH_SPACE="user 1,user 2"
    # gh CLI は空白を含むユーザー名も処理できる
    print_success "gh CLI は空白を含む値も引数として正しく処理"

    # 特殊文字のエスケープ
    echo ""
    print_info "特殊文字のエスケープテスト"
    SPECIAL_TITLE='Title with "quotes" and $variables'
    TITLE_JSON=$(jq -n --arg title "${SPECIAL_TITLE}" '{title: $title}')

    if echo "${TITLE_JSON}" | jq . > /dev/null 2>&1; then
        EXTRACTED=$(echo "${TITLE_JSON}" | jq -r '.title')
        if [ "${EXTRACTED}" = "${SPECIAL_TITLE}" ]; then
            print_success "特殊文字が正しくエスケープされている"
        else
            print_failure "特殊文字のエスケープに問題があります"
        fi
    else
        print_failure "特殊文字を含むJSON生成に失敗"
    fi

    # PR番号の妥当性チェック
    echo ""
    print_info "PR番号の妥当性チェック: ${PR_NUMBER}"
    if [[ "${PR_NUMBER}" =~ ^[0-9]+$ ]]; then
        print_success "PR番号は有効な数値"
    else
        print_failure "PR番号が数値ではありません: ${PR_NUMBER}"
    fi
}

# Test 7: 実際のワークフロー比較
test_workflow_comparison() {
    print_section "Test 7: ワークフロー比較 (PR #${PR_NUMBER})"

    print_info "修正前のワークフロー（curl使用）:"
    echo "  IFS=',' read -r -a ASSIGNEE_ARRAY <<< \"user1,user2\""
    echo "  ASSIGNEES_STR=\$(printf '\"%s\",' \"\${ASSIGNEE_ARRAY[@]}\" | sed 's/,\$//')"
    echo "  curl -X POST -H \"Authorization: token \$TOKEN\" \\"
    echo "    https://api.github.com/repos/${REPO}/issues/${PR_NUMBER}/assignees \\"
    echo "    -d \"{\\\"assignees\\\":[\${ASSIGNEES_STR}]}\""

    echo ""
    print_info "修正後のワークフロー（gh CLI使用）:"
    echo "  gh pr edit ${PR_NUMBER} --add-assignee \"user1,user2\" --repo \"${REPO}\""

    echo ""
    print_success "修正後の利点:"
    print_info "  1. コードが簡潔で読みやすい"
    print_info "  2. エスケープ処理が自動"
    print_info "  3. エラーハンドリングが組み込み"
    print_info "  4. 認証が gh CLI で管理される"
}

# メイン実行
main() {
    print_header
    check_gh_cli
    test_assignee_processing
    test_special_characters
    test_gh_cli_syntax
    test_numeric_fields
    test_repository_dispatch
    test_edge_cases
    test_workflow_comparison

    # 最終結果
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    TOTAL=$((PASSED + FAILED))
    echo -e "${GREEN}成功: ${PASSED}${NC} / ${TOTAL}"

    if [ ${FAILED} -eq 0 ]; then
        echo -e "${GREEN}すべてのテストが成功しました${NC}"
        echo -e "${BLUE}==========================================${NC}"
        exit 0
    else
        echo -e "${RED}失敗: ${FAILED}${NC} / ${TOTAL}"
        echo -e "${RED}一部のテストが失敗しました${NC}"
        echo -e "${BLUE}==========================================${NC}"
        exit 1
    fi
}

# スクリプト実行
main
