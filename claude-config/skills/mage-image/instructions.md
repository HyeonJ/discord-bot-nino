# Mage 이미지 생성 스킬

Mage (mage.space)에서 AI 이미지를 생성하고 다운로드하는 스킬.

## 사전 조건
- Edge 브라우저 CDP 연결 (포트 9222)
- mage.space 로그인 상태
- agent-browser CLI 사용 가능: `source ~/.nvm/nvm.sh`

## 플로우

### 1. Mage 페이지 열기
```bash
source ~/.nvm/nvm.sh
agent-browser --cdp 9222 open https://www.mage.space
agent-browser --cdp 9222 wait --load networkidle
```

### 2. 로그인 확인
스냅샷으로 로그인 상태 확인:
```bash
agent-browser --cdp 9222 snapshot -i
```
로그인 안 돼있으면 사용자에게 안내.

### 3. 프롬프트 입력
Mage는 contenteditable div를 사용하므로 일반 fill이 안 됨. eval로 직접 입력:
```bash
agent-browser --cdp 9222 eval --stdin <<'EOF'
(() => {
  const el = document.querySelector('[contenteditable="true"]');
  if (!el) return 'NO_INPUT';
  el.focus();
  el.innerHTML = "";
  document.execCommand("selectAll");
  document.execCommand("insertText", false, "프롬프트 내용");
  return 'OK';
})()
EOF
```

### 4. 전송
```bash
agent-browser --cdp 9222 press Enter
```

### 5. 생성 대기
Mage 무료 플랜은 생성에 시간이 걸림 (30초~수분). 주기적으로 이미지 확인:
```bash
sleep 30
agent-browser --cdp 9222 eval '(() => { const imgs = document.querySelectorAll("img[src*=\\"temp/30d/creations\\"]"); return imgs.length; })()'
```
이미지가 나타날 때까지 반복 (최대 3분).

### 6. 이미지 추출
```bash
# 이미지 URL 가져오기
IMG_URL=$(agent-browser --cdp 9222 eval '(() => { const imgs = document.querySelectorAll("img[src*=\"temp/30d/creations\"]"); return imgs.length ? imgs[imgs.length-1].src : "NONE"; })()')

# 다운로드
curl -o /tmp/mage-output.png "$IMG_URL"
```

### 7. 디스코드 전송
```bash
discord-send -f /tmp/mage-output.png -c 채널ID "이미지 생성 완료!"
```

## 참조 이미지 업로드 (선택)
```bash
# Reference 영역 클릭 후 파일 업로드
agent-browser --cdp 9222 snapshot -i  # 업로드 영역 ref 확인
agent-browser --cdp 9222 click @REF   # Reference > New 클릭
agent-browser --cdp 9222 upload 'input[type=file]' '/path/to/image.png'
```

## 프롬프트 작성 원칙
1. 영어로 쓰기 (DALL-E/Mage 공통)
2. 구체적 스펙 먼저 (크기, 스타일)
3. 네거티브 프롬프트 포함 ("no shadows, no text")
4. 한 문장에 하나의 요구
5. 짧을수록 좋음

## 제한사항
- 무료 플랜: 300 Gems/일 (매일 리셋)
- 이미지당 약 45~60 Gems
- 하루에 5~6장 정도 가능
- 생성 속도 느림 (무료 플랜)
