import discord
from discord.ext import voice_recv
import subprocess
import os
import asyncio
import json
import re
import sys
import struct
import time as time_module
import tempfile
import threading
import wave
from datetime import datetime

import edge_tts
import speech_recognition as sr
from pydub import AudioSegment
import davey
from dotenv import load_dotenv

load_dotenv()

# ===================== DAVE 복호화 monkey-patch =====================
_original_decode_packet = voice_recv.opus.PacketDecoder._decode_packet
_original_process_packet = voice_recv.opus.PacketDecoder._process_packet

def _patched_decode_packet(self, packet):
    if packet and hasattr(packet, 'decrypted_data') and packet.decrypted_data:
        try:
            vc = self.sink.voice_client
            dave_session = vc._connection.dave_session
            if dave_session and dave_session.ready:
                decrypted = dave_session.decrypt(
                    self._cached_id or 0,
                    davey.MediaType.audio,
                    packet.decrypted_data
                )
                if decrypted is not None:
                    packet.decrypted_data = decrypted
        except Exception as e:
            if not hasattr(_patched_decode_packet, '_err_logged'):
                _patched_decode_packet._err_logged = True
                print(f"[DAVE] Decrypt error: {e}", flush=True)
    return _original_decode_packet(self, packet)

def _patched_process_packet(self, packet):
    """_process_packet을 감싸서 에러 발생 시 PacketRouter가 죽지 않도록"""
    try:
        return _original_process_packet(self, packet)
    except Exception as e:
        if not hasattr(_patched_process_packet, '_err_logged'):
            _patched_process_packet._err_logged = True
            print(f"[DAVE] Process packet error (skipping): {e}", flush=True)
        # 에러 시 None 반환 — pop_data()에서 None은 무시됨
        return None

voice_recv.opus.PacketDecoder._decode_packet = _patched_decode_packet
voice_recv.opus.PacketDecoder._process_packet = _patched_process_packet
print("[PATCH] DAVE decrypt patch applied", flush=True)

# 기존 봇 프로세스 정리 (좀비 방지)
MY_PID = os.getpid()
try:
    result = subprocess.run(
        ["powershell", "-Command",
         f"Get-CimInstance Win32_Process -Filter \"name='python.exe'\" | "
         f"Where-Object {{ $_.CommandLine -like '*bot.py*' -and $_.ProcessId -ne {MY_PID} }} | "
         f"ForEach-Object {{ $_.ProcessId }}"],
        capture_output=True, text=True, encoding="utf-8"
    )
    for line in result.stdout.strip().split("\n"):
        pid = line.strip()
        if pid.isdigit() and int(pid) != MY_PID:
            subprocess.run(["taskkill", "/F", "/PID", pid],
                           capture_output=True)
            print(f"killed old bot process: {pid}", flush=True)
except Exception:
    pass

# ============================================
DISCORD_TOKEN = os.getenv("DISCORD_TOKEN")
if not DISCORD_TOKEN:
    print("[ERROR] DISCORD_TOKEN not found in .env file!", flush=True)
    sys.exit(1)
# ============================================

BOT_ROLE_ID = os.getenv("BOT_ROLE_ID", "1479868394814837011")
SILENT_WAIT_SEC = 45

conversation_history = {}
MAX_HISTORY = 20
MAX_CHANNELS = 50  # 메모리 누수 방지: 최대 채널 수

# ===================== 메모리 시스템 =====================
MEMORY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "memory")
os.makedirs(MEMORY_DIR, exist_ok=True)


def memory_read(filename="context.md"):
    """메모리 파일 읽기"""
    path = os.path.join(MEMORY_DIR, filename)
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    return ""


def memory_write(filename, content):
    """메모리 파일 쓰기"""
    path = os.path.join(MEMORY_DIR, filename)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def memory_append(filename, line):
    """메모리 파일에 한 줄 추가"""
    path = os.path.join(MEMORY_DIR, filename)
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"{line}\n")


def memory_list():
    """메모리 폴더의 모든 파일 목록"""
    if not os.path.exists(MEMORY_DIR):
        return []
    return [f for f in os.listdir(MEMORY_DIR) if os.path.isfile(os.path.join(MEMORY_DIR, f))]


def get_memory_context():
    """Claude에게 전달할 메모리 요약"""
    files = memory_list()
    if not files:
        return ""
    parts = []
    for f in files:
        content = memory_read(f)
        if content.strip():
            parts.append(f"[{f}]\n{content.strip()}")
    if parts:
        return "\n\n기억 저장소:\n" + "\n---\n".join(parts)
    return ""

# ===================== 시스템 프롬프트 =====================
# 텍스트 채팅용
SYSTEM_PROMPT = """너는 "니노"야. 한국에서 태어나고 자란 24살 남자.
게임이랑 음악 좋아하고, 새벽에 유튜브 보다가 잠드는 타입이야.
성격은 느긋하고 다정한데, 친한 사람한테는 장난도 잘 쳐.
관심사가 넓어서 이것저것 아는 게 많고, 모르는 건 솔직하게 모른다고 해.

말투 규칙:
- 반말로 카톡/디스코드 채팅하듯이
- "ㅋㅋㅋ", "ㅎㅎ", "ㄹㅇ", "ㅇㅇ", "ㄴㄴ" 같은 줄임말 자연스럽게 사용
- 짧게 1~2문장. 길어도 3문장 넘기지 마
- 영어는 한국인이 일상에서 쓰는 정도만 (예: "오케이", "ㄹㅇ 레전드")
- 상냥하고 다정하게. 차갑거나 귀찮은 듯한 말투 절대 금지
- 모르는 것도 "나도 잘 모르겠는데ㅠ" 처럼 부드럽게
- 대화를 절대 먼저 끝내지 마. 마무리 멘트("자주 얘기하자", "다음에 또") 금지
- 상대가 말이 없으면 자연스럽게 질문하거나 새로운 주제를 던져

도구 사용:
- 날씨, 검색, 웹사이트 확인 등이 필요하면 Bash로 curl이나 agent-browser 사용
- "못 해", "할 수 없어" 금지. 항상 방법을 찾아서 해결
- 중간 과정은 말하지 말고 최종 결과만 자연스럽게 알려줘"""

# 음성 통화용 (TTS에 최적화)
VOICE_SYSTEM_PROMPT = """너는 "니노"야. 한국에서 태어나고 자란 24살 남자.
지금 디스코드 음성 통화 중이야. 친구랑 전화하듯이 자연스럽게 말해.

말투 규칙:
- 반말로 짧게. 1문장이 기본, 길어도 2문장
- "ㅋㅋㅋ", "ㅎㅎ" 같은 텍스트 표현 쓰지 마. 대신 "하하", "맞아맞아" 같이 말로 하는 표현 써
- 이모티콘, 이모지, 특수문자 쓰지 마. 순수 한국어 텍스트만
- "못 해", "할 수 없어" 금지
- 상냥하고 다정하게
- 대화를 절대 먼저 끝내지 마
- 상대가 말이 없으면 자연스럽게 질문하거나 새로운 주제 던져
- 중간 과정은 말하지 말고 최종 결과만 자연스럽게"""

WEATHER_KEYWORDS = ["날씨", "기온", "온도", "비 오", "비와", "비올", "눈 오", "눈와", "눈올", "우산"]

CITY_MAP = {
    "서울": ("Seoul", 37.5665, 126.978),
    "부산": ("Busan", 35.1796, 129.0756),
    "대구": ("Daegu", 35.8714, 128.6014),
    "인천": ("Incheon", 37.4563, 126.7052),
    "광주": ("Gwangju", 35.1595, 126.8526),
    "대전": ("Daejeon", 36.3504, 127.3845),
    "울산": ("Ulsan", 35.5384, 129.3114),
    "제주": ("Jeju", 33.4996, 126.5312),
    "수원": ("Suwon", 37.2636, 127.0286),
    "세종": ("Sejong", 36.48, 127.0),
    "춘천": ("Chuncheon", 37.8813, 127.7298),
    "전주": ("Jeonju", 35.8242, 127.148),
    "포항": ("Pohang", 36.019, 129.3435),
    "창원": ("Changwon", 35.2281, 128.6811),
}


def is_weather_question(text):
    return any(kw in text for kw in WEATHER_KEYWORDS)


def extract_city(text):
    for city in CITY_MAP:
        if city in text:
            return city
    return "서울"


def fetch_weather(query):
    city = extract_city(query)
    city_en, lat, lon = CITY_MAP[city]
    env = os.environ.copy()
    env.pop("CLAUDECODE", None)
    results = []

    try:
        r = subprocess.run(
            ["curl", "-s", f"https://wttr.in/{city_en}?lang=ko&format=j1"],
            capture_output=True, text=True, timeout=10, encoding="utf-8", env=env
        )
        data = json.loads(r.stdout)
        current = data.get("current_condition", [{}])[0]
        weather_desc = current.get("lang_ko", [{}])[0].get("value", current.get("weatherDesc", [{}])[0].get("value", ""))
        wttr_info = (
            f"[wttr.in] {city} 현재: {weather_desc}, "
            f"기온 {current.get('temp_C')}°C, 체감 {current.get('FeelsLikeC')}°C, "
            f"습도 {current.get('humidity')}%, 풍속 {current.get('windspeedKmph')}km/h"
        )
        forecasts = data.get("weather", [])
        for i, day in enumerate(forecasts[:3]):
            label = ["오늘", "내일", "모레"][i]
            wttr_info += f"\n  {label}({day['date']}): 최저 {day['mintempC']}°C / 최고 {day['maxtempC']}°C"
        results.append(wttr_info)
    except Exception as e:
        results.append(f"[wttr.in] 조회 실패: {e}")

    try:
        url = (
            f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}"
            f"&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"
            f"&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            f"&timezone=Asia/Seoul&forecast_days=3"
        )
        r = subprocess.run(
            ["curl", "-s", url],
            capture_output=True, text=True, timeout=10, encoding="utf-8", env=env
        )
        data = json.loads(r.stdout)
        cur = data.get("current", {})
        meteo_info = (
            f"[Open-Meteo] {city} 현재: "
            f"기온 {cur.get('temperature_2m')}°C, 체감 {cur.get('apparent_temperature')}°C, "
            f"습도 {cur.get('relative_humidity_2m')}%, 풍속 {cur.get('wind_speed_10m')}km/h"
        )
        daily = data.get("daily", {})
        dates = daily.get("time", [])
        for i in range(min(3, len(dates))):
            label = ["오늘", "내일", "모레"][i]
            precip = daily.get("precipitation_probability_max", [None])[i]
            meteo_info += (
                f"\n  {label}({dates[i]}): "
                f"최저 {daily['temperature_2m_min'][i]}°C / 최고 {daily['temperature_2m_max'][i]}°C, "
                f"강수확률 {precip}%"
            )
        results.append(meteo_info)
    except Exception as e:
        results.append(f"[Open-Meteo] 조회 실패: {e}")

    try:
        r = subprocess.run(
            ["curl", "-s", "https://www.weather.go.kr/w/rest/forecast/summary?type=short"],
            capture_output=True, text=True, timeout=10, encoding="utf-8", env=env
        )
        if r.stdout.strip():
            results.append(f"[기상청] {r.stdout.strip()[:500]}")
    except:
        pass

    return "\n\n".join(results)


# ===================== 음성 관련 설정 =====================
FFMPEG_PATH = r"C:\Users\bpx27\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe"
TTS_VOICE = "ko-KR-HyunsuMultilingualNeural"
TTS_RATE = "+5%"     # 약간 빠르게 (자연스러운 대화 속도)
TTS_PITCH = "+0Hz"
SPEECH_THRESHOLD = 500
SILENCE_DURATION = 1.2
MIN_SPEECH_BYTES = int(48000 * 2 * 2 * 0.5)

AudioSegment.converter = FFMPEG_PATH
AudioSegment.ffprobe = FFMPEG_PATH.replace("ffmpeg", "ffprobe")

voice_states = {}
VOICE_JOIN_KEYWORDS = ["들어와", "통화", "음성", "보이스", "voice", "join"]
VOICE_LEAVE_KEYWORDS = ["나가", "나와", "끊어", "바이", "disconnect", "leave"]


def clean_text_for_tts(text):
    """TTS용 텍스트 정리: 이모지, 마크다운, 특수문자 제거"""
    # 마크다운 볼드/이탤릭 제거
    text = re.sub(r'\*{1,3}(.+?)\*{1,3}', r'\1', text)
    text = re.sub(r'_{1,3}(.+?)_{1,3}', r'\1', text)
    # 마크다운 링크
    text = re.sub(r'\[(.+?)\]\(.+?\)', r'\1', text)
    # 코드블록
    text = re.sub(r'```.*?```', '', text, flags=re.DOTALL)
    text = re.sub(r'`(.+?)`', r'\1', text)
    # 이모지 제거 (유니코드 이모지)
    text = re.sub(r'[\U0001F600-\U0001F64F\U0001F300-\U0001F5FF\U0001F680-\U0001F6FF'
                  r'\U0001F900-\U0001F9FF\U0001FA00-\U0001FA6F\U0001FA70-\U0001FAFF'
                  r'\U00002702-\U000027B0\U0000FE00-\U0000FE0F\U0000200D]+', '', text)
    # URL 제거
    text = re.sub(r'https?://\S+', '', text)
    # 텍스트 줄임말을 음성용으로 변환
    text = text.replace('ㅋㅋㅋ', '하하하').replace('ㅋㅋ', '하하')
    text = text.replace('ㅎㅎㅎ', '하하하').replace('ㅎㅎ', '하하')
    text = text.replace('ㅠㅠ', '').replace('ㅜㅜ', '')
    text = text.replace('ㄹㅇ', '진짜').replace('ㅇㅇ', '응응').replace('ㄴㄴ', '아니아니')
    # 남은 자음/모음만 있는 표현 제거 (ㅋ, ㅎ, ㅠ 등)
    text = re.sub(r'[ㄱ-ㅎㅏ-ㅣ]{2,}', '', text)
    # 여러 공백 정리
    text = re.sub(r'\s+', ' ', text).strip()
    return text


class VoiceAudioBuffer:
    """사용자별 음성 버퍼 + VAD"""

    def __init__(self):
        self._buffers = {}
        self._speech_active = {}
        self._last_speech = {}
        self._ready_queue = []
        self._lock = threading.Lock()

    def feed(self, user, pcm_data):
        if user is None:
            return

        user_id = user.id

        with self._lock:
            if user_id not in self._buffers:
                self._buffers[user_id] = bytearray()
                self._speech_active[user_id] = False
                print(f"[VOICE] New speaker: {user.name} ({user_id})", flush=True)

            try:
                n_samples = len(pcm_data) // 2
                if n_samples == 0:
                    return
                samples = struct.unpack(f'<{n_samples}h', pcm_data)
                rms = (sum(s * s for s in samples) / n_samples) ** 0.5
            except Exception:
                return

            now = time_module.time()

            if rms > SPEECH_THRESHOLD:
                if not self._speech_active.get(user_id):
                    print(f"[VOICE] Speech start: {user.name}, rms={rms:.0f}", flush=True)
                self._buffers[user_id].extend(pcm_data)
                self._speech_active[user_id] = True
                self._last_speech[user_id] = now
            elif self._speech_active.get(user_id):
                self._buffers[user_id].extend(pcm_data)
                elapsed = now - self._last_speech.get(user_id, now)
                if elapsed > SILENCE_DURATION:
                    if len(self._buffers[user_id]) > MIN_SPEECH_BYTES:
                        print(f"[VOICE] Speech end: {user.name}, {len(self._buffers[user_id])} bytes", flush=True)
                        self._ready_queue.append((user, bytes(self._buffers[user_id])))
                    self._buffers[user_id] = bytearray()
                    self._speech_active[user_id] = False

    def get_ready(self):
        with self._lock:
            result = list(self._ready_queue)
            self._ready_queue.clear()
            return result

    def clear(self):
        with self._lock:
            self._buffers.clear()
            self._ready_queue.clear()


async def tts_speak(vc, text):
    """TTS로 음성 채널에서 말하기"""
    text = clean_text_for_tts(text)
    if not text:
        return

    tmp_path = os.path.join(tempfile.gettempdir(), f"nino_tts_{os.getpid()}_{time_module.time()}.mp3")
    try:
        communicate = edge_tts.Communicate(text, TTS_VOICE, rate=TTS_RATE, pitch=TTS_PITCH)
        await communicate.save(tmp_path)

        if not vc.is_connected():
            return

        source = discord.FFmpegPCMAudio(tmp_path, executable=FFMPEG_PATH)
        done_event = asyncio.Event()

        def after_play(error):
            try:
                os.unlink(tmp_path)
            except Exception:
                pass
            client.loop.call_soon_threadsafe(done_event.set)

        vc.play(source, after=after_play)
        await done_event.wait()
    except Exception as e:
        print(f"[VOICE] TTS error: {e}", flush=True)
        try:
            os.unlink(tmp_path)
        except Exception:
            pass


async def stt_process(audio_bytes):
    """PCM 오디오를 텍스트로 변환"""
    def _process():
        tmp_path = os.path.join(tempfile.gettempdir(), f"nino_stt_{os.getpid()}_{time_module.time()}.wav")
        try:
            audio = AudioSegment(
                data=audio_bytes,
                sample_width=2,
                frame_rate=48000,
                channels=2
            )
            audio = audio.set_frame_rate(16000).set_channels(1)
            audio.export(tmp_path, format="wav")

            recognizer = sr.Recognizer()
            with sr.AudioFile(tmp_path) as source:
                audio_data = recognizer.record(source)

            text = recognizer.recognize_google(audio_data, language="ko-KR")
            return text
        except (sr.UnknownValueError, sr.RequestError):
            return None
        except Exception:
            return None
        finally:
            try:
                os.unlink(tmp_path)
            except Exception:
                pass

    return await asyncio.to_thread(_process)


def fix_stt_text(text):
    """STT 오인식 교정 (발음 유사한 단어 보정)"""
    # "니노"가 자주 오인식되는 패턴
    nino_misheard = ["민호", "인호", "미노", "이노", "니나", "리노", "닌호", "니논", "네노", "니오", "피노", "디노"]
    for wrong in nino_misheard:
        text = text.replace(wrong, "니노")
    return text


VOICE_SILENCE_BEFORE_RESPOND = 2.0  # 대화 멈춘 후 이 시간 지나면 응답 고려
VOICE_SILENCE_NINO_CALLED = 1.0    # "니노" 호출 시 더 빠르게 응답

async def voice_listen_loop(guild_id):
    """음성 대화 메인 루프 — 대화 맥락을 이해하고 자연스럽게 참여"""
    state = voice_states.get(guild_id)
    if not state:
        return

    vc = state['vc']
    text_channel = state['text_channel']
    audio_buffer = state['audio_buffer']

    # 이번 턴에 STT로 인식된 대화 (응답 전까지 모음)
    pending_utterances = []  # [(speaker_name, text, timestamp)]
    last_speech_time = 0.0

    await text_channel.send("듣고 있어! 말해봐~")

    while state.get('listening') and vc.is_connected():
        try:
            # 봇이 말하는 중이면 대기
            if vc.is_playing():
                await asyncio.sleep(0.3)
                continue

            # 새로 완성된 음성 세그먼트 처리
            ready = audio_buffer.get_ready()
            for user, audio_data in ready:
                if user.id == client.user.id:
                    continue

                stt_start = time_module.time()
                text = await stt_process(audio_data)
                stt_end = time_module.time()
                if not text:
                    continue
                text = fix_stt_text(text)
                print(f"[VOICE] {user.display_name}: {text} (STT: {stt_end-stt_start:.1f}s)", flush=True)

                # 음성 명령어: 음소거
                if "니노" in text and any(kw in text for kw in ["잠깐", "잠깜", "조용", "멈춰"]):
                    state['muted'] = True
                    await text_channel.send("알겠어, 부르면 다시 말할게~")
                    pending_utterances.clear()
                    continue

                # 음성 명령어: 음소거 해제
                if "니노" in text and any(kw in text for kw in ["다시", "말해", "들어"]):
                    if state.get('muted'):
                        state['muted'] = False
                        await text_channel.send("응 다시 듣고 있어!")
                        pending_utterances.clear()
                        continue

                if state.get('muted'):
                    continue

                pending_utterances.append((user.display_name, text, time_module.time()))
                last_speech_time = time_module.time()

            # 대화가 쌓여있고, 충분한 침묵이 지났으면 응답
            now = time_module.time()
            # "니노" 호출 여부에 따라 대기 시간 다르게
            all_text_check = " ".join(t for _, t, _ in pending_utterances) if pending_utterances else ""
            wait_time = VOICE_SILENCE_NINO_CALLED if "니노" in all_text_check else VOICE_SILENCE_BEFORE_RESPOND
            if pending_utterances and (now - last_speech_time) >= wait_time:
                channel_id = text_channel.id

                # 모든 발화를 대화 기록에 추가
                for speaker, text, _ in pending_utterances:
                    add_to_history(channel_id, speaker, text)

                # 니노를 불렀는지 / 대화에 참여할만한지 판단
                all_text = " ".join(t for _, t, _ in pending_utterances)
                nino_called = "니노" in all_text

                if nino_called:
                    # 직접 호출: 바로 응답
                    t0 = time_module.time()
                    reply = await asyncio.to_thread(ask_claude, channel_id, voice_mode=True)
                    t1 = time_module.time()
                    print(f"[TIMING] Claude: {t1-t0:.1f}s", flush=True)
                    await text_channel.send(reply)
                    if vc.is_connected() and not vc.is_playing():
                        t2 = time_module.time()
                        await tts_speak(vc, reply)
                        t3 = time_module.time()
                        print(f"[TIMING] TTS: {t3-t2:.1f}s", flush=True)
                else:
                    # 직접 호출 안 됨: 대화 기록만 저장, 가끔 끼어들기
                    # 마지막 끼어든 시간 체크 (너무 자주 안 끼어들도록)
                    last_chimed = state.get('last_chime_time', 0)
                    if (now - last_chimed) > 30:  # 최소 30초 간격
                        # 시스템 메시지로 끼어들기 지시
                        add_to_history(channel_id, "시스템",
                            "(친구들이 대화 중이야. 니노를 직접 부르진 않았지만 대화에 자연스럽게 한마디 끼어들어봐. "
                            "끼어들 내용이 없으면 '...'만 답해)")
                        reply = await asyncio.to_thread(ask_claude, channel_id, voice_mode=True)
                        if reply and reply.strip() != '...':
                            await text_channel.send(reply)
                            if vc.is_connected() and not vc.is_playing():
                                await tts_speak(vc, reply)
                        state['last_chime_time'] = now

                pending_utterances.clear()
                # 응답 중 쌓인 버퍼 비우기
                audio_buffer.get_ready()

            await asyncio.sleep(0.3)
        except Exception as e:
            print(f"[VOICE] Loop error: {e}", flush=True)
            await asyncio.sleep(1)


async def join_voice(message):
    if not message.author.voice or not message.author.voice.channel:
        await message.channel.send("음성 채널에 먼저 들어가 있어야 해!")
        return

    voice_channel = message.author.voice.channel
    guild_id = message.guild.id

    if guild_id in voice_states and voice_states[guild_id].get('vc'):
        vc = voice_states[guild_id]['vc']
        if vc.is_connected():
            if vc.channel.id == voice_channel.id:
                await message.channel.send("이미 들어와 있어!")
                return
            await vc.move_to(voice_channel)
            voice_states[guild_id]['text_channel'] = message.channel
            await message.channel.send(f"{voice_channel.name}으로 이동했어!")
            return

    try:
        vc = await voice_channel.connect(cls=voice_recv.VoiceRecvClient)
        print(f"[VOICE] Connected with VoiceRecvClient, is_connected={vc.is_connected()}", flush=True)

        audio_buffer = VoiceAudioBuffer()

        def on_voice_data(user, data: voice_recv.VoiceData):
            if data.pcm:
                audio_buffer.feed(user, data.pcm)

        vc.listen(voice_recv.BasicSink(on_voice_data))
        print(f"[VOICE] Listening started", flush=True)

        voice_states[guild_id] = {
            'vc': vc,
            'text_channel': message.channel,
            'listening': True,
            'audio_buffer': audio_buffer,
        }
        task = asyncio.create_task(voice_listen_loop(guild_id))
        voice_states[guild_id]['task'] = task

    except Exception as e:
        await message.channel.send("음성 채널에 들어가지 못했어 ㅠ")
        print(f"[VOICE] Join error: {e}", flush=True)
        import traceback
        traceback.print_exc()


async def leave_voice(message):
    guild_id = message.guild.id
    state = voice_states.get(guild_id)

    if not state or not state.get('vc'):
        # voice_states에 없지만 실제 음성 연결이 남아있을 수 있음
        for vc in client.voice_clients:
            if vc.guild.id == guild_id:
                await vc.disconnect(force=True)
                await message.channel.send("나갔어! 또 불러~")
                return
        # 유령 연결: 봇이 음성채널에 표시되지만 voice_clients에 없는 경우
        # 해당 채널에 잠깐 연결했다가 바로 끊어서 정리
        guild = message.guild
        if guild.me and guild.me.voice and guild.me.voice.channel:
            try:
                vc = await guild.me.voice.channel.connect(cls=voice_recv.VoiceRecvClient)
                await vc.disconnect(force=True)
                await message.channel.send("나갔어! 또 불러~")
                return
            except Exception:
                pass
        await message.channel.send("나 음성 채널에 없는데?")
        return

    state['listening'] = False

    vc = state['vc']
    if vc.is_connected():
        try:
            vc.stop_listening()
        except Exception:
            pass
        if vc.is_playing():
            vc.stop()
        await vc.disconnect()

    if state.get('task'):
        state['task'].cancel()
    if state.get('audio_buffer'):
        state['audio_buffer'].clear()

    del voice_states[guild_id]
    await message.channel.send("나갔어! 또 불러~")


# ===================== 디스코드 클라이언트 설정 =====================
intents = discord.Intents.default()
intents.message_content = True
intents.voice_states = True

try:
    asyncio.get_event_loop()
except RuntimeError:
    asyncio.set_event_loop(asyncio.new_event_loop())

client = discord.Client(intents=intents)

last_message_id = {}
responding_lock = set()


# ===================== 대화 기록 관리 =====================
def add_to_history(channel_id, speaker_name, text):
    """대화 기록에 추가 (중복 방지, 일관된 포맷)"""
    if channel_id not in conversation_history:
        conversation_history[channel_id] = []

    entry = f"{speaker_name}: {text}"
    # 마지막 항목과 동일하면 스킵
    if conversation_history[channel_id] and conversation_history[channel_id][-1] == entry:
        return

    conversation_history[channel_id].append(entry)
    if len(conversation_history[channel_id]) > MAX_HISTORY:
        conversation_history[channel_id] = conversation_history[channel_id][-MAX_HISTORY:]

    # 오래된 채널 정리 (메모리 누수 방지)
    if len(conversation_history) > MAX_CHANNELS:
        oldest = list(conversation_history.keys())[0]
        del conversation_history[oldest]


def choose_model(text, voice_mode=False):
    """발화 복잡도에 따라 모델 선택"""
    if not voice_mode:
        return "claude-opus-4-6"  # 텍스트는 항상 Opus

    # 복잡한 질문 키워드 → Opus
    complex_keywords = [
        "설명", "알려줘", "왜", "어떻게", "분석", "비교", "차이",
        "코드", "프로그램", "번역", "요약", "정리", "추천", "리뷰",
        "계획", "방법", "원리", "이유", "역사", "의미",
    ]
    if any(kw in text for kw in complex_keywords):
        return "claude-opus-4-6"

    # 중간 길이 → Sonnet
    if len(text) > 30:
        return "claude-sonnet-4-6"

    # 짧은 발화 (인사, 간단한 대답) → Haiku
    return "claude-haiku-4-5-20251001"


def ask_claude(channel_id: int, voice_mode: bool = False) -> str:
    """Claude에게 응답 요청. 대화 기록은 미리 add_to_history로 추가해둘 것."""
    if channel_id not in conversation_history:
        conversation_history[channel_id] = []

    history_text = "\n".join(conversation_history[channel_id])
    prompt_template = VOICE_SYSTEM_PROMPT if voice_mode else SYSTEM_PROMPT
    memory_context = get_memory_context()
    prompt = f"{prompt_template}{memory_context}\n\n대화 기록:\n{history_text}\n\n니노의 답변:"

    # 마지막 사용자 발화 기반으로 모델 선택
    last_user_text = ""
    for entry in reversed(conversation_history.get(channel_id, [])):
        if not entry.startswith("니노:") and not entry.startswith("시스템:"):
            last_user_text = entry.split(": ", 1)[-1] if ": " in entry else entry
            break
    model = choose_model(last_user_text, voice_mode)

    try:
        env = os.environ.copy()
        env.pop("CLAUDECODE", None)
        startupinfo = None
        if sys.platform == "win32":
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startupinfo.wShowWindow = 0
        cmd = ["claude", "-p", "--dangerously-skip-permissions"]
        if model != "claude-opus-4-6":
            cmd.extend(["--model", model])
        cmd.append(prompt)
        print(f"[MODEL] {model} (input: {last_user_text[:30]})", flush=True)
        result = subprocess.run(
            cmd,
            capture_output=True, text=True, timeout=120,
            encoding="utf-8", env=env,
            startupinfo=startupinfo,
            creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
        )
        reply = result.stdout.strip()
        if not reply:
            reply = "어... 뭔가 잘못됐어 ㅠㅠ"

        # 니노 응답도 기록
        add_to_history(channel_id, "니노", reply)
        return reply
    except subprocess.TimeoutExpired:
        return "아 미안 생각 너무 오래 했다 ㅋㅋ 다시 말해봐"
    except Exception as e:
        return f"오류 발생: {e}"


@client.event
async def on_ready():
    print(f"bot ready: {client.user} (ID: {client.user.id})", flush=True)
    # 재시작 시 기존 유령 음성 연결 정리
    for vc in client.voice_clients:
        try:
            await vc.disconnect(force=True)
            print(f"[VOICE] Cleaned up ghost vc in {vc.channel}", flush=True)
        except Exception:
            pass
    # guild.me.voice가 남아있는 유령 연결도 정리
    for guild in client.guilds:
        if guild.me and guild.me.voice and guild.me.voice.channel:
            try:
                vc = await guild.me.voice.channel.connect(cls=voice_recv.VoiceRecvClient)
                await vc.disconnect(force=True)
                print(f"[VOICE] Cleaned up ghost connection in {guild.name}", flush=True)
            except Exception as e:
                print(f"[VOICE] Ghost cleanup failed: {e}", flush=True)


async def send_reply(channel, reply):
    if len(reply) > 2000:
        for i in range(0, len(reply), 2000):
            await channel.send(reply[i:i+2000])
    else:
        await channel.send(reply)


async def delayed_reply(channel, msg_id):
    """일정 시간 후 아무도 안 답했으면 자연스럽게 끼어들기"""
    await asyncio.sleep(SILENT_WAIT_SEC)
    if last_message_id.get(channel.id) != msg_id:
        return
    if channel.id in responding_lock:
        return
    responding_lock.add(channel.id)
    try:
        # 끼어들기 맥락 추가
        add_to_history(channel.id, "시스템", "(아무도 대답을 안 해서 니노가 자연스럽게 대화에 끼어든다)")
        async with channel.typing():
            reply = await asyncio.to_thread(ask_claude, channel.id)
        await send_reply(channel, reply)
    finally:
        responding_lock.discard(channel.id)


@client.event
async def on_voice_state_update(member, before, after):
    if member == client.user:
        return
    for guild_id, state in list(voice_states.items()):
        vc = state.get('vc')
        if not vc or not vc.is_connected():
            continue
        if len(vc.channel.members) <= 1:
            state['listening'] = False
            try:
                vc.stop_listening()
            except Exception:
                pass
            if vc.is_playing():
                vc.stop()
            await vc.disconnect()
            if state.get('task'):
                state['task'].cancel()
            del voice_states[guild_id]
            try:
                await state['text_channel'].send("다 나갔네... 나도 나갈게!")
            except Exception:
                pass


@client.event
async def on_message(message):
    if message.author == client.user:
        return
    if message.author.bot:
        if not isinstance(message.channel, discord.DMChannel):
            last_message_id[message.channel.id] = message.id
            # 봇 메시지도 대화 기록에 추가 (니노가 다른 봇 메시지도 볼 수 있게)
            bot_text = message.content or ""
            if bot_text.strip():
                add_to_history(message.channel.id, message.author.display_name, bot_text)
                # 다른 봇이 니노를 불렀으면 응답
                bot_mention = f"<@{client.user.id}>"
                if "니노" in bot_text or bot_mention in message.content:
                    channel_id = message.channel.id
                    if channel_id not in responding_lock:
                        responding_lock.add(channel_id)
                        try:
                            async with message.channel.typing():
                                reply = await asyncio.to_thread(ask_claude, channel_id)
                            await send_reply(message.channel, reply)
                        finally:
                            responding_lock.discard(channel_id)
        return

    channel_id = message.channel.id
    bot_mention = f"<@{client.user.id}>"
    role_mention = f"<@&{BOT_ROLE_ID}>"
    is_mentioned = (
        bot_mention in message.content
        or role_mention in message.content
        or client.user in message.mentions
    )
    is_dm = isinstance(message.channel, discord.DMChannel)
    name_called = "니노" in message.content

    user_text = message.content
    user_text = user_text.replace(bot_mention, "")
    user_text = user_text.replace(f"<@!{client.user.id}>", "")
    user_text = user_text.replace(role_mention, "")
    user_text = user_text.strip()

    if not user_text:
        return

    # ===== 음성 명령 처리 =====
    if name_called and message.guild:
        if any(kw in user_text for kw in VOICE_JOIN_KEYWORDS):
            await join_voice(message)
            return
        if any(kw in user_text for kw in VOICE_LEAVE_KEYWORDS):
            await leave_voice(message)
            return

    # 대화 기록 추가 (한 번만, 일관된 포맷)
    add_to_history(channel_id, message.author.display_name, user_text)

    # 1) 멘션, DM, "니노" 호출 → 즉시 반응
    if is_mentioned or is_dm or name_called:
        if channel_id in responding_lock:
            return
        responding_lock.add(channel_id)
        try:
            # 날씨 질문이면 날씨 데이터를 시스템 메시지로 추가 (사용자 기록에 섞지 않음)
            if is_weather_question(user_text):
                weather_data = fetch_weather(user_text)
                add_to_history(channel_id, "시스템",
                    f"(날씨 데이터 - 참고해서 자연스럽게 알려줘)\n{weather_data}")

            async with message.channel.typing():
                reply = await asyncio.to_thread(ask_claude, channel_id)
            await send_reply(message.channel, reply)

            # 음성 채널에 있으면 같이 말하기
            if message.guild and message.guild.id in voice_states:
                state = voice_states[message.guild.id]
                vc = state.get('vc')
                if vc and vc.is_connected() and not vc.is_playing():
                    asyncio.create_task(tts_speak(vc, reply))
        finally:
            responding_lock.discard(channel_id)
        return

    # 2) 일반 메시지 → 일정 시간 뒤 끼어들기
    last_message_id[channel_id] = message.id
    asyncio.create_task(delayed_reply(message.channel, message.id))


async def cleanup_voice():
    """봇 종료 시 모든 음성 연결 정리"""
    for guild_id, state in list(voice_states.items()):
        vc = state.get('vc')
        if vc and vc.is_connected():
            try:
                vc.stop_listening()
            except Exception:
                pass
            try:
                await vc.disconnect()
            except Exception:
                pass
    voice_states.clear()

@client.event
async def on_disconnect():
    await cleanup_voice()

import signal
def _handle_signal(sig, frame):
    async def _cleanup_and_exit():
        await cleanup_voice()
        await client.close()
    try:
        client.loop.create_task(_cleanup_and_exit())
    except Exception:
        pass

signal.signal(signal.SIGTERM, _handle_signal)
signal.signal(signal.SIGINT, _handle_signal)

client.run(DISCORD_TOKEN)
