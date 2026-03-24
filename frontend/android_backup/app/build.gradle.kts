<manifest xmlns:android="http://schemas.android.com/apk/res/android">

<!-- ─── Existing ─────────────────────────────────────────────── -->
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>

<!-- ─── Network & Connectivity ───────────────────────────────── -->
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>

<!-- ─── Location (WiFi SSID/BSSID + GPS) ─────────────────────── -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>

<!-- ─── Battery ──────────────────────────────────────────────── -->
<uses-permission android:name="android.permission.BATTERY_STATS"/>

<!-- ─── Bluetooth (Android 12+ needs SCAN + CONNECT) ─────────── -->
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission
android:name="android.permission.BLUETOOTH_CONNECT"
android:minSdkVersion="31"/>
<uses-permission
android:name="android.permission.BLUETOOTH_SCAN"
android:minSdkVersion="31"/>

<!-- ─── Sensors (high-frequency sampling e.g. gyro) ──────────── -->
<uses-permission android:name="android.permission.HIGH_SAMPLING_RATE_SENSORS"/>

<!-- ─── Storage (for device info reads) ──────────────────────── -->
<uses-permission
android:name="android.permission.READ_EXTERNAL_STORAGE"
android:maxSdkVersion="32"/>
<uses-permission
android:name="android.permission.WRITE_EXTERNAL_STORAGE"
android:maxSdkVersion="29"/>

<!-- ─── Notifications (Android 13+) ──────────────────────────── -->
<uses-permission
android:name="android.permission.POST_NOTIFICATIONS"
android:minSdkVersion="33"/>

<!-- ─── Camera & Mic (for capability detection) ──────────────── -->
<uses-permission android:name="android.permission.CAMERA"/>

<!-- ─── Activity Recognition (motion / step detection) ───────── -->
<uses-permission android:name="android.permission.ACTIVITY_RECOGNITION"/>

<!-- ─── Advertising ID (Play Store Data Safety required) ─────── -->
<uses-permission android:name="com.google.android.gms.permission.AD_ID"/>

<!-- ─── Feature declarations (soft — won't block install) ────── -->
<uses-feature android:name="android.hardware.location.gps"          android:required="false"/>
<uses-feature android:name="android.hardware.sensor.accelerometer"  android:required="false"/>
<uses-feature android:name="android.hardware.sensor.gyroscope"      android:required="false"/>
<uses-feature android:name="android.hardware.bluetooth"             android:required="false"/>
<uses-feature android:name="android.hardware.nfc"                   android:required="false"/>
<uses-feature android:name="android.hardware.camera.any"            android:required="false"/>
<uses-feature android:name="android.hardware.fingerprint"           android:required="false"/>

<application
android:label="frontend"
android:name="${applicationName}"
android:icon="@mipmap/ic_launcher">

<activity
android:name=".MainActivity"
android:exported="true"
android:launchMode="singleTop"
android:taskAffinity=""
android:theme="@style/LaunchTheme"
android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
android:hardwareAccelerated="true"
android:windowSoftInputMode="adjustResize">

<meta-data
android:name="io.flutter.embedding.android.NormalTheme"
android:resource="@style/NormalTheme"/>

<intent-filter>
<action android:name="android.intent.action.MAIN"/>
<category android:name="android.intent.category.LAUNCHER"/>
</intent-filter>
</activity>

<!-- Don't delete the meta-data below.
This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
<meta-data
android:name="flutterEmbedding"
android:value="2"/>

</application>

<!-- Required to query activities that can process text, see:
https://developer.android.com/training/package-visibility and
https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.
In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
<queries>
<intent>
<action android:name="android.intent.action.PROCESS_TEXT"/>
<data android:mimeType="text/plain"/>
</intent>
</queries>

</manifest>