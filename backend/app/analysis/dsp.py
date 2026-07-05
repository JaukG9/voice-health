"""Self-contained DSP helpers: resampling, framed RMS and MFCC.

Implemented with numpy/scipy only — compiled DSP packages such as numba are
blocked by some Windows Application Control policies, and this keeps the
install small and dependency-light.
"""

from math import gcd

import numpy as np
from scipy.fft import dct
from scipy.signal import resample_poly


def resample(audio: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
    factor = gcd(orig_sr, target_sr)
    return resample_poly(audio, target_sr // factor, orig_sr // factor).astype(np.float32)


def frame_rms(audio: np.ndarray, frame_length: int, hop_length: int) -> np.ndarray:
    """RMS energy of successive overlapping frames."""
    if len(audio) < frame_length:
        return np.array([np.sqrt(np.mean(audio**2))])
    frames = np.lib.stride_tricks.sliding_window_view(audio, frame_length)[::hop_length]
    return np.sqrt(np.mean(frames**2, axis=1))


def mfcc(
    audio: np.ndarray,
    sr: int,
    n_mfcc: int = 13,
    n_mels: int = 26,
    frame_length: int = 400,
    hop_length: int = 160,
    n_fft: int = 512,
) -> np.ndarray:
    """MFCCs (n_frames x n_mfcc) via the standard mel-filterbank pipeline."""
    if len(audio) < frame_length:
        audio = np.pad(audio, (0, frame_length - len(audio)))
    frames = np.lib.stride_tricks.sliding_window_view(audio, frame_length)[::hop_length]
    frames = frames * np.hamming(frame_length)
    power = np.abs(np.fft.rfft(frames, n=n_fft, axis=1)) ** 2 / n_fft
    mel_energy = power @ _mel_filterbank(sr, n_fft, n_mels).T
    log_mel = np.log(mel_energy + 1e-10)
    return dct(log_mel, type=2, axis=1, norm="ortho")[:, :n_mfcc]


def _mel_filterbank(sr: int, n_fft: int, n_mels: int) -> np.ndarray:
    def to_mel(hz):
        return 2595 * np.log10(1 + hz / 700)

    def to_hz(mel):
        return 700 * (10 ** (mel / 2595) - 1)

    mel_points = np.linspace(to_mel(0), to_mel(sr / 2), n_mels + 2)
    bins = np.floor((n_fft + 1) * to_hz(mel_points) / sr).astype(int)
    bank = np.zeros((n_mels, n_fft // 2 + 1))
    for i in range(n_mels):
        left, center, right = bins[i], bins[i + 1], bins[i + 2]
        for j in range(left, center):
            bank[i, j] = (j - left) / (center - left)
        for j in range(center, right):
            bank[i, j] = (right - j) / (right - center)
    return bank
