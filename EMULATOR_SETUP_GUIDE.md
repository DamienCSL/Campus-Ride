# Complete Android Emulator Setup Guide for CampusRide

## Step-by-Step Instructions

### **STEP 1: Verify Android Studio Installation**

1. **Check if Android Studio is installed:**
   - Open Android Studio
   - If not installed, download from: https://developer.android.com/studio
   - Install it with default settings

2. **Verify SDK Location:**
   - Open Android Studio
   - Go to: **File → Settings** (or **Android Studio → Preferences** on Mac)
   - Navigate to: **Appearance & Behavior → System Settings → Android SDK**
   - Note the **Android SDK Location** path (usually: `C:\Users\damie\AppData\Local\Android\Sdk`)

---

### **STEP 2: Install Required SDK Components**

1. **Open SDK Manager:**
   - In Android Studio: **Tools → SDK Manager**
   - Or: **More Actions → SDK Manager**

2. **Install SDK Platforms:**
   - Go to **SDK Platforms** tab
   - Check at least one Android version (recommended: **Android 13 (Tiramisu)** or **Android 14**)
   - Click **Apply** and wait for installation

3. **Install SDK Tools:**
   - Go to **SDK Tools** tab
   - Ensure these are checked:
     - ✅ **Android SDK Build-Tools**
     - ✅ **Android Emulator**
     - ✅ **Android SDK Platform-Tools**
     - ✅ **Android SDK Command-line Tools**
     - ✅ **Google Play services**
   - Click **Apply** and wait for installation

---

### **STEP 3: Set Environment Variables (CRITICAL)**

1. **Open Environment Variables:**
   - Press `Win + R`, type `sysdm.cpl`, press Enter
   - Click **Advanced** tab → **Environment Variables** button
   - OR: Search "Environment Variables" in Windows Start menu

2. **Add User Variables:**
   - Under **User variables for damie**, click **New**
   - Add these TWO variables (one at a time):
   
   **Variable 1:**
   - Name: `ANDROID_HOME`
   - Value: `C:\Users\damie\AppData\Local\Android\Sdk`
   - Click **OK**
   
   **Variable 2:**
   - Name: `ANDROID_SDK_ROOT`
   - Value: `C:\Users\damie\AppData\Local\Android\Sdk`
   - Click **OK**

3. **Edit Path Variable:**
   - Under **User variables**, find **Path** and click **Edit**
   - Click **New** and add these TWO paths (one at a time):
     - `C:\Users\damie\AppData\Local\Android\Sdk\emulator`
     - `C:\Users\damie\AppData\Local\Android\Sdk\platform-tools`
   - Click **OK** on all dialogs

4. **IMPORTANT:** Close ALL terminal windows and Cursor completely, then reopen them

---

### **STEP 4: Verify Environment Variables**

Open a **NEW** PowerShell terminal in Cursor and run:

```powershell
# Check environment variables
echo $env:ANDROID_HOME
echo $env:ANDROID_SDK_ROOT

# Check if tools are in PATH
where emulator
where adb

# Check Flutter setup
flutter doctor
```

**Expected Output:**
- `ANDROID_HOME` and `ANDROID_SDK_ROOT` should show: `C:\Users\damie\AppData\Local\Android\Sdk`
- `where emulator` should show: `C:\Users\damie\AppData\Local\Android\Sdk\emulator\emulator.exe`
- `where adb` should show: `C:\Users\damie\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- `flutter doctor` should show Android toolchain as installed

---

### **STEP 5: Create an Android Virtual Device (AVD)**

1. **Open AVD Manager:**
   - In Android Studio: **Tools → Device Manager**
   - Or: **More Actions → Virtual Device Manager**

2. **Create New Device:**
   - Click **Create Device** button
   - Select a device (recommended: **Pixel 5** or **Pixel 6**)
   - Click **Next**

3. **Select System Image:**
   - Choose a system image (recommended: **Android 13 (Tiramisu)** or **Android 14**)
   - If you see **Download** next to an image, click it to download first
   - Select the downloaded image and click **Next**

4. **Configure AVD:**
   - Name your device (e.g., "Pixel_5_API_33")
   - Review settings (you can change RAM, etc. if needed)
   - Click **Finish**

5. **Verify AVD Created:**
   - You should see your device in the AVD Manager list

---

### **STEP 6: Start the Emulator**

**Method 1: From Android Studio**
- In AVD Manager, click the **Play** button (▶) next to your device
- Wait for emulator to boot (first time takes longer)

**Method 2: From Command Line**
```powershell
# List available emulators
flutter emulators

# Launch specific emulator
flutter emulators --launch <emulator_id>

# Or launch directly
& "C:\Users\damie\AppData\Local\Android\Sdk\emulator\emulator.exe" -avd <emulator_name>
```

**Wait for emulator to fully boot** (you'll see the Android home screen)

---

### **STEP 7: Verify Emulator is Detected**

In a new terminal, run:

```powershell
# Check connected devices
flutter devices

# Or use adb
adb devices
```

**Expected Output:**
- You should see your emulator listed (e.g., `emulator-5554`)

---

### **STEP 8: Install Project Dependencies**

In your project directory (`C:\Users\damie\StudioProjects\CampusRide`), run:

```powershell
# Get Flutter packages
flutter pub get

# Clean build (if needed)
flutter clean
```

---

### **STEP 9: Run Your CampusRide App**

1. **Make sure emulator is running** (from Step 6)

2. **Run the app:**
```powershell
flutter run
```

3. **First build takes time** - Flutter will:
   - Build the Android APK
   - Install it on the emulator
   - Launch the app

4. **Hot Reload:**
   - Press `r` in terminal to hot reload
   - Press `R` to hot restart
   - Press `q` to quit

---

### **STEP 10: Troubleshooting Common Issues**

#### **Issue: "Error fetching your Android emulators!"**
**Solution:**
- Verify environment variables are set correctly (Step 3)
- Restart Cursor completely
- Run `flutter doctor` to check setup

#### **Issue: "No devices found"**
**Solution:**
- Make sure emulator is running
- Run `adb devices` to verify connection
- Try restarting the emulator

#### **Issue: "SDK location not found"**
**Solution:**
- Check `ANDROID_HOME` and `ANDROID_SDK_ROOT` are set
- Verify the path exists in File Explorer
- Restart terminal/Cursor

#### **Issue: Build errors**
**Solution:**
```powershell
flutter clean
flutter pub get
flutter run
```

#### **Issue: Emulator is slow**
**Solution:**
- Enable hardware acceleration in BIOS (Intel VT-x or AMD-V)
- Allocate more RAM to emulator in AVD settings
- Use a system image with Google Play (usually faster)

---

### **Quick Reference Commands**

```powershell
# Check Flutter setup
flutter doctor

# List available emulators
flutter emulators

# Launch emulator
flutter emulators --launch <emulator_id>

# Check connected devices
flutter devices

# Run app
flutter run

# Hot reload (while app is running)
# Press 'r' in terminal

# Stop app
# Press 'q' in terminal
```

---

### **Next Steps After Setup**

1. ✅ Emulator should be running
2. ✅ App should launch successfully
3. ✅ You can now develop and test your CampusRide app
4. ✅ Use hot reload for faster development

---

## Need Help?

If you encounter any issues:
1. Run `flutter doctor -v` and check the output
2. Verify all environment variables are set
3. Make sure Android Studio SDK components are installed
4. Restart everything (emulator, terminal, Cursor)

Good luck with your FYP project! 🚀



