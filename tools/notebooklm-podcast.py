#!/usr/bin/env python3
"""
NotebookLM 영어강의 팟캐스트 생성 스크립트
사용법:
  uv run --with notebooklm-py notebooklm-podcast.py create \
    --title "영어강의 3강" \
    --source "소스 텍스트나 URL" \
    --instructions "이전 강의에서 아쉬웠던 점: ..."

  uv run --with notebooklm-py notebooklm-podcast.py list
"""
import asyncio
import argparse
import sys
from pathlib import Path

from notebooklm import NotebookLMClient, AudioFormat
from notebooklm.auth import AuthTokens


async def list_notebooks():
    auth = await AuthTokens.from_storage()
    async with NotebookLMClient(auth) as client:
        notebooks = await client.notebooks.list()
        for nb in notebooks:
            print(f"{nb.id}: {nb.title}")


async def create_podcast(title: str, sources: list[str], instructions: str | None,
                         lang: str, fmt: str, output_dir: str):
    auth = await AuthTokens.from_storage()
    async with NotebookLMClient(auth) as client:
        # 1. 새 노트북 생성
        print(f"[1/4] 노트북 생성: {title}")
        notebook = await client.notebooks.create(title)
        print(f"  → 노트북 ID: {notebook.id}")

        # 2. 소스 추가
        source_ids = []
        for i, src in enumerate(sources):
            print(f"[2/4] 소스 추가 ({i+1}/{len(sources)}): {src[:60]}...")
            if src.startswith("http://") or src.startswith("https://"):
                added = await client.sources.add_url(notebook.id, src)
            else:
                added = await client.sources.add_text(notebook.id, src, title=f"소스 {i+1}")
            source_ids.append(added.id)
            print(f"  → 소스 ID: {added.id}, 인덱싱 대기 중...")
            await client.sources.wait(notebook.id, added.id)
            print(f"  → 인덱싱 완료")

        # 3. 팟캐스트 생성
        audio_format = AudioFormat[fmt.upper()] if fmt else AudioFormat.DEEP_DIVE
        print(f"[3/4] 팟캐스트 생성 (형식: {audio_format.name}, 언어: {lang})")
        status = await client.artifacts.generate_audio(
            notebook.id,
            source_ids=source_ids if source_ids else None,
            language=lang,
            instructions=instructions,
            audio_format=audio_format,
        )
        print(f"  → 작업 ID: {status.task_id}, 완료 대기 중...")
        artifact = await client.artifacts.wait(notebook.id, status.task_id)
        print(f"  → 팟캐스트 생성 완료!")

        # 4. 다운로드
        output_path = Path(output_dir) / f"{title}.mp3"
        output_path.parent.mkdir(parents=True, exist_ok=True)
        print(f"[4/4] 다운로드: {output_path}")
        audio_data = await client.artifacts.download_audio(notebook.id, artifact.id)
        output_path.write_bytes(audio_data)
        print(f"  → 저장 완료: {output_path}")
        print(f"\n노트북 URL: https://notebooklm.google.com/notebook/{notebook.id}")
        return str(output_path)


def main():
    parser = argparse.ArgumentParser(description="NotebookLM 팟캐스트 생성")
    subparsers = parser.add_subparsers(dest="cmd")

    # list 명령
    subparsers.add_parser("list", help="노트북 목록")

    # create 명령
    create_p = subparsers.add_parser("create", help="새 팟캐스트 생성")
    create_p.add_argument("--title", required=True, help="강의 제목 (예: 영어강의 3강)")
    create_p.add_argument("--source", action="append", dest="sources", default=[],
                          help="소스 (텍스트 또는 URL, 여러 번 사용 가능)")
    create_p.add_argument("--instructions", help="팟캐스트 생성 지침")
    create_p.add_argument("--lang", default="ko", help="언어 (기본: ko)")
    create_p.add_argument("--format", default="DEEP_DIVE",
                          choices=["DEEP_DIVE", "BRIEF", "CRITIQUE", "DEBATE"],
                          help="팟캐스트 형식")
    create_p.add_argument("--output-dir", default="/tmp/notebooklm-podcasts",
                          help="저장 경로")

    args = parser.parse_args()

    if args.cmd == "list":
        asyncio.run(list_notebooks())
    elif args.cmd == "create":
        if not args.sources:
            print("오류: --source 가 최소 하나 필요해")
            sys.exit(1)
        result = asyncio.run(create_podcast(
            title=args.title,
            sources=args.sources,
            instructions=args.instructions,
            lang=args.lang,
            fmt=args.format,
            output_dir=args.output_dir,
        ))
        print(f"\n완료! 파일: {result}")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
