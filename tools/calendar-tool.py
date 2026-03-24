#!/home/bpx27/discord-bot-nino/.venv/bin/python
"""
calendar-tool: 카카오 캘린더 + Apple iCloud 캘린더 CLI
사용법: calendar-tool.py <kakao|apple|both> <add|list> [options]
"""

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

# ── 설정 파일 경로 ──────────────────────────────────────────────

KAKAO_CONFIG = Path.home() / '.kakao-calendar-config.json'
KAKAO_TOKEN = Path.home() / '.kakao-calendar-token.json'
APPLE_CONFIG = Path.home() / '.apple-calendar-config.json'

# ── 카카오 캘린더 ──────────────────────────────────────────────

def kakao_get_token():
    if not KAKAO_CONFIG.exists():
        print("❌ 카카오 설정 없음. kakao-calendar-setup.py --setup 실행", file=sys.stderr)
        return None
    if not KAKAO_TOKEN.exists():
        print("❌ 카카오 토큰 없음. kakao-calendar-setup.py --auth 실행", file=sys.stderr)
        return None

    config = json.loads(KAKAO_CONFIG.read_text())
    token = json.loads(KAKAO_TOKEN.read_text())

    # 토큰 만료 임박 시 갱신
    if time.time() > token.get('expires_at', 0) - 600:
        data = urllib.parse.urlencode({
            'grant_type': 'refresh_token',
            'client_id': config['rest_api_key'],
            'client_secret': config.get('client_secret', ''),
            'refresh_token': token['refresh_token'],
        }).encode()
        req = urllib.request.Request('https://kauth.kakao.com/oauth/token', data=data)
        try:
            with urllib.request.urlopen(req) as resp:
                result = json.loads(resp.read())
            token['access_token'] = result['access_token']
            token['expires_at'] = time.time() + result.get('expires_in', 21599)
            if 'refresh_token' in result:
                token['refresh_token'] = result['refresh_token']
            KAKAO_TOKEN.write_text(json.dumps(token, indent=2))
            KAKAO_TOKEN.chmod(0o600)
        except Exception as e:
            print(f"❌ 토큰 갱신 실패: {e}", file=sys.stderr)
            return None

    return token['access_token']


def kakao_add(title, start, end, location=None, description=None):
    access_token = kakao_get_token()
    if not access_token:
        return False

    def kst_to_utc(dt):
        utc = dt - timedelta(hours=9)
        return utc.strftime('%Y-%m-%dT%H:%M:%SZ')

    event = {
        'title': title,
        'time': {
            'start_at': kst_to_utc(start),
            'end_at': kst_to_utc(end),
            'time_zone': 'Asia/Seoul',
            'all_day': False,
        }
    }
    if location:
        event['location'] = {'name': location}
    if description:
        event['description'] = description

    data = urllib.parse.urlencode({
        'calendar_id': 'primary',
        'event': json.dumps(event),
    }).encode()
    req = urllib.request.Request(
        'https://kapi.kakao.com/v2/api/calendar/create/event',
        data=data,
        headers={'Authorization': f'Bearer {access_token}'}
    )
    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read())
        event_id = result.get('event_id')
        print(f"✅ 카카오 캘린더 등록 완료 (event_id: {event_id})")
        return True
    except Exception as e:
        print(f"❌ 카카오 캘린더 등록 실패: {e}", file=sys.stderr)
        return False


def kakao_list(from_date, to_date):
    access_token = kakao_get_token()
    if not access_token:
        return

    def kst_to_utc(dt):
        utc = dt - timedelta(hours=9)
        return utc.strftime('%Y-%m-%dT%H:%M:%SZ')

    params = urllib.parse.urlencode({
        'from': kst_to_utc(from_date),
        'to': kst_to_utc(to_date),
    })
    req = urllib.request.Request(
        f'https://kapi.kakao.com/v2/api/calendar/events?{params}',
        headers={'Authorization': f'Bearer {access_token}'}
    )
    try:
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read())
        events = result.get('events', [])
        if not events:
            print("일정 없음")
            return
        for ev in events:
            t = ev.get('time', {})
            print(f"• {ev.get('title', '?')} | {t.get('start_at', '?')} ~ {t.get('end_at', '?')}")
    except Exception as e:
        print(f"❌ 조회 실패: {e}", file=sys.stderr)


# ── Apple iCloud 캘린더 ────────────────────────────────────────

def apple_get_client():
    if not APPLE_CONFIG.exists():
        print("❌ Apple 캘린더 설정 없음. ~/.apple-calendar-config.json 필요", file=sys.stderr)
        print('  {"apple_id": "your@icloud.com", "app_password": "xxxx-xxxx-xxxx-xxxx"}', file=sys.stderr)
        return None, None

    try:
        import caldav
    except ImportError:
        print("❌ caldav 패키지 없음. `uv pip install caldav` 실행", file=sys.stderr)
        return None, None

    config = json.loads(APPLE_CONFIG.read_text())
    client = caldav.DAVClient(
        url="https://caldav.icloud.com",
        username=config['apple_id'],
        password=config['app_password'],
    )
    return client, config


def apple_add(title, start, end, location=None, description=None, calendar_name=None):
    client, config = apple_get_client()
    if not client:
        return False

    try:
        principal = client.principal()
        calendars = principal.calendars()

        # 캘린더 이름 조회 (deprecated name 대신 get_display_name 사용)
        def cal_name(c):
            try:
                return c.get_display_name()
            except Exception:
                return str(c.name) if hasattr(c, 'name') else '?'

        if calendar_name:
            cal = next((c for c in calendars if cal_name(c) == calendar_name), None)
            if not cal:
                names = [cal_name(c) for c in calendars]
                print(f"❌ '{calendar_name}' 캘린더 없음. 사용 가능: {names}", file=sys.stderr)
                return False
        else:
            # 기본값: Home 캘린더 (Reminders 제외)
            cal = next((c for c in calendars if cal_name(c) == 'Home'), None)
            if not cal:
                cal = next((c for c in calendars if cal_name(c) not in ('Reminders ⚠️', 'Reminders')), calendars[0])

        vcal = f"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//nino//calendar-tool//KO
BEGIN:VEVENT
DTSTART;TZID=Asia/Seoul:{start.strftime('%Y%m%dT%H%M%S')}
DTEND;TZID=Asia/Seoul:{end.strftime('%Y%m%dT%H%M%S')}
SUMMARY:{title}
{f'LOCATION:{location}' if location else ''}
{f'DESCRIPTION:{description}' if description else ''}
END:VEVENT
END:VCALENDAR"""

        cal.save_event(vcal)
        print(f"✅ Apple 캘린더 등록 완료 (캘린더: {cal_name(cal)})")
        return True
    except Exception as e:
        print(f"❌ Apple 캘린더 등록 실패: {e}", file=sys.stderr)
        return False


def apple_list(from_date, to_date, calendar_name=None):
    client, config = apple_get_client()
    if not client:
        return

    try:
        principal = client.principal()
        calendars = principal.calendars()

        target_cals = calendars
        if calendar_name:
            target_cals = [c for c in calendars if c.name == calendar_name]

        for cal in target_cals:
            events = cal.date_search(start=from_date, end=to_date, expand=True)
            for ev in events:
                vevent = ev.vobject_instance.vevent
                summary = str(vevent.summary.value) if hasattr(vevent, 'summary') else '?'
                dtstart = vevent.dtstart.value if hasattr(vevent, 'dtstart') else '?'
                print(f"• [{cal.name}] {summary} | {dtstart}")
    except Exception as e:
        print(f"❌ 조회 실패: {e}", file=sys.stderr)


# ── CLI ────────────────────────────────────────────────────────

def parse_datetime(s):
    """'2026-03-25 14:00' 또는 '2026-03-25T14:00' 파싱"""
    for fmt in ('%Y-%m-%d %H:%M', '%Y-%m-%dT%H:%M', '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d %H:%M:%S'):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    # 날짜만 (종일)
    try:
        return datetime.strptime(s, '%Y-%m-%d')
    except ValueError:
        print(f"❌ 날짜 형식 오류: {s} (예: 2026-03-25 14:00)", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description='캘린더 일정 관리')
    parser.add_argument('service', choices=['kakao', 'apple', 'both'])
    parser.add_argument('action', choices=['add', 'list'])
    parser.add_argument('--title', '-t', help='일정 제목')
    parser.add_argument('--start', '-s', help='시작 (2026-03-25 14:00)')
    parser.add_argument('--end', '-e', help='종료 (2026-03-25 15:00)')
    parser.add_argument('--location', '-l', help='장소')
    parser.add_argument('--description', '-d', help='설명')
    parser.add_argument('--calendar', '-c', help='Apple 캘린더 이름')
    parser.add_argument('--from', dest='from_date', help='조회 시작일')
    parser.add_argument('--to', dest='to_date', help='조회 종료일')

    args = parser.parse_args()

    if args.action == 'add':
        if not args.title or not args.start:
            parser.error('--title과 --start 필수')
        start = parse_datetime(args.start)
        end = parse_datetime(args.end) if args.end else start + timedelta(hours=1)

        if args.service in ('kakao', 'both'):
            kakao_add(args.title, start, end, args.location, args.description)
        if args.service in ('apple', 'both'):
            apple_add(args.title, start, end, args.location, args.description, args.calendar)

    elif args.action == 'list':
        if not args.from_date:
            parser.error('--from 필수')
        from_dt = parse_datetime(args.from_date)
        to_dt = parse_datetime(args.to_date) if args.to_date else from_dt + timedelta(days=1)

        if args.service in ('kakao', 'both'):
            print("── 카카오 캘린더 ──")
            kakao_list(from_dt, to_dt)
        if args.service in ('apple', 'both'):
            print("── Apple 캘린더 ──")
            apple_list(from_dt, to_dt, args.calendar)


if __name__ == '__main__':
    main()
