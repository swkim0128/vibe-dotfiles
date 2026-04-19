---
name: update-vibe-script-files
description: Use when asked to add, edit, or remove entries in vibe-tools data files (commands, prompts, sessionizer paths). Each file has a different format and conventions that must be read first before updating.
---

# Update Vibe Script Files

## Overview

vibe-tools 스크립트들은 각자 데이터 파일을 읽어 동작한다. 업데이트 전에 반드시 해당 파일을 먼저 읽어 형식과 관행을 파악한 후 일관되게 추가한다.

## 파일별 스크립트 매핑

| 요청 키워드 | 데이터 파일 | 사용 스크립트 |
|------------|-----------|--------------|
| 명령어 추가, tools 메뉴, Ctrl+F | `commands.txt` | `my-tools.sh` |
| 프롬프트 추가, Claude 프롬프트 | `prompts/*.txt` | `claude-skills.sh` |
| 프로젝트 경로, sessionizer | `sessionizer-paths.txt` | `vibe.sh` / `tmux-sessionizer.sh` |

**파일 위치**: `~/Project/vibe-dotfiles/vibe-tools/` (심볼릭 링크 → `~/.config/vibe-tools/`)

## 워크플로우

```
1. 해당 데이터 파일(또는 디렉토리) 읽기
2. 형식·섹션·명명 규칙 파악
3. 기존 항목과 일관된 형식으로 추가/수정
```

**파일을 읽기 전에 수정하지 않는다.**

---

## commands.txt

**형식**: `이모지 레이블 | 실행명령어`  
**섹션 구분**: `# ── 섹션명 ──────`  
**주석/빈줄**: fzf에서 자동 제외

```
# ── Git ─────────────────────────────────────────────
🌿 브랜치 목록 확인 | git branch -a
📤 현재 브랜치 푸시 | git push origin HEAD
```

**추가 시 확인사항**: 기존 섹션에 포함되는지, 새 섹션이 필요한지, 이모지 스타일 일치 여부

---

## prompts/ 디렉토리

**형식**: 파일명 = `숫자_프롬프트명.txt` (예: `01_상세_코드리뷰.txt`)  
**내용**: 파일 전체가 Claude에게 전송될 프롬프트 텍스트

```bash
# 추가 시: 기존 번호 목록 확인 후 다음 번호로 생성
ls ~/.config/vibe-tools/prompts/
```

**추가 시 확인사항**: 기존 파일 번호 목록, 프롬프트 내용의 목적/범위

---

## sessionizer-paths.txt

**형식**: 한 줄에 경로 하나, `~` 사용 가능  
**주석**: `#` 줄은 무시

```
~/project
~/work
~/Project/para
```

**추가 시 확인사항**: 경로가 실제 존재하는지, 중복 여부

---

## 변경 후 적용

```bash
# commands.txt, sessionizer-paths.txt → 즉시 반영 (다음 실행 시 자동 로드)
# prompts/ 파일 추가 → 즉시 반영
# aliases.zsh 변경 시
source ~/.zshrc
```
