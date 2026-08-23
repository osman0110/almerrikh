# Conservative R8 keep rules for this app's plugin set. Prioritizes not
# breaking runtime behavior (pose detection, Firebase, notifications) over
# maximum shrink ratio — matches CLAUDE.md's "stability first" priority.

# Flutter engine/plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google ML Kit pose detection — loads native/reflection-based classes that
# R8 cannot trace statically; stripping these silently breaks AI Assessment.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_pose_detection.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_pose_detection_common.** { *; }
-dontwarn com.google.mlkit.**

# Firebase (core/auth/messaging/firestore/functions)
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# camera plugin
-keep class io.flutter.plugins.camera.** { *; }

# flutter_local_notifications
-keep class com.dexterous.** { *; }

# Play Core split-install classes referenced by Flutter's deferred-components
# support even when unused — avoids R8 "missing_rules" build failures.
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
