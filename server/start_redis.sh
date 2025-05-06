#!/bin/bash

# Redis 서버 살아있는지 확인
if redis-cli ping | grep -q PONG; then
  echo "✅ Redis 이미 실행 중입니다."
else
  echo "🔵 Redis 실행 시작..."
  sudo systemctl start redis
  sleep 2
  if redis-cli ping | grep -q PONG; then
    echo "✅ Redis 정상 실행 완료!"
  else
    echo "❌ Redis 실행 실패. 직접 확인 필요."
  fi
fi
