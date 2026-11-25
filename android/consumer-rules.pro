# 걸음 수, 시각, 활동 상태가 로그에 남지 않도록 릴리스 빌드에서 디버그 로그 호출을 지운다
-assumenosideeffects class android.util.Log {
    public static int d(...);
    public static int v(...);
}
