#!/bin/bash
# tmux를 거치지 않고 macOS 시스템에 직접 알림을 띄웁니다.
osascript -e 'display notification "Claude가 작업을 마치고 응답을 기다리고 있습니다." with title "Claude Code"'
