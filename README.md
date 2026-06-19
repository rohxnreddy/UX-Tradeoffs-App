# UX-Tradeoffs-App

A comprehensive full-stack application designed to measure, analyze, and visualize user experience (UX) tradeoffs across different media modalities. The platform provides objective quality assessment tools for video, audio, speech, and images by combining a Flutter frontend with a FastAPI backend.

## Features

- **Video Quality Assessment (VMAF):** Integration for computing Video Multi-Method Assessment Fusion.
- **Audio Quality Assessment (PEAQ):** Perceptual Evaluation of Audio Quality for testing audio fidelity.
- **Speech Quality Assessment (PESQ):** Perceptual Evaluation of Speech Quality for voice communications.
- **Image Quality Assessment (IQA):** Metrics including BRISQUE, NIQE, PIQE, and RankIQA.
- **WebRTC Testing:** Utilities for assessing WebRTC codec performance.
- **Hardware & Battery Load:** Mobile-side battery load and performance testing.
- **User Questionnaires:** Built-in subjective survey module for collecting perceived user experience.
- **Results Dashboard:** Database integration with a historical results viewer and insights dashboard.

## Project Structure

```text
UX-Tradeoffs-App/
├── backend/
│   ├── src/
│   │   ├── app.py                 # FastAPI application entry point
│   │   ├── db/                    # PostgreSQL Database, ORM & Insights dashboard
│   │   ├── IMA/                   # Image Quality Assessment (BRISQUE, NIQE, PIQE, etc.)
│   │   ├── peaq/                  # Perceptual Evaluation of Audio Quality module
│   │   ├── pesq/                  # Perceptual Evaluation of Speech Quality module
│   │   ├── vmaf/                  # VMAF computation module
│   │   └── webrtc/                # WebRTC codec evaluation tools
│   ├── requirements.txt           # Python dependencies
│   ├── main.py                    # Uvicorn server runner
│   ├── start_prod.sh              # Production startup script
│   └── stop_prod.sh               # Production shutdown script
│
└── frontend/
    ├── lib/
    │   ├── battery/               # Battery load testing UI
    │   ├── IQA/                   # Image Quality Assessment UI
    │   ├── peaq/                  # PEAQ testing UI
    │   ├── pesq/                  # PESQ testing UI
    │   ├── vmaf/                  # VMAF testing UI
    │   └── src/                   # Core application logic
    │       ├── auth/              # Authentication screens
    │       ├── questionnaire/     # Subjective UX questionnaire
    │       ├── results/           # Test history and results viewer
    │       ├── runner/            # Test execution framework
    │       └── tests/             # Specific test page implementations
    ├── android/                   # Android-specific files
    ├── ios/                       # iOS-specific files
    └── pubspec.yaml               # Flutter dependencies
```

## Prerequisites

### Backend Requirements
- **Python**: 3.8 or higher
- **FFmpeg**: Compiled with VMAF support (`libvmaf`)
- **Database**: PostgreSQL
- **Additional Libraries**: Specific dependencies for IQA, PEAQ, and PESQ processing.

### Frontend Requirements
- **Flutter SDK**: 3.0 or higher
- **Dart SDK**: 2.17 or higher
- **Platform-specific tools**: Android Studio (Android) or Xcode (iOS/macOS)

## Backend Setup

### 1. Install FFmpeg with VMAF Support

```bash
git clone https://github.com/FFmpeg/FFmpeg.git
cd FFmpeg
./configure --enable-gpl --enable-libvmaf --enable-version3
make -j$(nproc)
sudo make install
```

### 2. Set Up Python Environment

Navigate to the backend directory:
```bash
cd backend
python3 -m venv venv
source venv/bin/activate  # macOS/Linux
# venv\Scripts\activate   # Windows
```

### 3. Install Python Dependencies

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

### 4. Configure Environment Variables

Create a `.env` file in the `backend/` directory:
```env
POSTGRES_USERNAME="your_username"
POSTGRES_PASSWORD="your_password"
POSTGRES_DB="db_name"
```

### 5. Run the Backend Server

```bash
cd backend
source venv/bin/activate
python main.py
```
*API Documentation will be available at: http://localhost:8000/docs*

## Frontend Setup

### 1. Navigate to Frontend Directory
```bash
cd frontend
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Run the Application
```bash
flutter devices       # List available devices
flutter run -d <id>   # Run on selected device
```

## License

This project is licensed under the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International Public License (CC BY-NC-SA 4.0)**. 

You are free to:
- **Share** — copy and redistribute the material in any medium or format
- **Adapt** — remix, transform, and build upon the material

Under the following terms:
- **Attribution** — You must give appropriate credit, provide a link to the license, and indicate if changes were made.
- **NonCommercial** — You may not use the material for commercial purposes.
- **ShareAlike** — If you remix, transform, or build upon the material, you must distribute your contributions under the same license as the original.

For full license details, please see the [LICENSE](LICENSE) file in the root directory.

## Third-Party Attribution

This project utilizes specific third-party assets for media testing, which require attribution:

### Audio — PEAQ Reference File (`peaq.wav`)
- **Title:** Allegro in C major, K.1b
- **Composer:** Wolfgang Amadeus Mozart
- **Source:** [Musopen](https://musopen.org/music/?length__lt=1)
- **License:** [Creative Commons Attribution 3.0 Unported (CC BY 3.0)](https://creativecommons.org/licenses/by/3.0/)
- *Note:* Used as the reference signal for Perceptual Evaluation of Audio Quality (PEAQ) testing. The file is resampled and processed on the server side during quality analysis but is not redistributed in modified form.

### Speech — PESQ Reference File (`pesq.wav`)
- **Title:** spontaneous-speech-en-1
- **Source:** [Mozilla Common Voice — Data Collective](https://datacollective.mozillafoundation.org/datasets/cmn1pv5hi00uto1072y1074y7)
- **License:** [CC0 1.0 Universal (Public Domain)](https://spdx.org/licenses/CC0-1.0.html)
- *Note:* Used as the reference signal for Perceptual Evaluation of Speech Quality (PESQ) testing. 

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full details.
