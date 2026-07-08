#!/bin/bash
# 目的: 各ターンの冒頭に現在日時を AI のコンテキストに注入する
# 関連: CLAUDE.md「人間的な生活のために」セクション
# 前提: UserPromptSubmit hook として登録

CURRENT_TIME=$(date '+%H:%M')
CURRENT_DATE=$(date '+%Y-%m-%d (%a)')

jq -nc --arg ctx "現在日時: ${CURRENT_DATE} ${CURRENT_TIME}" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
