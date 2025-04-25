#!/bin/bash

set -euo pipefail

echo "🧠 Running check-all-ci-success script..."

# 必須環境変数の確認
: "${IGNORED_WORKFLOW:?Missing IGNORED_WORKFLOW}"
: "${PR_NUMBER:?Missing PR_NUMBER}"
: "${APP_TOKEN:?Missing APP_TOKEN}"

# GITHUB_OUTPUT がない環境用の保険（例：ローカル実行時）
GITHUB_OUTPUT=${GITHUB_OUTPUT:-/dev/null}

MAX_ATTEMPTS=30
INTERVAL=20
TOTAL_WAIT_MINUTES=$((MAX_ATTEMPTS * INTERVAL / 60))

echo "🔁 Polling up to $TOTAL_WAIT_MINUTES min ($MAX_ATTEMPTS attempts, ${INTERVAL}s interval)"

for (( i=1; i<=MAX_ATTEMPTS; i++ )); do
  echo "⏳ Polling attempt $i/$MAX_ATTEMPTS..."

  # PR 情報取得
  if ! PR_DATA=$(gh api -H "Authorization: token $APP_TOKEN" \
      "/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}"); then
    echo "❌ Failed to fetch PR data" >&2
    echo "ci_passed=false" >> "$GITHUB_OUTPUT"
    exit 1
  fi

  HEAD_SHA=$(echo "$PR_DATA" | jq -r .head.sha)

  # ワークフロー実行取得（最新50件）
  if ! RUNS_DATA=$(gh api -H "Authorization: token $APP_TOKEN" \
      "/repos/${GITHUB_REPOSITORY}/actions/runs?per_page=50"); then
    echo "❌ Failed to fetch workflow runs" >&2
    echo "ci_passed=false" >> "$GITHUB_OUTPUT"
    exit 1
  fi

  # 対象のワークフロー抽出（自分以外）
  FILTERED_RUNS=$(echo "$RUNS_DATA" | jq -c \
    --arg HEAD_SHA "$HEAD_SHA" \
    --arg IGNORED "$IGNORED_WORKFLOW" '
      .workflow_runs | map(select(.head_sha == $HEAD_SHA and .name != $IGNORED))
    ')

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
      echo "✅ All CIs passed!"
      echo "ci_passed=true" >> "$GITHUB_OUTPUT"
    else
      echo "❌ Some CI checks failed!"
      echo "ci_passed=false" >> "$GITHUB_OUTPUT"
    fi
    exit 0
  fi

  sleep "$INTERVAL"
done

echo "❌ CI polling timed out"
echo "ci_passed=false" >> "$GITHUB_OUTPUT"
exit 1
