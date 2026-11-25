# rdc_health

링닥 비즈 앱이 휴대폰과 워치의 걸음 기록을 읽는 데 쓰는 Flutter 플러그인입니다. iOS는 HealthKit과 CoreMotion을, Android는 Health Connect를 사용합니다.

시험 전용 API를 걷어내고 정식 API 8개로 바꾸는 중입니다(브랜치 `feature/g1-formalize`). Dart 쪽은 끝났고 iOS/Android 네이티브 구현은 이 브랜치에서 진행 중이라, 그 전에는 호출해도 동작하지 않습니다. 판정 규칙은 본 앱이 갖고 이 패키지는 걸음 데이터와 깨우기만 제공합니다.

## 지원 환경

| 항목 | 값 |
|---|---|
| Flutter | 3.44.0 (`.fvmrc`) |
| iOS | 16.6 이상 |
| Android | minSdk 24. Google Play 서비스(Recording API)가 필요합니다. Health Connect는 API 28 이상에서만 보조로 쓰고, 없으면 그 소스만 건너뜁니다. |

## 설치

본 앱 `pubspec.yaml`에 git 의존으로 추가하고 브랜치 이름이 아닌 커밋 해시로 고정합니다.

```yaml
dependencies:
  rdc_health:
    git:
      url: https://github.com/issac-itphy/ringdoc-steps-flutter.git
      ref: <커밋 해시>
```

본 앱과 이 패키지를 함께 고치는 동안에는 로컬 경로로 덮어써서 push 없이 바로 확인합니다. 이 설정은 본 앱에 커밋하지 않습니다.

```yaml
dependency_overrides:
  rdc_health:
    path: ../rdc_health
```

## 본 앱에 필요한 설정

샘플 앱(`example/`)에 아래 설정이 모두 들어 있으니 같은 파일을 보고 옮기면 됩니다.

### iOS

`ios/Runner/Info.plist`에 권한 요청 문구를 넣습니다. 문구 없이 권한을 요청하면 앱이 종료됩니다.

| 키 | 용도 |
|---|---|
| `NSHealthShareUsageDescription` | 건강 앱의 걸음 읽기 |
| `NSMotionUsageDescription` | 동작 및 피트니스(CoreMotion) 걸음 읽기 |

`ios/Runner/Runner.entitlements`에 HealthKit 항목을 추가합니다. Apple 개발자 계정의 App ID에서도 HealthKit을 켜고 프로비저닝 프로필을 다시 만들어야 합니다.

```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.access</key>
<array/>
<key>com.apple.developer.healthkit.background-delivery</key>
<true/>
```

앱이 꺼진 상태에서도 새 걸음을 받으려면 `AppDelegate.swift`의 `didFinishLaunchingWithOptions` 첫 줄에서 관찰 쿼리를 다시 등록합니다.

```swift
import rdc_health

RdcHealthPlugin.registerObserverIfEnabled()
```

### Android

패키지 매니페스트가 호스트 앱 매니페스트로 병합하는 권한은 `ACTIVITY_RECOGNITION`, `health.READ_STEPS`, `health.READ_HEALTH_DATA_IN_BACKGROUND`, `RECEIVE_BOOT_COMPLETED`입니다. 쓰기 권한과 30일 넘은 기록 읽기 권한은 쓰지 않습니다. 시험용 삼성 헬스 조회(`queries`)도 없앴고 Health Connect 앱 조회만 남겼습니다.

- 가용성: Recording API를 줄 Play 서비스가 기준입니다(`unsupported`/`needsInstall`/`available`). Health Connect는 보조 신호라 없어도 `available`입니다.
- 권한: `requestPermissions()`는 활동 인식을 묻고, Health Connect가 있으면 걸음 읽기와 백그라운드 읽기를 이어서 묻습니다. 반환값은 활동 인식 허용 여부입니다.
- 부팅 수신기(`BootReceiver`): 재부팅과 앱 업데이트 뒤 수집이 켜져 있으면 활동 전환과 주기 작업을 다시 겁니다. 예약 알림은 호스트 앱의 flutter_local_notifications 수신기가 다시 겁니다.
- 백그라운드 엔진: 걷기 전환이 오거나 15분 주기가 되면 WorkManager 작업이 헤드리스 FlutterEngine을 띄워 `setBackgroundHandler`로 등록한 핸들러를 한 번 실행하고(최대 60초) 엔진을 끕니다. `setActive(false)`이면 Dart는 부르지 않습니다. 호스트 앱은 Dart 쪽에서 `setBackgroundHandler`만 부르면 됩니다.
- 로그: 걸음 수, 시각, 활동 상태는 로그에 남기지 않습니다. 릴리스 빌드에서 `Log.d/v`를 지우는 규칙(`consumer-rules.pro`)이 호스트 앱 R8에 전달됩니다.

`android/app/src/main/AndroidManifest.xml`에는 Health Connect 권한 화면이 여는 처리방침 링크를 추가합니다. Android 13 이하는 메인 액티비티의 인텐트 필터를, Android 14 이상은 activity-alias를 사용합니다. 샘플 앱은 처리방침 화면 대신 첫 화면을 엽니다.

```xml
<!-- 메인 activity 안 -->
<intent-filter>
    <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
</intent-filter>

<!-- application 안 -->
<activity-alias
    android:name="ViewPermissionUsageActivity"
    android:exported="true"
    android:targetActivity=".MainActivity"
    android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
    <intent-filter>
        <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
        <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
    </intent-filter>
</activity-alias>
```

패키지가 API 26 미만에서도 `java.time`을 사용하므로 앱 모듈에서 core library desugaring을 켭니다(본 앱은 이미 켜져 있습니다).

```groovy
android {
    compileOptions {
        coreLibraryDesugaringEnabled true
    }
}
dependencies {
    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'
}
```

이 패키지의 Gradle 설정은 AGP 9.0.1과 Kotlin 2.3.20 기준입니다. AGP 8을 쓰는 앱에서 빌드되는지는 아직 확인하지 않았습니다.

## API

| 함수 | 하는 일 |
|---|---|
| `availability()` | 수집 가능 상태 하나(`available`, `needsInstall`, `unsupported`) |
| `requestPermissions()` | 휴대폰 권한 요청. 허용되면 true |
| `enable(String userId)` | 수집 스위치를 켜고 등록 |
| `setActive(bool active)` | 로그아웃용. 기록만 멈추고 등록은 유지. 깨움 때 Dart 핸들러는 계속 실행되어 호스트가 판단함(iOS는 기록이 없어 플래그만 저장) |
| `disable()` | 모든 등록을 풀고 네이티브 파일 삭제. 여러 번 불러도 안전 |
| `moveSegments(from, to)` | 이동 구간 목록(5분, 50걸음 이상) |
| `hourlySteps(from, to)` | 시간별 걸음 수 |
| `setBackgroundHandler(handler)` | OS가 앱을 깨울 때 실행할 함수 등록 |

`setBackgroundHandler`의 핸들러는 `@pragma('vm:entry-point')`가 붙은 최상위 또는 static 함수여야 하며, 클로저를 넘기면 `ArgumentError`가 납니다. 사용 예는 `example/lib/main.dart`를 보세요.

호스트 앱은 `main()` 초반(첫 `await` 전)에 `setBackgroundHandler`를 불러야 합니다. 앱이 종료된 상태에서 iOS가 백그라운드로 앱을 띄우면 걸음 변경 알림이 Dart 시작보다 먼저 도착하는데, 플러그인은 등록이 올 때까지 HealthKit 완료 콜백을 최대 25초 쥐고 있다가 등록 즉시 핸들러를 한 번 실행합니다. 등록이 25초 안에 오지 않으면 그 깨움은 처리 없이 끝납니다.

## 개발

clone할 때 폴더 이름을 패키지 이름과 같은 `rdc_health`로 둡니다. 레포 이름대로 두면 샘플 앱의 iOS 빌드가 SwiftPM 패키지 이름 충돌로 실패합니다. 본 앱처럼 git 의존으로 받을 때는 이 문제가 없습니다.

```sh
git clone https://github.com/issac-itphy/ringdoc-steps-flutter.git rdc_health
```

```sh
fvm flutter analyze
fvm flutter test

# 샘플 앱 실행
cd example && fvm flutter run

# Android 단위 테스트와 린트. gradlew는 샘플 앱을 한 번 빌드하면 생깁니다
cd example/android && ./gradlew :rdc_health:testDebugUnitTest :rdc_health:lintDebug
```
