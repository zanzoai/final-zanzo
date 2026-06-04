############################################
# 📷 ML Kit Text Recognition (Aadhaar OCR)
############################################
# Keep all ML Kit OCR classes (Latin + optional)
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.mlkit.vision.interfaces.** { *; }

############################################
# 💳 Stripe SDK (Payment + Push Provisioning)
############################################
-keep class com.stripe.android.** { *; }
-dontwarn com.stripe.android.**
-keep class com.reactnativestripesdk.** { *; }

# stripe-android 20.x uses Jetpack Compose for PaymentSheet internally.
# R8 treeshakes Compose runtime classes because they're only referenced via
# composition locals (indirect lookup). Keep the full runtime to prevent
# ClassNotFoundException at runtime.
-keep class androidx.compose.** { *; }
-dontwarn androidx.compose.**
-keep class androidx.activity.compose.** { *; }
-dontwarn androidx.activity.compose.**

############################################
# 🎤 Flutter Sound (uses JNI + native libs)
############################################
-keep class xyz.canardoux.flutter.** { *; }
-dontwarn xyz.canardoux.flutter.**

############################################
# 🧩 Flutter & Plugin Entry Points
############################################
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
-keep class com.google_mlkit_text_recognition.** { *; }

############################################
# ⚙️ General Safety Rules
############################################
# Keep annotation and reflection info
-keepattributes *Annotation*, Signature, InnerClasses

# Suppress warnings for annotations
-dontwarn org.jetbrains.annotations.**
-dontwarn javax.annotation.**

# Prevent stripping of reflection-based class members
-keep class * extends java.util.ListResourceBundle {
    protected Object[][] getContents();
}
-keepclassmembers class * {
    @androidx.annotation.Keep <fields>;
    @androidx.annotation.Keep <methods>;
}

############################################
# ✅ Extra Compatibility (Document Scanner, Image Cropper)
############################################
-keep class io.scanbot.** { *; }
-dontwarn io.scanbot.**
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**