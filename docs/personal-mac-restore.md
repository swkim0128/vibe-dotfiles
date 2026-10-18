# 개인 Mac 추가 도구와 주간 예약 복원

## 문서 → Markdown

uv가 설치된 환경에서 다음을 각각 실행한다. 10/18 확인 버전은 MarkItDown 0.1.8·Marker 2.0.0이며, 아래 명령은 최신 버전을 설치한다. 설치 정책과 용도 정본은 vibe-ai-config의 `shared/sops/sop_development_tools.md`다.

```bash
uv tool install "markitdown[pdf,docx,pptx,xlsx]"
uv tool install marker-pdf
```

`~/.local/bin`을 PATH에 포함한다. MarkItDown은 Office·HTML·빠른 텍스트 추출, Marker는 PDF 표·제목 구조 보존에 사용한다. Marker 첫 실행에는 모델 다운로드와 추가 저장공간이 필요하다. Graphify는 사용자 결정으로 제거했으므로 복원하지 않는다.

## 개인 주간 정리 — Codex, 일요일 22:00

정본은 `vibe-tools/personal_weekly_worker.sh`와 `vibe-tools/com.swkim0128.personal-weekly.plist`다. `install.sh`는 LaunchAgent를 등록하지 않는다. plist는 개인컴 `/Users/eunsol/Project/vibe-dotfiles` 경로를 포함하므로 다른 Mac에서는 복사한 plist의 워커·로그 경로와 HOME을 대상 사용자 값으로 바꾼다. PARA 경로가 `$HOME/Project/para`와 다르면 `EnvironmentVariables.PARA_VAULT`도 지정한다.

사전 조건: Codex CLI 설치·로그인, vibe-ai-config 개인 프로필 배포, `~/.agents/skills/notion-weekly-retrospective/SKILL.md`, Notion MCP OAuth 및 회고 쓰기 도구 승인 설정. 인증정보는 각 Mac에서 연결하며 복사·커밋하지 않는다. 워커는 `codex exec`·`gpt-6.1-sol`·medium·read-only로 실행하며 Notion KPT 회고만 작성한다.

같은 개인컴 경로로 복원할 때 아래 명령을 각각 실행한다. 이미 등록된 경우 먼저 `launchctl bootout gui/$(id -u)/com.swkim0128.personal-weekly`로 기존 등록을 해제한다.

```bash
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/personal-weekly"
cp "$HOME/Project/vibe-dotfiles/vibe-tools/com.swkim0128.personal-weekly.plist" "$HOME/Library/LaunchAgents/"
plutil -lint "$HOME/Library/LaunchAgents/com.swkim0128.personal-weekly.plist"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.swkim0128.personal-weekly.plist"
launchctl print "gui/$(id -u)/com.swkim0128.personal-weekly"
```

실행 결과는 `~/Library/Logs/personal-weekly/YYYY-MM-DD.md`와 `.log`, 노션 해당 주 페이지의 KPT 회고에서 확인한다.
