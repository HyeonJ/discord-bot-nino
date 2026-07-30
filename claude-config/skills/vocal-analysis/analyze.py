#!/usr/bin/env python3
"""보컬 발성 분석 스크립트 — 피치, 포먼트, HNR, 스펙트로그램"""

import argparse
import parselmouth
from parselmouth.praat import call
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager
import os


def setup_korean_font():
    for fp in ['/usr/share/fonts/truetype/nanum/NanumGothic.ttf',
               '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc']:
        if os.path.exists(fp):
            font_manager.fontManager.addfont(fp)
            prop = font_manager.FontProperties(fname=fp)
            plt.rcParams['font.family'] = prop.get_name()
            break
    plt.rcParams['axes.unicode_minus'] = False


def hz_to_note(hz):
    if hz <= 0:
        return "N/A"
    notes = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']
    semitone = 12 * np.log2(hz / 440.0) + 69
    note_idx = int(round(semitone)) % 12
    octave = int(round(semitone)) // 12 - 1
    return f"{notes[note_idx]}{octave}"


def analyze(vocal_path, t_start, t_end, offset, title, output_path):
    snd = parselmouth.Sound(vocal_path)
    snd_section = snd.extract_part(t_start, t_end)

    # 표시용 시간 오프셋 (원곡 기준)
    display_start = t_start + offset
    display_end = t_end + offset

    # 1. 피치 분석
    pitch = call(snd_section, "To Pitch", 0.0, 75, 600)
    pitch_values = []
    pitch_times = []
    for i in range(pitch.get_number_of_frames()):
        t = pitch.get_time_from_frame_number(i + 1)
        p = pitch.get_value_in_frame(i + 1)
        if p > 0:
            pitch_times.append(t + display_start)
            pitch_values.append(p)

    if not pitch_values:
        print("ERROR: 이 구간에서 피치를 감지하지 못했습니다.")
        return

    print("=== 피치 분석 ===")
    min_p, max_p = min(pitch_values), max(pitch_values)
    print(f"최저음: {hz_to_note(min_p)} ({min_p:.1f} Hz)")
    print(f"최고음: {hz_to_note(max_p)} ({max_p:.1f} Hz)")
    print(f"평균: {np.mean(pitch_values):.1f} Hz")

    # 2. 포먼트 분석
    formant = call(snd_section, "To Formant (burg)", 0.0, 5, 5500, 0.025, 50)

    high_pitch_threshold = np.percentile(pitch_values, 80)
    print(f"\n=== 고음 구간 (>{high_pitch_threshold:.0f} Hz, {hz_to_note(high_pitch_threshold)}) ===")

    high_f1, high_f2, low_f1, low_f2 = [], [], [], []
    for i in range(pitch.get_number_of_frames()):
        t = pitch.get_time_from_frame_number(i + 1)
        p = pitch.get_value_in_frame(i + 1)
        if p > 0:
            f1 = call(formant, "Get value at time", 1, t, "Hertz", "Linear")
            f2 = call(formant, "Get value at time", 2, t, "Hertz", "Linear")
            if f1 > 0 and f2 > 0:
                if p >= high_pitch_threshold:
                    high_f1.append(f1)
                    high_f2.append(f2)
                else:
                    low_f1.append(f1)
                    low_f2.append(f2)

    if high_f1:
        print(f"고음 F1 평균: {np.mean(high_f1):.0f} Hz (입 열림 정도)")
        print(f"고음 F2 평균: {np.mean(high_f2):.0f} Hz (혀 위치)")
    if low_f1:
        print(f"저음 F1 평균: {np.mean(low_f1):.0f} Hz")
        print(f"저음 F2 평균: {np.mean(low_f2):.0f} Hz")
    if high_f1 and low_f1:
        f1_diff = np.mean(high_f1) - np.mean(low_f1)
        f2_diff = np.mean(high_f2) - np.mean(low_f2)
        print(f"\n고음 vs 저음 차이:")
        print(f"  F1 차이: {f1_diff:+.0f} Hz ({'입을 더 크게 열음' if f1_diff > 0 else '입을 더 좁게 닫음'})")
        print(f"  F2 차이: {f2_diff:+.0f} Hz ({'혀가 더 앞으로' if f2_diff > 0 else '혀가 더 뒤로'})")

    # 3. HNR
    hnr = call(snd_section, "To Harmonicity (cc)", 0.01, 75, 0.1, 1.0)
    print(f"\n=== 음질 분석 ===")
    hnr_values = []
    for i in range(hnr.get_number_of_frames()):
        v = call(hnr, "Get value in frame", i + 1)
        if v > -200:
            hnr_values.append(v)
    if hnr_values:
        print(f"HNR 평균: {np.mean(hnr_values):.1f} dB (높을수록 깨끗한 발성)")
        print(f"HNR 범위: {min(hnr_values):.1f} ~ {max(hnr_values):.1f} dB")

    # 4. 최고음 부근 상세
    max_pitch_idx = np.argmax(pitch_values)
    max_pitch_time = pitch_times[max_pitch_idx]
    print(f"\n=== 최고음 상세 ===")
    mins = int(max_pitch_time) // 60
    secs = max_pitch_time % 60
    print(f"최고음 시점: {mins}:{secs:04.1f}")
    print(f"최고음: {pitch_values[max_pitch_idx]:.1f} Hz ({hz_to_note(pitch_values[max_pitch_idx])})")

    window = 0.3
    nearby = [(t, p) for t, p in zip(pitch_times, pitch_values)
              if abs(t - max_pitch_time) < window]
    if len(nearby) > 2:
        pitches_n = [x[1] for x in nearby]
        times_n = [x[0] for x in nearby]
        rise_rate = (max(pitches_n) - min(pitches_n)) / (max(times_n) - min(times_n) + 0.001)
        print(f"피치 변화율: {rise_rate:.0f} Hz/sec")

    # 5. 시각화
    setup_korean_font()
    fig, axes = plt.subplots(4, 1, figsize=(14, 12), sharex=True)
    fig.suptitle(f"'{title}' 보컬 분석", fontsize=14)

    # 스펙트로그램
    ax = axes[0]
    spectrogram = call(snd_section, "To Spectrogram", 0.005, 5000, 0.002, 20, "Gaussian")
    X = np.array([[call(spectrogram, "Get power at", t, f)
                   for t in np.linspace(0, snd_section.duration, 500)]
                  for f in np.linspace(0, 5000, 200)])
    ax.imshow(10 * np.log10(X + 1e-10), aspect='auto', origin='lower',
              extent=[display_start, display_end, 0, 5000], cmap='magma')
    ax.set_ylabel('Frequency (Hz)')
    ax.set_title('스펙트로그램')

    # 피치
    ax = axes[1]
    ax.plot(pitch_times, pitch_values, 'b-', linewidth=1.5)
    ax.axhline(y=high_pitch_threshold, color='r', linestyle='--', alpha=0.5,
               label=f'고음 기준 ({high_pitch_threshold:.0f} Hz)')
    ax.set_ylabel('Pitch (Hz)')
    ax.set_title('피치 (음높이) 변화')
    ax.legend()
    for note_hz in [220, 261.6, 329.6, 392, 440, 523.3, 587.3, 659.3]:
        note = hz_to_note(note_hz)
        ax.axhline(y=note_hz, color='gray', linestyle=':', alpha=0.3)
        ax.text(display_start + 0.1, note_hz + 5, note, fontsize=8, color='gray')

    # 포먼트
    ax = axes[2]
    formant_times, f1_vals, f2_vals = [], [], []
    for i in range(formant.get_number_of_frames()):
        t = formant.get_time_from_frame_number(i + 1)
        f1 = call(formant, "Get value at time", 1, t, "Hertz", "Linear")
        f2 = call(formant, "Get value at time", 2, t, "Hertz", "Linear")
        if f1 > 0 and f2 > 0:
            formant_times.append(t + display_start)
            f1_vals.append(f1)
            f2_vals.append(f2)
    ax.plot(formant_times, f1_vals, 'r-', label='F1 (입 열림)', linewidth=1)
    ax.plot(formant_times, f2_vals, 'g-', label='F2 (혀 위치)', linewidth=1)
    ax.set_ylabel('Frequency (Hz)')
    ax.set_title('포먼트 (발성 방법)')
    ax.legend()

    # 인텐시티
    ax = axes[3]
    intensity = call(snd_section, "To Intensity", 100, 0.0)
    int_times = np.linspace(0, snd_section.duration, 500)
    int_values = [call(intensity, "Get value at time", t, "cubic") for t in int_times]
    ax.plot(int_times + display_start, int_values, 'purple', linewidth=1)
    ax.set_ylabel('Intensity (dB)')
    ax.set_xlabel('Time (sec)')
    ax.set_title('음량 변화')

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"\n차트 저장: {output_path}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='보컬 발성 분석')
    parser.add_argument('--vocal', required=True, help='보컬 분리된 wav 파일 경로')
    parser.add_argument('--start', type=float, required=True, help='분석 시작 시간 (section.wav 기준, 초)')
    parser.add_argument('--end', type=float, required=True, help='분석 끝 시간 (section.wav 기준, 초)')
    parser.add_argument('--offset', type=float, default=0, help='원곡 기준 오프셋 (초). section.wav가 원곡 몇 초부터인지')
    parser.add_argument('--title', default='보컬 분석', help='차트 제목 (가사 등)')
    parser.add_argument('--output', default='analysis_result.png', help='출력 이미지 경로')
    args = parser.parse_args()
    analyze(args.vocal, args.start, args.end, args.offset, args.title, args.output)
