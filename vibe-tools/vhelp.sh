#!/bin/bash
# vhelp: Vibe 치트시트 뷰어
# tmux 환경: 현재 윈도우 중앙에 팝업으로 표시
# tmux 팝업 내부: 팝업 닫힌 후 새 팝업으로 표시
# 일반 환경: 터미널에서 직접 표시

CHEATSHEET="$HOME/.config/vibe-tools/cheatsheet.md"

if [ -n "$TMUX" ]; then
    if [ -n "$VIBE_IN_POPUP" ]; then
        (sleep 0.3 && tmux display-popup -E -w 90% -h 90% -T " Vibe Cheat Sheet " "nvim -R '$CHEATSHEET'") &
        disown $!
    else
        tmux display-popup -E -w 90% -h 90% -T " Vibe Cheat Sheet " "nvim -R '$CHEATSHEET'"
    fi
else
    nvim -R "$CHEATSHEET"
fi
