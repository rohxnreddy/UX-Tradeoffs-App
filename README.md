# UX-TRADEOFFS-APP

A full-stack application Built with FastAPI backend and Flutter frontend.


## 📁 Project Structure

```
UX-TRADEOFFS-APP/
├── backend/
│   ├── src/
│   │   ├── vmaf/
│   │   │   ├── __pycache__/
│   │   │   ├── reference.mp4       # Reference video for comparison
│   │   │   └── vmaf.py            # VMAF computation module
│   │   ├── app.py                 # FastAPI application
│   │   ├── database_schemas.py    # Database schema definitions
│   │   ├── database.py            # Database connection & ORM
│   │   └── schemas.py             # Pydantic models
│   ├── venv/                      # Python virtual environment
│   ├── .env                       # Environment variables
│   ├── main.py                    # Application entry point
│   └── requirements.txt           # Python dependencies
│
└── frontend/
    ├── lib/
    │   └── vmaf/
    │       ├── vmaf.dart          # VMAF service module
    │       └── app.dart           # Main app module
    ├── android/                   # Android-specific files
    ├── ios/                       # iOS-specific files
    ├── assets/                    # Static assets
    ├── build/                     # Build artifacts
    ├── test/                      # Unit tests
    ├── .metadata
    ├── analysis_options.yaml      # Dart analyzer config
    ├── pubspec.yaml              # Flutter dependencies
    └── README.md
```

## 🔧 Prerequisites

### Backend Requirements
- **Python**: 3.8 or higher
- **FFmpeg**: With VMAF support (libvmaf)
- **Database**: PostgreSQL SDK

### Frontend Requirements
- **Flutter SDK**: 3.0 or higher
- **Dart SDK**: 2.17 or higher
- **Platform-specific tools**:
  - Android Studio (for Android)
  - Xcode (for iOS, macOS only)

##  Backend Setup

### 1. Install FFmpeg with VMAF Support

#### Build from Source (for full VMAF support)
```bash
git clone https://github.com/FFmpeg/FFmpeg.git
cd FFmpeg
./configure --enable-gpl --enable-libvmaf --enable-version3
make -j$(nproc)
sudo make install
```

**Verify installation:**
```bash
ffmpeg -version
ffprobe -version
# Check for libvmaf support
ffmpeg -filters 2>&1 | grep vmaf
```

### 2. Set Up Python Environment

Navigate to the backend directory:
```bash
cd backend
```

Create and activate virtual environment:
```bash
# Create virtual environment
python3 -m venv venv

# Activate (macOS/Linux)
source venv/bin/activate

# Activate (Windows)
venv\Scripts\activate
```

### 3. Install Python Dependencies

```bash
pip install --upgrade pip
pip install -r requirements.txt
```


### 4. Configure Environment Variables

Create `.env` file in `backend/`:
```bash
touch .env
```

Add configuration:
```env
POSTGRES_USERNAME="your_username"
POSTGRES_PASSWORD="your_password"
POSTGRES_DB="db_name"
```

### 5. Run the Backend Server

```bash
cd backend
source venv/bin/activate  # if not already activated
python main.py
```


**API Documentation** will be available at:
- Swagger UI: http://localhost:8000/docs



## 📱 Frontend Setup

### 1. Install Flutter


**Verify installation:**
```bash
flutter --version
flutter doctor
```

### 2. Navigate to Frontend Directory

```bash
cd frontend
```

### 3. Install Dependencies

```bash
flutter pub get
```



### 4. Run on Mobile (Android)
```bash
# List available devices
flutter devices

# Run on connected Android device
flutter run -d android
```

## 📜 Third-Party Attribution

This project uses audio assets that require attribution. The PEAQ reference
audio ([Allegro in C major, K.1b](https://musopen.org/music/?length__lt=1))
is provided by [Musopen](https://musopen.org) under the
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) license.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full details.







