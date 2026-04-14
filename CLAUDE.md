# CLAUDE.md

Claude Code가 이 저장소에서 작업할 때 필요한 최소 정보를 담습니다.

## 프로젝트 개요

Sori는 macOS 메뉴 막대 받아쓰기 앱입니다. 전역 단축키(`Option + Space`)로 마이크를 녹음하고 Apple Silicon MLX로 Qwen3-ASR을 돌려 전사한 뒤, 결과를 클립보드에 쓰고 활성 앱의 커서 위치에 붙여넣습니다. 개인 사용을 위한 로컬 빌드 전용이며 Mac App Store 배포는 의도하지 않습니다 (샌드박스 안에서는 `CGEventPost`가 막혀서 붙여넣기 기능이 동작하지 않음).

## 빌드 / 실행

```bash
# Xcode 프로젝트 재생성 (project.yml 수정 후 필요)
xcodegen generate

# Xcode에서 열어서 ⌘R
open Sori.xcodeproj

# 또는 CLI 빌드
xcodebuild -project Sori.xcodeproj -scheme Sori -configuration Debug -destination 'platform=macOS' build
```

**요구사항**: Swift 6.2, Xcode 16+, macOS 15+, Apple Silicon.

## 디렉토리 구조

```
Sori/
├── SoriApp.swift              # @main, MenuBarExtra + Settings scene
├── AppDelegate.swift          # 생명주기, Welcome/일반 세션 분기
├── AppState.swift             # @MainActor ObservableObject, 상태 머신 & 오케스트레이션
├── Core/
│   ├── Recorder.swift         # AVAudioEngine 녹음 (final class, @unchecked Sendable)
│   ├── Transcriber.swift      # actor Qwen3ASRSTT 래퍼, lazy load + idle unload + cancel
│   ├── ModelDownloader.swift  # actor, Hub snapshot API
│   ├── AudioFileDecoder.swift # 외부 파일 → 16kHz mono Int16 wav
│   ├── FileTranscriptionQueue.swift  # @MainActor 파일 전사 큐
│   ├── Clipboard.swift        # NSPasteboard 쓰기 + CGEventPost Cmd-V
│   ├── HotkeyManager.swift    # KeyboardShortcuts + ESC 전역 모니터
│   ├── PermissionChecker.swift# 마이크/접근성 상태 폴링
│   └── Preferences.swift      # UserDefaults 키 / PreferencesSnapshot / AppSupportDirectory
├── History/
│   ├── HistoryEntry.swift     # Codable 모델 (source: .live | .file)
│   └── HistoryStore.swift     # JSON 영속화, FIFO 1000개
└── UI/
    ├── WelcomeWindow.swift    # 첫 실행 권한/다운로드 안내 창
    ├── MenuBarContent.swift   # 메뉴 막대 드롭다운 (히스토리 + 검색 + 좌/우클릭)
    ├── SettingsView.swift     # 3탭 설정 창
    └── FileQueueWindow.swift  # 파일 전사 큐 창
```

## 상태 머신

```
.idle ─── toggleRecording ──▶ .recording ─── toggleRecording ──▶ .transcribing ──▶ .idle
  │                             │                                   │
  │                             └── ESC / cancel ──▶ .idle           └── 에러 ──▶ .error(String)
  └── 첫 녹음 전 lazy 로드 ──▶ .loadingModel ──▶ .recording
```

`AppRecordingState` (AppState.swift). 메뉴 막대 아이콘은 상태에 따라 바뀌며 `.recording`일 때만 0.5초 주기로 깜빡임.

## 스레드 규칙

- UI 상태를 들고 있는 타입은 `@MainActor`: `AppState`, `HistoryStore`, `FileTranscriptionQueue`, `PermissionChecker`, 컨트롤러 클래스.
- ML 모델에 접근하는 타입은 `actor`: `Transcriber`, `ModelDownloader`.
- `Recorder`는 audio render thread에서 tap 콜백이 호출되므로 `final class: @unchecked Sendable`. tap 콜백 안에서 동기적으로 변환 + 파일 쓰기.
- 메인 ↔ actor 경계에서는 `await` 또는 `Task { @MainActor in ... }` 사용.
- SwiftUI 바인딩과 섞이는 곳에서는 `@Published` + `@ObservedObject` 패턴 사용.

## App Sandbox / 권한 / Entitlements

- **App Sandbox는 OFF** (절대 켜지 말 것). 켜면 `CGEventPost(tap: .cghidEventTap, ...)`가 차단되어 붙여넣기 기능이 통째로 망가집니다. `project.yml`에서 entitlement 파일을 지정하지 않아 기본 OFF 상태가 유지됩니다.
- `INFOPLIST_KEY_LSUIElement: YES` — Dock 아이콘 숨김 메뉴 막대 전용 앱.
- `INFOPLIST_KEY_NSMicrophoneUsageDescription` — `project.yml`에 선언됨. 수정 후 `xcodegen generate` 필요.
- `ENABLE_HARDENED_RUNTIME: NO`, `CODE_SIGN_IDENTITY: "-"` — 로컬 "Sign to Run Locally" 서명.
- 런타임 권한: 마이크(`AVCaptureDevice.requestAccess`)와 접근성(`AXIsProcessTrustedWithOptions`). 두 가지 모두 `PermissionChecker`가 2초 주기로 폴링.

## 모델 관련

- **기본 모델**: `mlx-community/Qwen3-ASR-1.7B-bf16` (~3.4 GB, 비양자화). `ModelIdentifier.defaultModel`
- **설정에서 선택 가능**: bf16 / 8bit / 6bit / 4bit / 0.6B 계열
- **다운로드 경로**: `~/Library/Application Support/Sori/models/<repo-id>/`
- **로드 방식**: 기본은 lazy — 첫 전사 요청 시 `Qwen3ASRSTT.loadWithWarmup(from:)` 호출. 설정 토글로 eager 로드 가능.
- **유휴 언로드**: 기본 300초 (`modelIdleTimeoutSeconds`). `Transcriber.scheduleIdleUnload`가 `Task.sleep`으로 대기 후 `stt = nil` + `Qwen3ASRSTT.flushMemoryPool()`
- **전사 인터럽트**: `Transcriber.cancelCurrent()`는 플래그를 세우고 결과를 버리기만 한다. mlx-swift-asr는 내부 인터럽트를 지원하지 않아, 현재 추론이 끝날 때까지 GPU는 돈다. 사용자 체감상 "취소됨"으로 보이게 결과만 버린다.

## 저장 위치

- 설정: `NSUserDefaults` (번들 ID `com.solstice.sori`) — `PreferenceKeys` 참조
- 히스토리: `~/Library/Application Support/Sori/history.json`
- 모델 캐시: `~/Library/Application Support/Sori/models/`
- 파일 전사 결과 `.txt`: 원본 파일 옆. 쓰기 실패 시 `~/Library/Application Support/Sori/transcripts/<원본이름>.txt`
- 녹음 임시 wav: `FileManager.default.temporaryDirectory` → 전사 후 즉시 삭제

## 수정 시 주의

- `project.yml` 수정 후 반드시 `xcodegen generate` 실행. `.xcodeproj`는 generated 파일이지만 커밋 대상.
- 번들 ID(`com.solstice.sori`) 변경 시 기존 `NSUserDefaults` 도메인과 Application Support 디렉토리의 기존 데이터는 마이그레이션 없이 버려집니다.
- 클립보드 동작은 의도적으로 "쓰기만 하고 복원하지 않음" — 사용자 요구사항입니다. 변경 금지.
- `Transcriber.transcribe`는 `actor` 메서드지만 내부에서 `mlx-swift-asr`의 transcribe를 동기 호출합니다. `Task.checkCancellation`은 사용하지 말 것 (inner 호출이 체크하지 않으므로 의미 없음).
- `AudioFileDecoder`의 `ConversionFeeder`는 `@Sendable` 경계 때문에 필요합니다. 지우지 말 것.
- `PermissionChecker.refresh`의 AX 옵션 딕셔너리는 문자열 리터럴을 사용합니다. `kAXTrustedCheckOptionPrompt`는 Swift 6 strict concurrency와 충돌하므로 의도적으로 피합니다.

## 배포

현재는 로컬 빌드 전용. 추후 다른 사용자에게 배포한다면:

1. Apple Developer Program 가입 ($99/년)
2. Developer ID Application 인증서 확보
3. `entitlements.plist` 작성 (`cs.allow-jit` 또는 `cs.allow-unsigned-executable-memory`, `cs.disable-library-validation`, `device.audio-input`, `network.client`)
4. `ENABLE_HARDENED_RUNTIME: YES`로 변경 후 codesign → notarytool → stapler → DMG

App Store 배포는 기술 구조상 불가능합니다 (샌드박스 + JIT 제약).
