# UX-TRADEOFFS-APP

A full-stack application built with a FastAPI backend and Flutter frontend.


## Project Structure

```
UX-TRADEOFFS-APP/
├── backend/
│   ├── main.py
│   ├── requirements.txt
│   ├── peaq-pesq-audio/
│   └── src/
│       ├── app.py                 
│       ├── db/
│       │   ├── database.py         
│       │   ├── repository.py      
│       │   ├── schemas.py          
│       │   ├── schema.sql          
│       │   └── dashboard.py        
│       ├── vmaf/
│       │   ├── reference.mp4
│       │   └── vmaf.py
│       ├── peaq/
│       │   └── peaq.py
│       ├── pesq_module/
│       │   └── pesq_score.py
│       ├── webrtc/
│       │   └── codec_call.py
│       └── IMA/
│           └── IMA.py
├── frontend/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── vmaf/
│   │   ├── peaq/
│   │   ├── pesq/
│   │   ├── IQA/
│   │   └── metadata/
│   ├── assets/
│   ├── android/
│   ├── ios/
│   └── web/
```

## Prerequisites

### Backend Requirements
- **Python**: 3.8 or higher
- **FFmpeg**: With VMAF support (libvmaf)
- **Database**: PostgreSQL (via `DATABASE_URL`)

### Frontend Requirements
- **Flutter SDK**: 3.0 or higher
- **Dart SDK**: 2.17 or higher
- **Platform-specific tools**:
  - Android Studio (for Android)
  - Xcode (for iOS, macOS only)

## Backend Setup

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


### 4. Database Setup (PostgreSQL)

The backend expects a PostgreSQL connection string in `DATABASE_URL`.

1) Create a database + user (example)

```bash
createdb ux_tradeoffs
createuser ux_tradeoffs_user
psql -d ux_tradeoffs -c "GRANT ALL PRIVILEGES ON DATABASE ux_tradeoffs TO ux_tradeoffs_user;"
```

2) Create `backend/.env`

```bash
cd backend
touch .env
```

Example `.env`:

```env
DATABASE_URL="postgresql://ux_tradeoffs_user:your_password@localhost:5432/ux_tradeoffs"
```

3) Apply the schema

```bash
psql "$DATABASE_URL" -f src/db/schema.sql
```

Notes:
- The schema enables `pgcrypto` (`CREATE EXTENSION IF NOT EXISTS \"pgcrypto\";`). If you get a permissions error, run the schema as a superuser or ask your DB admin to enable the extension.
- Quick check: `psql "$DATABASE_URL" -c "\\dt"`

### 5. Run the Backend Server

```bash
cd backend
source venv/bin/activate  # if not already activated
python main.py
```


**API Documentation** will be available at:
- Swagger UI: http://localhost:8000/docs



## Frontend Setup

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







