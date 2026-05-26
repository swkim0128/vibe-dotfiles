#!/usr/bin/env bats
# multi_dispatch.bats — multi-dispatch 스킬 동작 검증 스캐폴드
#
# vibe-claude-plugin/plugins/task-mgmt/skills/multi-dispatch/ 의 동작을
# 행위적으로 검증하기 위한 bats 케이스. 현 단계는 스캐폴드 (skip).
#
# 검증 대상 (5섹션 5.3 항목과 1:1 매핑):
#   1. 인자 파싱 — Plane 이슈 / PARA 노트 / 자유텍스트 분류
#   2. --dry-run — 상태 디렉토리 / manifest 생성 + 디스패치 차단
#   3. 디스패치 — 인자별 1개 백그라운드 Agent
#   4. 콜백 폴링 — status.json 수집 + 타임아웃
#   5. 종합 보고 — ✅/⚠️/❌/🔒 포맷
#
# 사용:
#   bats tests/bats/multi_dispatch.bats
# 또는 bats 미설치 시 폴백:
#   bash -n tests/bats/multi_dispatch.bats

# ── 1. 인자 파싱 ─────────────────────────────────────────────────────────────

@test "arg parser: Plane 이슈 ID (DWDEV-4289) → plane_issue 로 분류" {
  skip "scaffold"
}

@test "arg parser: 절대경로 .md → para_note 로 분류" {
  skip "scaffold"
}

@test "arg parser: @세션명 접두 자유텍스트 → freetext + session_hint 추출" {
  skip "scaffold"
}

# ── 2. --dry-run ──────────────────────────────────────────────────────────────

@test "dry-run: STATE_DIR 와 manifest.json 만 생성, 서브 디렉토리 없음" {
  skip "scaffold"
}

@test "dry-run: Agent 디스패치 호출 0회" {
  skip "scaffold"
}

# ── 3. 디스패치 ────────────────────────────────────────────────────────────────

@test "dispatch: 인자 3개 → status.json 3개 queued 상태로 초기화" {
  skip "scaffold"
}

@test "dispatch: 동일 raw 인자 중복 → 중복 분 무시" {
  skip "scaffold"
}

@test "dispatch: 인자 7개 → 앞 6개만 처리하고 7번째는 누락 보고" {
  skip "scaffold"
}

# ── 4. 콜백 폴링 ──────────────────────────────────────────────────────────────

@test "polling: 모든 status=done 되면 즉시 종합 보고로 진행" {
  skip "scaffold"
}

@test "polling: 60분 타임아웃 도달 시 미완료 작업은 ❌ 로 표시" {
  skip "scaffold"
}

# ── 5. 종합 보고 ──────────────────────────────────────────────────────────────

@test "report: 4종 상태(done/warn/failed/escalated) → ✅/⚠️/❌/🔒 이모지 매핑" {
  skip "scaffold"
}
