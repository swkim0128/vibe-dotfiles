# 공용 환경변수 — ~/.zshenv 에서 source 되어 비대화형 셸(에이전트·스크립트)에도 적용된다.

# OpenSpec 익명 텔레메트리 끄기 (명령명·버전·UUID 전송 차단).
export OPENSPEC_TELEMETRY=0
# DO_NOT_TRACK 은 여러 CLI 가 따르는 표준 옵트아웃 변수라 다른 도구의 텔레메트리도 함께 꺼진다.
export DO_NOT_TRACK=1
