#!/bin/bash

set -euo pipefail

echo "🧠 Running check-all-ci-passed script..."

# 必須環境変数の確認
: "${GITHUB_REPOSITORY:?Missing GITHUB_REPOSITORY}"
: "${PR_NUMBER:?Missing PR_NUMBER}"

# GITHUB_OUTPUT がない環境用の保険（例：ローカル実行時）
GITHUB_OUTPUT=${GITHUB_OUTPUT:-/dev/null}

# 試行回数 30回 * 間隔 20秒 = 合計監視時間 10分
MAX_ATTEMPTS=30
INTERVAL=20
TOTAL_WAIT_MINUTES=$((MAX_ATTEMPTS * INTERVAL / 60))

echo "🔁 Polling up to $TOTAL_WAIT_MINUTES min ($MAX_ATTEMPTS attempts, ${INTERVAL}s interval)"

for (( i=1; i<=MAX_ATTEMPTS; i++ )); do
  echo "⏳ Polling attempt $i/$MAX_ATTEMPTS..."

  # PR 情報取得
  if ! PR_DATA=$(gh api "/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}"); then
    echo "❌ Failed to fetch PR data" >&2
    echo "ci_passed=false" >> "$GITHUB_OUTPUT"
    exit 1
  fi

  HEAD_SHA=$(echo "$PR_DATA" | jq -r .head.sha)

  # ワークフロー実行取得（最新50件）
  if ! RUNS_DATA=$(gh api "/repos/${GITHUB_REPOSITORY}/actions/runs?per_page=50"); then
    echo "❌ Failed to fetch workflow runs" >&2
    echo "ci_passed=false" >> "$GITHUB_OUTPUT"
    exit 1
  fi

  # 対象のワークフロー抽出
  FILTERED_RUNS=$(echo "$RUNS_DATA" | jq -c \
  --arg HEAD_SHA "$HEAD_SHA" '
    .workflow_runs | map(select(.head_sha == $HEAD_SHA))
  ')
  # # ワークフロー実行がない場合
  if [ "$(echo "$FILTERED_RUNS" | jq length)" -eq 0 ]; then
    echo "⚠️ No workflow runs found for this commit."
  else
    echo "$FILTERED_RUNS" | jq -r '.[] | "[WORKFLOW] \(.name): \(.status) / \(.conclusion)"'
  fi

  # 終了/成功判定
  COMPLETED=$(echo "$FILTERED_RUNS" | jq 'map(.status == "completed") | all')
  SUCCESSFUL=$(echo "$FILTERED_RUNS" | jq 'map(.conclusion == "success") | all')

  if [[ "$COMPLETED" == "true" ]]; then
    if [[ "$SUCCESSFUL" == "true" ]]; then
      # 全てのCIチェックが成功
      echo "✅ All CI checks passed!"
      echo "ci_passed=true" >> "$GITHUB_OUTPUT"
    else
      # いずれかのCIチェックが失敗
      echo "❌ Some CI checks failed!"
      echo "ci_passed=false" >> "$GITHUB_OUTPUT"
    fi
    exit 0
  fi

  sleep "$INTERVAL"
done

# タイムアウト
echo "❌ CI polling timed out"
echo "ci_passed=false" >> "$GITHUB_OUTPUT"
exit 0
