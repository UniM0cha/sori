# Sori

macOS 메뉴 막대 받아쓰기 앱. 전역 단축키로 음성을 녹음하고 Apple Silicon의 GPU로 곧바로 전사해 커서 위치에 붙여넣습니다. 네트워크는 첫 실행 모델 다운로드 외에는 쓰지 않습니다.

## 주요 기능

- **전역 단축키** — 기본 `Option + Space`. 눌러서 녹음 시작, 다시 눌러 종료.
- **온디바이스 전사** — Qwen3-ASR 1.7B 모델을 MLX(Metal GPU)로 실행. 음성 데이터가 Mac을 떠나지 않습니다.
- **클립보드 + 자동 붙여넣기** — 전사 결과를 클립보드에 남기면서 동시에 활성 앱의 커서 위치에 바로 붙여넣기.
- **히스토리** — 최근 전사 1,000개를 메뉴 막대 드롭다운에서 검색·재사용. 좌클릭은 재붙여넣기, 우클릭은 복사/삭제/원본 열기 컨텍스트 메뉴.
- **파일 전사 큐** — 기존 오디오 파일(wav, mp3, m4a, aac, flac, aiff 등)을 선택하면 백그라운드로 전사해 히스토리와 원본 옆 `.txt`에 함께 저장.
- **모델 메모리 자동 관리** — 기본 5분 유휴 시 모델을 언로드하고 다음 전사 요청 시 자동으로 다시 로드. 설정에서 1/5/10/30분/무제한 중 선택 가능.
- **ESC 취소** — 녹음 중 또는 전사 대기 중 ESC로 즉시 취소.

## 요구사항

- macOS 15 (Sequoia) 이상
- Apple Silicon (M1 이상)
- 약 3.4 GB 디스크 공간 — 기본 모델 `Qwen3-ASR-1.7B-bf16` 기준. 설정에서 더 작은 양자화 버전(8bit/6bit/4bit, 0.6B 계열)을 선택할 수 있습니다.
- Xcode 16 이상 (소스 빌드 시)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`.xcodeproj` 재생성 시)

## 설치 (소스 빌드)

```bash
git clone git@github.com:UniM0cha/sori.git
cd sori
brew install xcodegen    # 최초 1회
xcodegen generate
open Sori.xcodeproj
```

Xcode에서 ⌘R로 실행하면 Welcome 창이 떠서 다음을 안내합니다.

1. 마이크 권한 허용
2. 손쉬운 사용(Accessibility) 권한 허용 — 전사 텍스트를 다른 앱에 붙여넣기 위해 필수
3. 기본 모델 다운로드 (~3.4 GB, 한 번만)

## 사용법

| 동작 | 입력 |
|---|---|
| 녹음 시작 / 종료 | ⌥Space |
| 녹음 또는 전사 취소 | ESC |
| 히스토리 항목 즉시 붙여넣기 | 드롭다운 항목 좌클릭 |
| 복사만 / 삭제 / 원본 파일 열기 | 드롭다운 항목 우클릭 |
| 오디오 파일 전사 | 메뉴 막대 → "파일 전사…" |
| 설정 창 열기 | ⌘, |

녹음 중에는 메뉴 막대 아이콘이 깜빡여서 현재 상태를 표시합니다.

## 설정

메뉴 막대 → **설정**

- **일반** — 단축키 재바인딩
- **모델** — 양자화 선택(bf16 / 8bit / 6bit / 4bit / 0.6B 계열), 유휴 언로드 시간, 앱 시작 시 미리 로드 토글, 전사 언어(자동/한국어/영어/일본어/중국어), 자주 쓰는 단어 사전
- **히스토리** — 보존 기간(무제한/30일/7일/1일), 최대 개수

"앱 시작 시 모델 미리 로드"를 켜면 첫 녹음 지연이 사라지지만, 앱 실행 직후 ~4 GB 메모리가 점유됩니다. 기본값은 꺼짐(lazy)입니다.

## 기술 스택

| 계층 | 선택 |
|---|---|
| 언어 | Swift 6, SwiftUI + AppKit 혼합 |
| ASR 모델 | [`mlx-community/Qwen3-ASR-1.7B-bf16`](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-bf16) |
| 추론 | [MLX Swift ASR](https://github.com/ontypehq/mlx-swift-asr) (Apple GPU, Metal) |
| 전역 단축키 | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) |
| 오디오 입출력 | AVAudioEngine + AVAudioConverter |
| 모델 다운로드 | Hugging Face Hub (swift-transformers) |
| 빌드 | xcodegen → `Sori.xcodeproj` |

## 라이선스

MIT
