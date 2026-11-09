# rdc_health

링닥 비즈 앱이 휴대폰과 워치의 걸음 기록을 읽는 데 쓰는 Flutter 플러그인입니다. iOS는 HealthKit과 CoreMotion을, Android는 Health Connect를 사용합니다.

지금 코드는 시험 단계 구현이라 시험 전용 API와 권한이 함께 들어 있어 본 앱의 출시 빌드에는 넣지 않습니다.

## 지원 환경

| 항목 | 값 |
|---|---|
| Flutter | 3.44.0 (`.fvmrc`) |
| iOS | 16.6 이상 |
| Android | minSdk 24. API 28 미만에서는 Health Connect를 쓸 수 없어 `healthStepSamples` 같은 호출이 `health_connect_unavailable` 오류를 돌려줍니다. |

## 설치

본 앱 `pubspec.yaml`에 git 의존으로 추가하고 브랜치 이름이 아닌 커밋 해시로 고정합니다.

```yaml
dependencies:
  rdc_health:
    git:
      url: https://github.com/issac-itphy/rdc_health.git
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
| `NSHealthUpdateUsageDescription` | 시험용 걸음 쓰기(`writeTestSteps`)를 쓸 때만 |

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

HealthSpikeObserver.bootstrap()
```

### Android

걸음 권한은 패키지 매니페스트에서 본 앱 매니페스트로 자동 병합됩니다. 병합되는 항목은 `health.READ_STEPS`, `health.WRITE_STEPS`(시험용), `health.READ_HEALTH_DATA_IN_BACKGROUND`, `health.READ_HEALTH_DATA_HISTORY`, `ACTIVITY_RECOGNITION`과 시험용 수신기 2개입니다.

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

## 시험 전용 기능

본 앱에 정식으로 넣기 전에 걷어낼 항목입니다.

- 시험용 API: `writeTestSteps`, `scheduleTestNotification`, `readLog`, `appendLog`, `clearLog`
- Android 걸음 증가 알림: 걸음이 늘면 패키지가 직접 로컬 알림을 띄우는 동작(앱이 꺼졌을 때의 주기 작업, 앱이 켜졌을 때의 10초 확인)과 예약 알림 취소 시험
- 시험 로그: 걸음 기록을 기기 안 파일에 남기고 Android debug 빌드는 다운로드 폴더에도 복사
- 권한: `health.WRITE_STEPS`, `NSHealthUpdateUsageDescription`

## 개발

```sh
fvm flutter analyze
fvm flutter test

# 샘플 앱 실행
cd example && fvm flutter run

# Android 단위 테스트와 린트. gradlew는 샘플 앱을 한 번 빌드하면 생깁니다
cd example/android && ./gradlew :rdc_health:testDebugUnitTest :rdc_health:lintDebug
```
