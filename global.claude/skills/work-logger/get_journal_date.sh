#!/bin/bash
# 目的: journals 記録用の日付を返す（午前3時までは前日の日付）
# 関連: work-logger スキル
# 前提: GNU date

hour=$(date +%H)
if [ "$hour" -lt 3 ]; then
    date -d "yesterday" +%Y-%m-%d
else
    date +%Y-%m-%d
fi
