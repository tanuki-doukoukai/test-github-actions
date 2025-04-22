#!/bin/bash

# ========= 🔧 設定 =========
APP_ID="1224231"
PRIVATE_KEY_PATH="./github-app.pem"
REPO_URL="https://github.com/tanuki-doukoukai/test-github-actions.git"
BRANCH_NAME="test-app-push"
TARGET_FILE="push-test-$(date +%s).txt"
# ===========================

set -e

echo "🔐 Generating JWT..."
NOW=$(date +%s)
EXP=$(($NOW + 600))

HEADER_BASE64=$(echo -n '{"alg":"RS256","typ":"JWT"}' | openssl base64 -e | tr -d '=' | tr '/+' '_-' | tr -d '\n')
PAYLOAD_BASE64=$(echo -n "{\"iat\":$NOW,\"exp\":$EXP,\"iss\":$APP_ID}" | openssl base64 -e | tr -d '=' | tr '/+' '_-' | tr -d '\n')
SIGNATURE=$(echo -n "$HEADER_BASE64.$PAYLOAD_BASE64" | openssl dgst -sha256 -sign "$PRIVATE_KEY_PATH" | openssl base64 -e | tr -d '=' | tr '/+' '_-' | tr -d '\n')
JWT="$HEADER_BASE64.$PAYLOAD_BASE64.$SIGNATURE"

echo "✅ JWT created."

echo "🔍 Getting GitHub App info..."
APP_INFO=$(curl -s -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/app)

APP_NAME=$(echo "$APP_INFO" | jq -r '.name')
APP_SLUG=$(echo "$APP_INFO" | jq -r '.slug')
APP_NODE_ID=$(echo "$APP_INFO" | jq -r '.node_id')

echo "✅ GitHub App Info:"
echo "🔹 App Name  : $APP_NAME"
echo "🔹 App Slug  : $APP_SLUG"
echo "🔹 Node ID   : $APP_NODE_ID"
echo ""

echo "📦 Getting installation ID..."
INSTALLATION_ID=$(curl -s -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/app/installations | jq '.[0].id')

echo "✅ INSTALLATION_ID: $INSTALLATION_ID"

echo "🔑 Generating GitHub App token..."
ACCESS_TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens | jq -r '.token')

echo "✅ Access token obtained."

echo "📂 Cloning repository..."
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git clone "$REPO_URL" repo
cd repo

echo "🔀 Checking out branch: $BRANCH_NAME"
git checkout -b "$BRANCH_NAME" origin/"$BRANCH_NAME" || git checkout -b "$BRANCH_NAME"

echo "🔁 Rebasing to avoid non-fast-forward..."
git fetch origin "$BRANCH_NAME" || true
git rebase origin/"$BRANCH_NAME" || echo "🔸 Nothing to rebase"

echo "📝 Committing test file..."
echo "test push via GitHub App at $(date)" > "$TARGET_FILE"
git add "$TARGET_FILE"
git commit -m "test: push via GitHub App token (protection test)"

echo "🔁 Setting remote URL with access token..."
REPO_CLEAN_URL=$(echo "$REPO_URL" | sed -E 's#https://github.com/##')
git remote set-url origin https://x-access-token:$ACCESS_TOKEN@github.com/$REPO_CLEAN_URL

echo "🚀 Pushing to remote branch (no -f)..."
git push origin "$BRANCH_NAME"

echo "✅ Push complete! Branch: $BRANCH_NAME"
