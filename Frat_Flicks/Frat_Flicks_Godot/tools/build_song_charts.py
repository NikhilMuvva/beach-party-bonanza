#!/usr/bin/env python3
"""Offline audio analysis; runtime requires no analysis dependencies.
Rebuild: pip install librosa==0.11.0 numpy==1.26.4 scipy
Targets follow detected beats with >=0.85 s overall / >=1.3 s per-hand spacing.
"""
from pathlib import Path
import json
import hashlib
import librosa
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = ["LRLRLLRR", "LLRRLRRL", "LRRLRLLR", "LRLLRLRR", "RLLRRLRL"]

def build():
    playlist = json.loads((ROOT/'assets/audio/title_playlist.json').read_text())
    report = []
    for index, entry in enumerate(playlist):
        source = ROOT/entry['path'].removeprefix('res://')
        key = source.stem
        y, sr = librosa.load(source, sr=22050)
        hop = 220
        onset = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
        tempo, frames = librosa.beat.beat_track(onset_envelope=onset, sr=sr, hop_length=hop, trim=True)
        times = librosa.frames_to_time(frames, sr=sr, hop_length=hop)
        # Beat tracking gives a coherent grid; snap within 60 ms to the local
        # percussive attack to compensate for onset-envelope frame alignment.
        peaks = librosa.onset.onset_detect(onset_envelope=onset, sr=sr, hop_length=hop, units='time')
        beats = []
        last = -10.0
        hand_last = {'L': -10.0, 'R': -10.0}
        pattern = PATTERNS[index]
        for t in times:
            if len(peaks):
                nearest = float(peaks[np.argmin(abs(peaks-t))])
                if abs(nearest-t) <= .06:
                    t = nearest
            t = round(float(t), 4)
            if t < 2.4 or t > len(y)/sr-.65 or t-last < .85:
                continue
            hand = pattern[len(beats) % len(pattern)]
            if t-hand_last[hand] < 1.3:
                continue
            strength = float(onset[min(len(onset)-1, round(t*sr/hop))])
            beats.append({'t': t, 'lane': 'down' if hand=='L' else 'up', 'strength': round(min(1.,strength/max(float(onset.max()),.001)),3)})
            last=t
            hand_last[hand]=t
        assert len(beats)>10, source
        data={'name':entry['name'], 'artist':entry['artist'], 'audio':entry['path'],
              'bpm':round(float(np.asarray(tempo).item()),3), 'duration':round(len(y)/sr,4),
              'analysis':'librosa beat tracking, locally snapped to onsets; sparse phrase patterns',
              'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
              'pattern':pattern, 'detected_beats':[round(float(t),4) for t in times], 'beats':beats}
        (ROOT/f'assets/beatmaps/{key}.json').write_text(json.dumps(data,indent=2)+'\n')
        report.append({k:data[k] for k in ['name','bpm','duration','pattern'] } | {'targets':len(beats)})
        print(report[-1],flush=True)
    (ROOT/'docs/SONG_ANALYSIS.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__': build()
