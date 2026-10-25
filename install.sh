#!/bin/bash
# install.sh [work|personal] [--dry-run]
set -euo pipefail
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_FILE="$HOME/.config/vibe-dotfiles/profile"
SAVED_PROFILE=""
if [[ -f "$PROFILE_FILE" ]]; then
  SAVED_PROFILE="$(<"$PROFILE_FILE")"
elif [[ -f "$HOME/.config/vibe-ai-config/profile" ]]; then
  SAVED_PROFILE="$(<"$HOME/.config/vibe-ai-config/profile")"
fi
MODE="${1:-${SAVED_PROFILE:-personal}}"
case "$MODE" in
  work|personal) ;;
  -h|--help) echo "Usage: $0 [work|personal] [--dry-run]"; exit 0 ;;
  *) echo "알 수 없는 프로필: $MODE" >&2; exit 2 ;;
esac
if [[ -n "$SAVED_PROFILE" && "$MODE" != "$SAVED_PROFILE" && "${VIBE_PROFILE_SWITCH:-0}" != 1 ]]; then
  echo "머신 프로필은 $SAVED_PROFILE 입니다. 대신 실행: $0 $SAVED_PROFILE" >&2
  exit 2
fi
if [[ -n "${2:-}" && "${2:-}" != --dry-run ]]; then
  echo "지원하지 않는 옵션: $2" >&2
  exit 2
fi
# shellcheck source=manifests/common.conf
source "$DOTFILES/manifests/common.conf"
# shellcheck source=/dev/null
source "$DOTFILES/profiles/$MODE.conf"
# shellcheck source=lib/install-steps.sh
source "$DOTFILES/lib/install-steps.sh"
for step in "${INSTALL_STEPS[@]}"; do
  if ! declare -F "install_$step" >/dev/null; then
    echo "알 수 없는 설치 단계: $step" >&2
    exit 2
  fi
done
for manifest in "${BREW_FILES[@]}" "${NPM_FILES[@]}" "${UV_FILES[@]}"; do
  if [[ ! -f "$DOTFILES/$manifest" ]]; then
    echo "설치 목록 없음: $DOTFILES/$manifest" >&2
    exit 2
  fi
done
if [[ "${2:-}" == --dry-run ]]; then
  printf '프로필: %s\n' "$MODE"
  printf '단계: %s\n' "${INSTALL_STEPS[@]}"
  printf '패키지 목록: %s\n' "${BREW_FILES[@]}" "${NPM_FILES[@]}" "${UV_FILES[@]}"
  printf '설정 링크: %s\n' "${CONFIG_LINKS[@]}"
  exit 0
fi
mkdir -p "$(dirname "$PROFILE_FILE")"
printf '%s\n' "$MODE" > "$PROFILE_FILE"
for step in "${INSTALL_STEPS[@]}"; do
  "install_$step"
done

# ── 완료 ──────────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  ✅ Vibe Coding 환경 세팅이 완료되었습니다!"
echo "============================================================"
echo ""
echo "  다음 명령어로 alias를 즉시 적용하세요:"
echo "    source ~/.zshrc"
echo ""
echo "  Neovim 첫 실행 전 NvChad가 설치되어 있어야 합니다:"
echo "    git clone https://github.com/NvChad/starter ~/.config/nvim && nvim"
echo ""
