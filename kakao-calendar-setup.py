#!/usr/bin/env python3
"""
카카오 캘린더 OAuth 설정 스크립트
- 브라우저에서 카카오 로그인 후 동의 한 번으로 토큰 저장
- 이후 자동 갱신
"""

import os
import json
import sys
import time
import urllib.parse
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

TOKEN_FILE = Path.home() / '.kakao-calendar-token.json'
CONFIG_FILE = Path.home() / '.kakao-calendar-config.json'

# ── 토큰 저장/로드 ───────────────────────────────────────────────

def save_token(token_data):
    TOKEN_FILE.write_text(json.dumps(token_data, indent=2))
    TOKEN_FILE.chmod(0o600)

def load_token():
    if TOKEN_FILE.exists():
        return json.loads(TOKEN_FILE.read_text())
    return None

def load_config():
    if CONFIG_FILE.exists():
        return json.loads(CONFIG_FILE.read_text())
    return None

# ── 토큰 갱신 ────────────────────────────────────────────────────

def refresh_access_token(config, refresh_token):
    data = urllib.parse.urlencode({
        'grant_type': 'refresh_token',
        'client_id': config['rest_api_key'],
        'client_secret': config.get('client_secret', ''),
        'refresh_token': refresh_token,
    }).encode()
    req = urllib.request.Request('https://kauth.kakao.com/oauth/token', data=data)
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())
    return result

def get_valid_token():
    config = load_config()
    if not config:
        print("❌ 카카오 앱 설정 없음. kakao-calendar-setup.py --setup 실행하세요.")
        return None, None
    token = load_token()
    if not token:
        print("❌ 저장된 토큰 없음. kakao-calendar-setup.py --auth 실행하세요.")
        return None, None
    # 만료 임박 (10분 이내) 시 갱신
    if time.time() > token.get('expires_at', 0) - 600:
        result = refresh_access_token(config, token['refresh_token'])
        token['access_token'] = result['access_token']
        token['expires_at'] = time.time() + result.get('expires_in', 21599)
        if 'refresh_token' in result:
            token['refresh_token'] = result['refresh_token']
        save_token(token)
    return token['access_token'], config

# ── 일정 등록 ────────────────────────────────────────────────────

def create_event(title, start_kst, end_kst, location=None, description=None, calendar_id='primary'):
    """
    title: 일정 제목
    start_kst: 'YYYY-MM-DDTHH:MM:SS' (KST)
    end_kst: 'YYYY-MM-DDTHH:MM:SS' (KST)
    """
    access_token, _ = get_valid_token()
    if not access_token:
        return None

    # KST → UTC 변환 (KST = UTC+9)
    def kst_to_utc(kst_str):
        from datetime import datetime, timedelta
        dt = datetime.fromisoformat(kst_str)
        utc = dt - timedelta(hours=9)
        return utc.strftime('%Y-%m-%dT%H:%M:%SZ')

    event = {
        'title': title,
        'time': {
            'start_at': kst_to_utc(start_kst),
            'end_at': kst_to_utc(end_kst),
            'time_zone': 'Asia/Seoul',
            'all_day': False,
        }
    }
    if location:
        event['location'] = {'name': location}
    if description:
        event['description'] = description

    data = urllib.parse.urlencode({
        'calendar_id': calendar_id,
        'event': json.dumps(event),
    }).encode()
    req = urllib.request.Request(
        'https://kapi.kakao.com/v2/api/calendar/create/event',
        data=data,
        headers={'Authorization': f'Bearer {access_token}'}
    )
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())
    return result.get('event_id')

# ── OAuth 플로우 ──────────────────────────────────────────────────

class OAuthHandler(BaseHTTPRequestHandler):
    auth_code = None

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        if 'code' in params:
            OAuthHandler.auth_code = params['code'][0]
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'<h1>OK! \xec\xb0\xbd\xec\x9d\x84 \xeb\x8b\xab\xec\x95\x84\xeb\x8f\x84 \xeb\x8f\xbc\xec\x9a\x94.</h1>')
        else:
            self.send_response(400)
            self.end_headers()

    def log_message(self, *args):
        pass

def run_oauth(config):
    redirect_uri = 'http://localhost:5000/callback'
    url = (
        f"https://kauth.kakao.com/oauth/authorize"
        f"?client_id={config['rest_api_key']}"
        f"&redirect_uri={urllib.parse.quote(redirect_uri)}"
        f"&response_type=code"
        f"&scope=talk_calendar"
    )
    print(f"\n브라우저에서 아래 URL을 열고 카카오 로그인 + 동의 눌러주세요:\n\n{url}\n")

    server = HTTPServer(('localhost', 5000), OAuthHandler)
    server.timeout = 120
    while OAuthHandler.auth_code is None:
        server.handle_request()

    code = OAuthHandler.auth_code
    data = urllib.parse.urlencode({
        'grant_type': 'authorization_code',
        'client_id': config['rest_api_key'],
        'client_secret': config.get('client_secret', ''),
        'redirect_uri': redirect_uri,
        'code': code,
    }).encode()
    req = urllib.request.Request('https://kauth.kakao.com/oauth/token', data=data)
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())

    token_data = {
        'access_token': result['access_token'],
        'refresh_token': result['refresh_token'],
        'expires_at': time.time() + result.get('expires_in', 21599),
    }
    save_token(token_data)
    print("✅ 토큰 저장 완료!")
    return token_data

# ── CLI ──────────────────────────────────────────────────────────

if __name__ == '__main__':
    if '--setup' in sys.argv:
        print("카카오 앱 정보 입력 (developers.kakao.com에서 확인)")
        rest_api_key = input("REST API 키: ").strip()
        client_secret = input("Client Secret (없으면 Enter): ").strip()
        config = {'rest_api_key': rest_api_key, 'client_secret': client_secret}
        CONFIG_FILE.write_text(json.dumps(config, indent=2))
        CONFIG_FILE.chmod(0o600)
        print(f"✅ 설정 저장: {CONFIG_FILE}")

    elif '--auth' in sys.argv:
        config = load_config()
        if not config:
            print("먼저 --setup 실행하세요.")
            sys.exit(1)
        run_oauth(config)

    elif '--test' in sys.argv:
        event_id = create_event(
            title='니노 테스트 일정',
            start_kst='2026-03-11T12:00:00',
            end_kst='2026-03-11T13:00:00',
            description='카카오 캘린더 연동 테스트'
        )
        if event_id:
            print(f"✅ 일정 등록 완료: {event_id}")
        else:
            print("❌ 등록 실패")

    else:
        print("사용법: kakao-calendar-setup.py [--setup|--auth|--test]")
