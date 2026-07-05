# NeuroVoice AI

Longitudinal speech monitoring for people with neurological conditions
(Parkinson's, aphasia, ALS, stroke recovery, MS). The app records a daily
reading-passage sample, analyzes it on **your own computer** — nothing is sent
to any cloud service and everything is free — and tracks how your speech
changes against **your own baseline** over weeks and months.

> **Not a medical device.** NeuroVoice AI tracks change over time; it does not
> diagnose any condition.

## How it works

```
Flutter app (voice_health/)                 FastAPI backend (backend/)
┌──────────────────────────┐   WAV upload   ┌─────────────────────────────┐
│ Record 16 kHz WAV        │ ─────────────> │ Noise reduction             │
│ Store locally            │                │ Whisper transcription       │
│ Dashboard / streak       │ <───────────── │ Acoustic features (Praat)   │
│ Trend charts (fl_chart)  │  JSON result   │ Voice embedding             │
│ Clinician report export  │                │ Baseline comparison         │
└──────────────────────────┘                │ Plain-language summary      │
                                            │ SQLite history              │
                                            └─────────────────────────────┘
```

Measured per recording: speech rate, articulation rate, pause count/duration,
pitch and pitch variability, volume, jitter, shimmer, harmonic-to-noise ratio,
voice tremor, speech rhythm, pronunciation confidence, MFCCs, and a voice
embedding. Each new recording is compared to the personal baseline (first 5
recordings) and a 0–100 stability score plus a patient-friendly summary is
generated — deterministically, with no paid LLM.

## Running the backend (Windows PC)

The virtual environment is already set up in `backend/.venv`. To start the
server:

```powershell
cd backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

- `--host 0.0.0.0` lets your phone connect over Wi-Fi. When Windows Firewall
  asks, **allow Python on private networks**.
- Interactive API docs: http://localhost:8000/docs
- The Whisper `base` model (~75 MB) is downloaded automatically on first run
  (already done on this machine).

Fresh setup on another machine: `python -m venv .venv`, then
`.venv\Scripts\pip install -r requirements.txt`.

### Configuration (environment variables, all optional)

| Variable | Default | Purpose |
|---|---|---|
| `NEUROVOICE_WHISPER_MODEL` | `base` | `tiny`/`base`/`small`/`medium` — accuracy vs. speed |
| `NEUROVOICE_DB` | `backend/neurovoice.db` | SQLite location |

### Optional upgrade: pretrained voice embeddings

By default the backend uses MFCC-statistics embeddings (small, fast). For a
more sensitive speaker-consistency signal, install SpeechBrain's ECAPA-TDNN
(~1.5 GB with CPU PyTorch, still free):

```powershell
.\.venv\Scripts\pip install speechbrain torch --index-url https://download.pytorch.org/whl/cpu
```

The backend detects it automatically — no code change needed.

## Running the app

One-time: enable Windows **Developer Mode** (`start ms-settings:developers`) —
Flutter plugins need symlink support.

```powershell
cd voice_health
flutter run
```

Connecting the app to the backend (Settings tab → Server address):

- **Android emulator**: `http://10.0.2.2:8000` (the default — works out of the box).
- **Physical phone**: phone and PC on the same Wi-Fi, then use your PC's LAN IP,
  e.g. `http://192.168.1.23:8000`. Find the IP with `ipconfig` → "IPv4 Address"
  of your Wi-Fi adapter. Use **Test connection** in Settings to confirm.

## Project layout

```
backend/
  app/main.py               API: /health, /analyze, /history/{user}, DELETE /history/{user}
  app/analysis/             audio.py, transcription.py, features.py, dsp.py,
                            embeddings.py, trends.py, summary.py, pipeline.py
  app/database.py           SQLite history
voice_health/
  lib/screens/              home (dashboard), record, trends, settings
  lib/services/             app_store, api_service, recorder_service, report_builder
  lib/models/               analysis_result
```

## Notes

- **$0 by design**: local Whisper, Praat via parselmouth, numpy/scipy DSP,
  template-based summaries. No accounts, no API keys, no cloud.
- The DSP layer (`app/analysis/dsp.py`) is deliberately numba/librosa-free:
  Windows Smart App Control blocks numba's unsigned DLLs.
- Recordings stay on the phone (`documents/recordings/`); analysis history is
  cached on the phone and mirrored in the backend's SQLite file.
- Privacy: users are identified only by a random anonymous ID.
