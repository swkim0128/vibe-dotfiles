#!/usr/bin/env bash
# git-auto-commit.sh — 공통 git auto-commit/push 라이브러리
#
# 사용법: source 후 함수 호출
#   source "$HOME/.config/vibe-tools/git-auto-commit.sh"
#   git_auto_commit_push <repo_dir> <commit_msg> [add_pattern]
#
# 또는 단계별 사용:
#   git_has_changes <repo>          (변경 있으면 0, 없으면 1)
#   git_safe_add <repo> [pattern]   (-A 또는 ':!exclude' 등 — 기본 -A)
#   git_has_staged <repo>           (stage된 변경 있으면 0)
#   git_commit_push <repo> <msg>    (commit + push, 실패 시 stderr 보고)
#
# 환경변수:
#   AUTO_GIT_PUSH=off               전체 비활성 (모든 헬퍼가 silent skip)
#   AUTO_GIT_PUSH_QUIET=1           성공 시 메시지 미출력 (실패만 보고)
#   AUTO_GIT_PUSH_DRY_RUN=1         실제 commit/push 안 하고 echo만
#
# 직접 실행 시: 사용법 출력 후 종료.

# ── 직접 실행 방지 (sourced로만 사용) ──────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cat <<'EOF'
git-auto-commit.sh — 공통 git auto-commit/push 라이브러리

본 스크립트는 source로만 사용하세요:

  source "$HOME/.config/vibe-tools/git-auto-commit.sh"
  git_auto_commit_push "/path/to/repo" "commit message" [add_pattern]

함수:
  git_has_changes <repo>           변경 감지 (0=있음, 1=없음)
  git_safe_add <repo> [pattern]    add (기본 -A)
  git_has_staged <repo>            stage 감지
  git_commit_push <repo> <msg>     commit + push
  git_auto_commit_push <repo> <msg> [pattern]   통합 (변경→add→commit→push)

환경변수:
  AUTO_GIT_PUSH=off              전체 비활성
  AUTO_GIT_PUSH_QUIET=1          성공 메시지 미출력
  AUTO_GIT_PUSH_DRY_RUN=1        commit/push 미실행 (echo만)
EOF
    exit 0
fi

# ── 헬퍼 ────────────────────────────────────────────────────────────────────

# 변경 있음(working tree dirty 또는 untracked) → 0, 없음 → 1
git_has_changes() {
    local repo="$1"
    [[ -d "$repo/.git" ]] || return 1

    if ! git -C "$repo" diff --quiet HEAD 2>/dev/null; then
        return 0
    fi
    if [[ -n "$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        return 0
    fi
    return 1
}

# git add (기본 -A. 패턴 지정 가능: ':!plugins', 'specific/file.json' 등)
git_safe_add() {
    local repo="$1"
    local pattern="${2:--A}"

    [[ -d "$repo/.git" ]] || return 1

    if [[ "$pattern" == "-A" ]]; then
        git -C "$repo" add -A 2>/dev/null || return 1
    else
        # pathspec 형태(콜론 시작) 또는 일반 path
        git -C "$repo" add "$pattern" 2>/dev/null || return 1
    fi
}

# stage된 변경 있음 → 0, 없음 → 1
git_has_staged() {
    local repo="$1"
    [[ -d "$repo/.git" ]] || return 1
    git -C "$repo" diff --cached --quiet 2>/dev/null && return 1 || return 0
}

# commit + push. 성공 0 / commit 실패 1 / push 실패 2
git_commit_push() {
    local repo="$1"
    local msg="$2"
    local base
    base="$(basename "$repo")"

    [[ -d "$repo/.git" ]] || return 1

    if [[ "${AUTO_GIT_PUSH_DRY_RUN:-0}" == "1" ]]; then
        echo "🧪 [dry-run] $base: would commit \"$msg\" + push" >&2
        return 0
    fi

    if ! git -C "$repo" commit -m "$msg" >/dev/null 2>&1; then
        echo "⚠️  [git-auto-commit] $base: commit 실패" >&2
        return 1
    fi

    if ! git -C "$repo" push >/dev/null 2>&1; then
        echo "⚠️  [git-auto-commit] $base: push 실패 — 수동으로 확인 필요" >&2
        return 2
    fi

    if [[ "${AUTO_GIT_PUSH_QUIET:-0}" != "1" ]]; then
        echo "✅ [git-auto-commit] $base: $msg" >&2
    fi
    return 0
}

# 통합: 변경 감지 → add → stage 감지 → commit → push
# 사용: git_auto_commit_push <repo> <msg> [add_pattern]
git_auto_commit_push() {
    local repo="$1"
    local msg="$2"
    local pattern="${3:--A}"

    if [[ "${AUTO_GIT_PUSH:-on}" == "off" ]]; then
        return 0
    fi

    git_has_changes "$repo" || return 0
    git_safe_add "$repo" "$pattern" || return 1
    git_has_staged "$repo" || return 0
    git_commit_push "$repo" "$msg"
}

# 변경된 top-level 디렉토리 목록을 의미 단위로 반환 (메시지 생성용)
# 사용: dirs=$(git_changed_dirs <repo>); echo "$dirs"
git_changed_dirs() {
    local repo="$1"
    [[ -d "$repo/.git" ]] || return 1

    git -C "$repo" diff --cached --name-only 2>/dev/null \
        | awk -F/ '{print $1}' \
        | sort -u \
        | grep -v '^$' \
        | head -5 \
        | paste -sd ', ' -
}

# stage된 파일 수 반환
git_staged_count() {
    local repo="$1"
    [[ -d "$repo/.git" ]] || { echo 0; return 1; }
    git -C "$repo" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' '
}

# 표준 메시지 생성기: "chore(auto): {dirs} updated ({N} files) [timestamp]"
# 사용: msg=$(git_auto_message <repo>)
git_auto_message() {
    local repo="$1"
    local dirs file_count timestamp
    dirs="$(git_changed_dirs "$repo")"
    [[ -z "$dirs" ]] && dirs="(misc)"
    file_count="$(git_staged_count "$repo")"
    timestamp="$(date '+%Y-%m-%d %H:%M')"
    echo "chore(auto): ${dirs} updated (${file_count} files) [${timestamp}]"
}
