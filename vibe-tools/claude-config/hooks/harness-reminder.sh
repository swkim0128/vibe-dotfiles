#!/bin/bash
# UserPromptSubmit hook — harness pipeline reminder injected into context
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[하네스 규칙] 코드 수정/생성 요청이라면 반드시 GROUND(플랜 수립) → APPLY(원자적 구현) → VERIFY(검증) → ADAPT(실패 추적) 순서를 따르세요. 동일 오류 3회 시 즉시 중단 후 브리핑."}}\n'
