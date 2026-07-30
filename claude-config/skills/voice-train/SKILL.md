---
name: voice-train
description: 유튜브 영상들에서 보컬을 추출해 RVC 목소리 모델 학습 — Google Colab + Applio
user_invocable: true
---

유튜브 영상에서 보컬을 추출하고 RVC v2 모델을 학습하는 스킬.

## 중요: NVIDIA GPU 필수
RVC 학습은 NVIDIA GPU(CUDA)가 필수. CPU로는 현실적으로 불가능 (며칠~몇 주 소요).
Darren 집컴은 AMD RX 6600이라 CUDA 미지원 → **Google Colab 무료 T4 GPU** 사용.

## 파이프라인

### Phase 1: 로컬에서 보컬 추출 (니노가 수행)

```bash
WORK_DIR=/tmp/voice-cover
SINGER="가수이름"
DATASET_DIR="$WORK_DIR/dataset/$SINGER"
mkdir -p "$DATASET_DIR"
cd $WORK_DIR

# 1. 유튜브에서 다운로드
for i in 1 2 3 4 5; do
  yt-dlp -x --audio-format wav --audio-quality 0 -o "$WORK_DIR/raw_${i}.%(ext)s" "유튜브URL_$i"
done

# 2. demucs로 보컬 분리
source $WORK_DIR/.venv/bin/activate
for f in $WORK_DIR/raw_*.wav; do
  demucs --two-stems=vocals -n htdemucs_ft -o "$WORK_DIR/separated" "$f"
done

# 3. 보컬 파일을 데이터셋 폴더로 복사
i=1; for d in $WORK_DIR/separated/htdemucs_ft/raw_*/; do
  cp "$d/vocals.wav" "$DATASET_DIR/vocal_${i}.wav"
  i=$((i+1))
done

# 4. zip으로 묶어서 catbox.moe 업로드 (Colab에서 다운로드용)
cd $WORK_DIR/dataset
zip -r "${SINGER}_dataset.zip" "$SINGER/"
curl -F "reqtype=fileupload" -F "fileToUpload=@${SINGER}_dataset.zip" https://catbox.moe/user/api.php
```

### Phase 2: Google Colab에서 학습 (니노가 agent-browser로 자동화)

Colab 노트북 열기: https://colab.research.google.com/
Runtime → Change runtime type → **GPU (T4)** 선택

#### 셀 1: Applio 설치 + 모델 다운로드
```python
%cd /content
!git config --global advice.detachedHead false
!git clone https://github.com/IAHispano/Applio/ --branch 3.6.2 --single-branch
%cd /content/Applio
!pip install -q -r requirements.txt --extra-index-url https://download.pytorch.org/whl/cu128
!pip install -q wget torchfcpe torchcrepe
!python core.py "prerequisites" --models "True" --pretraineds_hifigan "True"
```

#### 셀 2: Google Drive 마운트 + 데이터셋 다운로드
```python
from google.colab import drive
drive.mount('/content/drive')

import os
SINGER = "가수이름"
DRIVE_MODEL_DIR = f"/content/drive/MyDrive/voice-models/{SINGER}"
os.makedirs(DRIVE_MODEL_DIR, exist_ok=True)

# catbox에서 데이터셋 다운로드
!wget -q "https://files.catbox.moe/XXXXXX.zip" -O /tmp/dataset.zip
!mkdir -p /content/Applio/logs/{SINGER}
!unzip -q /tmp/dataset.zip -d /content/dataset_tmp
!mv /content/dataset_tmp/{SINGER}/* /content/Applio/logs/{SINGER}/ 2>/dev/null || true
```

#### 셀 3: Preprocess
```bash
cd /content/Applio && python rvc/train/preprocess/preprocess.py \
  logs/가수이름 \
  logs/가수이름 \
  40000 \
  4 \
  Simple \
  False \
  False \
  0 \
  3.0 \
  0.3 \
  None
```
**주의**: `cut_preprocess`는 반드시 `Simple` 사용. `Cut`은 Applio에 없는 값이라 0개 파일 생성됨.

#### 셀 4: F0 + Embedding 추출 (standalone 스크립트)
**주의**: 이 코드는 반드시 `.py` 파일로 저장 후 `!python` 으로 실행할 것.
Colab 노트북 셀에서 인라인 실행하면 커널이 크래시됨.

```python
# /content/extract_all.py 로 저장 후 !python /content/extract_all.py 실행
import os, sys, glob, numpy as np, torch
os.chdir('/content/Applio')
sys.path.append('/content/Applio')

SINGER = "가수이름"
LOGS = f'/content/Applio/logs/{SINGER}'
os.makedirs(os.path.join(LOGS, 'f0'), exist_ok=True)
os.makedirs(os.path.join(LOGS, 'f0_voiced'), exist_ok=True)
os.makedirs(os.path.join(LOGS, 'extracted'), exist_ok=True)

device = 'cuda:0'
wav_path = os.path.join(LOGS, 'sliced_audios_16k')
files = sorted(glob.glob(os.path.join(wav_path, '*.wav')))
print(f"총 {len(files)}개 파일 처리")

# F0 extraction (RMVPE)
from rvc.lib.utils import load_audio_16k
from rvc.lib.predictors.f0 import RMVPE
rmvpe = RMVPE(device=device, sample_rate=16000, hop_size=160)
f0_dir = os.path.join(LOGS, 'f0')
f0v_dir = os.path.join(LOGS, 'f0_voiced')
f0_bin, f0_max, f0_min = 256, 1100.0, 50.0
f0_mel_min = 1127 * np.log(1 + f0_min / 700)
f0_mel_max = 1127 * np.log(1 + f0_max / 700)

for i, fp in enumerate(files):
    fname = os.path.basename(fp)
    try:
        audio = load_audio_16k(fp)
        f0 = rmvpe.get_f0(audio, filter_radius=0.03)
        np.save(os.path.join(f0v_dir, fname + '.npy'), f0, allow_pickle=False)
        f0_mel = 1127.0 * np.log(1.0 + f0 / 700.0)
        f0_mel = np.clip((f0_mel - f0_mel_min) * (f0_bin - 2) / (f0_mel_max - f0_mel_min) + 1, 1, f0_bin - 1)
        np.save(os.path.join(f0_dir, fname + '.npy'), np.rint(f0_mel).astype(int), allow_pickle=False)
    except Exception as e:
        print(f'F0 err {fname}: {e}')
    if (i+1) % 50 == 0:
        print(f'F0: {i+1}/{len(files)}')

print(f"F0 완료: {len(os.listdir(f0_dir))}개")

# Embeddings (korean-hubert-base)
from rvc.lib.utils import load_embedding
model = load_embedding('korean-hubert-base', None).to(device).float()
model.eval()
extracted_dir = os.path.join(LOGS, 'extracted')

for i, fp in enumerate(files):
    fname = os.path.basename(fp)
    out = os.path.join(extracted_dir, fname.replace('.wav', '.npy'))
    if os.path.exists(out): continue
    feats = torch.from_numpy(load_audio_16k(fp)).to(device).float().view(1,-1)
    with torch.no_grad():
        r = model(feats)['last_hidden_state']
    np.save(out, r.squeeze(0).float().cpu().numpy(), allow_pickle=False)
    if (i+1) % 50 == 0:
        print(f'Embed: {i+1}/{len(files)}')

print(f"Embedding 완료: {len(os.listdir(extracted_dir))}개")

# Config + Filelist 생성
from rvc.train.extract.preparing_files import generate_config, generate_filelist
generate_config('40000', LOGS)
generate_filelist(LOGS, '40000', 2)
print("Config + Filelist 생성 완료!")
```

#### 셀 5: Train
```bash
cd /content/Applio && python rvc/train/train.py \
  가수이름 \
  25 \
  300 \
  rvc/models/pretraineds/hifi-gan/f0G40k.pth \
  rvc/models/pretraineds/hifi-gan/f0D40k.pth \
  0 \
  8 \
  40000 \
  False \
  True \
  False \
  True \
  50 \
  False \
  HiFi-GAN \
  False
```
- `save_every_epoch=25`: 25 에폭마다 체크포인트 저장 (런타임 끊김 대비)
- `overtraining_detector=True, threshold=50`: 50 에폭 개선 없으면 자동 중단

#### 셀 6: 모델을 Google Drive에 복사
```python
import shutil, glob
SINGER = "가수이름"
DRIVE_DIR = f"/content/drive/MyDrive/voice-models/{SINGER}"
os.makedirs(DRIVE_DIR, exist_ok=True)

# .pth 모델
for f in glob.glob(f"/content/Applio/logs/{SINGER}/*.pth"):
    shutil.copy2(f, DRIVE_DIR)
    print(f"복사: {f} → {DRIVE_DIR}")

# .index 파일
for f in glob.glob(f"/content/Applio/logs/{SINGER}/*.index"):
    shutil.copy2(f, DRIVE_DIR)
    print(f"복사: {f} → {DRIVE_DIR}")
```

### Phase 3: 모델 다운로드 + 저장 (니노가 수행)

```bash
MODEL_DIR=/home/bpx27/voice-models/$SINGER
mkdir -p "$MODEL_DIR"
# Google Drive에서 다운로드하거나 Discord로 파일 수신
```

## 학습 파라미터

| 항목 | 권장값 | 설명 |
|------|--------|------|
| Sample Rate | 40000 | RVC 표준 |
| Epochs | 300 | 과적합 감지기가 자동 중단 |
| Batch Size | 8 | T4 GPU에 적합 |
| Save Every | 25 | 런타임 끊김 대비 자주 저장 |
| f0 Method | rmvpe | 가장 정확한 피치 추출 |
| Embedder | korean-hubert-base | 한국어 음성 최적화 |
| Vocoder | HiFi-GAN | 검증된 보코더 |
| Overtraining Detector | ON, threshold 50 | 50 에폭 개선 없으면 자동 중단 |
| cut_preprocess | Simple | **Cut은 존재하지 않는 값** — 반드시 Simple 사용 |

## Colab 자동화 트러블슈팅

### ProcessPoolExecutor 문제
Applio의 `extract.py`는 `ProcessPoolExecutor(spawn)`을 사용하는데, Colab에서 spawn된 프로세스가 조용히 실패함.
→ **해결**: standalone `.py` 파일로 단일 프로세스에서 직접 실행

### 인라인 코드 커널 크래시
RMVPE 등 CUDA 모델을 노트북 셀에서 직접 import+실행하면 커널 크래시.
→ **해결**: 코드를 `.py` 파일로 저장 후 `!python script.py`로 실행

### 런타임 끊김
Colab 무료 티어는 언제든 끊길 수 있음. 에폭 200까지 학습 후 끊긴 경험 있음.
→ **해결**: Google Drive 마운트 + save_every_epoch=25로 자주 저장

### 데이터셋 보존
catbox.moe에 업로드해두면 런타임 리셋 후에도 빠르게 재다운로드 가능.

## 참고
- Colab 무료 티어: T4 GPU, 세션 최대 ~12시간, GPU 쿼터 초과 시 다음 날 리셋
- 학습 데이터: 3~5곡 보컬 (15~20분 분량)이 적절
- 모델 저장 위치: `/home/bpx27/voice-models/가수이름/`
- voice-cover 스킬에서 이 모델을 사용
- 조성모 데이터셋 catbox: https://files.catbox.moe/w5rway.zip (4곡 보컬)
