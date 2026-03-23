# OneDrive Vault 업로드 스킬

WSL2에서 OneDrive Vault 경로에 파일/폴더를 생성하고 클라우드에 동기화하는 스킬.

## 배경
WSL2에서 OneDrive 경로(`/mnt/c/Users/bpx27/OneDrive/문서/Vault/`)에 새 파일/폴더를 만들면 OneDrive가 감지하지 못해 동기화가 안 됨. PowerShell, CMD, Shell COM, robocopy, SHChangeNotify 모두 실패. **rclone**으로 클라우드에 직접 업로드하는 방식으로 해결.

## 사용법

### CLI 도구: `onedrive-upload`
```bash
# 파일 업로드
~/discord-bot-nino/onedrive-upload file.md 문서/Vault/research/

# 폴더 업로드
~/discord-bot-nino/onedrive-upload ./my-folder/ 문서/Vault/

# 폴더 생성
~/discord-bot-nino/onedrive-upload --mkdir 문서/Vault/new-folder

# 디렉토리 동기화
~/discord-bot-nino/onedrive-upload --sync /local/path 문서/Vault/target

# 목록 확인
~/discord-bot-nino/onedrive-upload --ls 문서/Vault/
```

### rclone 직접 사용
```bash
~/.local/bin/rclone copy /path/to/file "onedrive:문서/Vault/folder/"
~/.local/bin/rclone mkdir "onedrive:문서/Vault/new-folder"
~/.local/bin/rclone lsd "onedrive:문서/Vault/"
~/.local/bin/rclone sync /local/dir "onedrive:문서/Vault/target/" --progress
```

## 워크플로우: Vault에 새 콘텐츠 추가

1. **로컬에 파일 작성** (WSL 어디든 OK)
2. **rclone으로 OneDrive 클라우드에 업로드** (`onedrive-upload` 사용)
3. **로컬 OneDrive 경로에도 복사** (Obsidian에서 바로 볼 수 있도록)
   ```bash
   cp file.md /mnt/c/Users/bpx27/OneDrive/문서/Vault/folder/
   ```

## 주의사항
- OneDrive 경로: `문서/Vault/` (rclone에서는 앞에 슬래시 없이)
- 로컬 경로: `/mnt/c/Users/bpx27/OneDrive/문서/Vault/`
- rclone config: `~/.config/rclone/rclone.conf` (토큰 자동 갱신)
- 기존 파일 수정도 WSL에서 하면 OneDrive 동기화 안 될 수 있음 → 수정 후에도 rclone으로 업로드할 것
- **파일 생성/수정 후 항상 rclone 업로드를 기본으로** (로컬 OneDrive 동기화에 의존하지 말 것)
