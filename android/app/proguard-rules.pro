# Flutter Wrapper and Plugins Proguard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class dev.flutter.pigeon.** { *; }

# Prevent stripping the dev.flutter.pigeon.shared_preferences_android.SharedPreferencesApi
-keep class dev.flutter.pigeon.shared_preferences_android.SharedPreferencesApi { *; }
-keep class dev.flutter.pigeon.shared_preferences_android.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# R8 missing classes rules
-keep class com.example.mssql_connection.** { *; }
-keep class net.sourceforge.jtds.** { *; }
-dontwarn com.example.mssql_connection.**
-dontwarn net.sourceforge.jtds.**

-dontwarn com.example.mssql_connection.MssqlConnectionPlugin
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
-dontwarn jcifs.Config
-dontwarn jcifs.smb.NtlmPasswordAuthentication
-dontwarn jcifs.smb.SmbNamedPipe
-dontwarn org.ietf.jgss.GSSContext
-dontwarn org.ietf.jgss.GSSCredential
-dontwarn org.ietf.jgss.GSSException
-dontwarn org.ietf.jgss.GSSManager
-dontwarn org.ietf.jgss.GSSName
-dontwarn org.ietf.jgss.Oid
