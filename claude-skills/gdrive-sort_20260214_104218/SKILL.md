---
name: gdrive-sort
description: "Google Drive에서 동기화된 마크다운 파일을 PARA 구조의 적절한 위치로 분류하여 이동합니다. 'gdrive 정리', 'gdrive 분류', '구글 드라이브 문서 정리', '동기화된 문서 분류' 등의 요청에 사용하세요. gdrive 폴더에 새 파일이 있을 때마다 이 스킬을 사용하면 됩니다."
---

# Google Drive 동기화 문서 분류 스킬

## 개요

`sync-gdrive.sh` 스크립트로 Google Drive(NotebookLM 등)에서 동기화된 마크다운 파일들이 `para/gdrive/` 폴더에 쌓입니다. 이 스킬은 각 파일의 내용을 읽고, PARA 볼트의 `03.Resources/` 하위 카테고리 중 가장 적합한 곳으로 분류하여 이동합니다.

분류가 애매한 파일은 사용자에게 확인을 받고, 어디에도 맞지 않으면 `99.Unsorted/`에 넣습니다.

## 워크플로우

### 1단계: gdrive 폴더 스캔

```
경로: para/gdrive/
```

이 폴더의 마크다운 파일(.md) 목록을 확인합니다. 파일이 없으면 "정리할 파일이 없습니다"라고 안내하고 종료합니다.

### 2단계: 리소스 카테고리 맵 확인

`03.Resources/` 하위 폴더 목록을 읽어서 현재 존재하는 카테고리를 파악합니다. 아래는 기본 매핑 테이블이지만, 실제 폴더 목록을 우선 참조하세요.

| 카테고리 폴더 | 키워드/주제 |
|-------------|----------|
| 01.Algorithm | 알고리즘, 자료구조, 정렬, 탐색, DP, 그래프 |
| 02.graphql | GraphQL, 쿼리, 뮤테이션, 스키마 |
| 03.JavaScript | JavaScript, JS, ES6, Node.js, V8 |
| 04.Kotlin | Kotlin, 코틀린, 코루틴 |
| 05.Kubernetes | Kubernetes, K8s, 쿠버네티스, Pod, Deployment |
| 06.MacOS | macOS, Mac, Homebrew |
| 07.MCP | MCP, Model Context Protocol |
| 08.Next.js | Next.js, SSR, SSG, App Router |
| 09.React | React, 리액트, 컴포넌트, 훅, JSX |
| 10.TypeScript | TypeScript, TS, 타입, 인터페이스 |
| 11.Vim | Vim, Neovim, 에디터 |
| 13.Git | Git, GitHub, 브랜치, 커밋 |
| 14.Java | Java, JVM, JDK |
| 15.Linux | Linux, 리눅스, 쉘, Bash, Ubuntu |
| 17.Python | Python, 파이썬, pip, Django |
| 18.PHP | PHP, Laravel |
| 19.Spring | Spring, SpringBoot, IoC, DI, AOP, JPA, MVC |
| 20.Web | HTTP, REST, API, 웹, 브라우저, CSS, HTML, 아키텍처 패턴(CQRS, Saga, Outbox 등) |
| 21.Tools | 개발 도구, IDE, Docker, CI/CD |
| 23.CS-Fundamentals | 운영체제, 네트워크, 컴퓨터 구조, 자료구조 이론 |
| 24.Database | DB, SQL, NoSQL, 인덱스, 튜닝, RDBMS |
| ShellScript | 쉘 스크립트, Bash 스크립트 |
| 99.Unsorted | 위 카테고리에 맞지 않는 파일 |

### 3단계: 파일별 분류

각 파일에 대해:

1. **파일명 분석**: 제목에서 주제 키워드를 추출
2. **내용 읽기**: 파일 앞부분(약 50줄)을 읽어 핵심 주제를 파악
3. **카테고리 결정**: 매핑 테이블과 대조하여 가장 적합한 카테고리 선택

분류 기준 우선순위:
- 파일 내용에서 다루는 핵심 기술/주제가 무엇인지가 가장 중요
- 파일명의 키워드는 보조 참고
- 여러 주제가 섞여 있으면 가장 비중이 큰 주제의 카테고리로 분류
- 아키텍처 패턴(CQRS, Event Sourcing, Saga, Outbox 등)은 `20.Web`으로 분류
- 특정 프레임워크에 종속된 내용이면 해당 프레임워크 카테고리 우선 (예: Spring + CQRS → `19.Spring`)

### 4단계: 사용자 확인

분류 결과를 테이블로 보여줍니다:

```
| 파일명 | 분류 카테고리 | 이유 |
|--------|-------------|------|
| CQRS 패턴의 핵심 원리.md | 20.Web | 아키텍처 패턴 |
| Spring Security 설정.md | 19.Spring | Spring 프레임워크 |
```

사용자가 수정할 수 있게 "이대로 진행할까요? 변경할 항목이 있으면 알려주세요."라고 안내합니다.

### 5단계: 파일 이동

사용자 승인 후 각 파일을 해당 카테고리 폴더로 이동합니다:

```bash
mv "para/gdrive/파일명.md" "para/03.Resources/카테고리/파일명.md"
```

이동 완료 후 결과를 요약합니다.

### 6단계: gdrive 폴더 정리 확인

모든 파일 이동이 끝나면 gdrive 폴더에 남은 파일이 있는지 확인하고 결과를 보고합니다.

## 에러 처리

- 동일한 파일명이 대상 폴더에 이미 존재하면 사용자에게 덮어쓰기/이름변경/건너뛰기 선택을 요청
- gdrive 폴더가 비어있으면 안내 메시지 후 종료
- 03.Resources에 적합한 카테고리가 없으면 99.Unsorted로 이동

## 사용 예시

```
사용자: "gdrive 정리해줘"
→ gdrive 폴더 스캔
→ 6개 파일 발견, 내용 분석
→ 분류 결과 테이블 제시
→ 사용자 확인 후 이동 실행
→ 완료 보고
```

```
사용자: "구글 드라이브에서 가져온 문서 분류해줘"
→ 동일 워크플로우 실행
```
