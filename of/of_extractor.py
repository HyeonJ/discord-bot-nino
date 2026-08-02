"""OnlyFans media extractor — detect media type, DRM, and extract URLs."""
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional
import re


@dataclass(frozen=True)
class MediaItem:
    type: str  # 'img' | 'vid'
    url: str
    quality: Optional[str] = None
    drm: bool = False


def detect_drm(video_info: Optional[Dict[str, Any]]) -> bool:
    """Return True for DASH+Widevine DRM signatures."""
    if not isinstance(video_info, dict):
        return False

    if video_info.get("drm") is True or video_info.get("isDrm") is True:
        return True

    key_systems = video_info.get("keySystems") or video_info.get("key_systems") or []
    if isinstance(key_systems, str):
        key_systems = [key_systems]
    has_drm_system = any(
        isinstance(ks, str) and ("widevine" in ks.lower() or "playready" in ks.lower())
        for ks in key_systems
    )

    video_src = str(video_info.get("videoSrc") or video_info.get("src") or "")
    has_blob_src = video_src.startswith("blob:")

    manifest_url = str(video_info.get("manifestUrl") or video_info.get("manifest") or "")
    has_dash = ".mpd" in manifest_url.lower()

    if ".mpd" in video_src.lower():
        has_dash = True

    for source in _to_list(video_info.get("sources")):
        if not isinstance(source, dict):
            continue
        src = str(source.get("src") or "")
        mime = str(source.get("type") or "")
        if ".mpd" in src.lower() or "application/dash+xml" in mime.lower():
            has_dash = True

    return has_drm_system and (has_dash or has_blob_src)


def detect_media_type(page_info: Optional[Dict[str, Any]]) -> str:
    """Returns: 'swiper', 'single_video', 'single_image', 'no_media'"""
    if not isinstance(page_info, dict):
        return "no_media"

    if page_info.get("hasSwiper") is True:
        return "swiper"

    slides = page_info.get("slides")
    if isinstance(slides, list) and slides:
        return "swiper"

    if page_info.get("hasVideo") is True or isinstance(page_info.get("video"), dict):
        return "single_video"

    if page_info.get("hasImage") is True or isinstance(page_info.get("image"), dict):
        return "single_image"

    return "no_media"


def extract_media_urls(ab_eval_fn: Callable[[str], Any], post_id: str) -> List[MediaItem]:
    """Extract all media URLs from current post page.

    ab_eval_fn should return a page_info dict when called with "extractMedia".
    """
    del post_id
    page_info = ab_eval_fn("extractMedia")
    if not isinstance(page_info, dict):
        return []

    media_type = detect_media_type(page_info)

    if media_type == "no_media":
        return []

    if media_type == "swiper":
        slides = page_info.get("slides") or []
        return _collect_swiper_media(slides) if isinstance(slides, list) else []

    if media_type == "single_video":
        video = page_info.get("video")
        if not isinstance(video, dict):
            return []
        # Check for direct CDN URL first (even if DRM is configured)
        # Prefer best quality from <source> elements if available
        best_src, best_q = _pick_best_video_source(video)
        # 🔴 DASH 매니페스트는 «직행 CDN URL» 이 아니다 (2026-08-02)
        #   `.mpd` 는 cdn 호스트에 있고 blob: 도 아니라 이 분기를 통과해버렸다. 그러면
        #   아래 detect_drm() 이 **도달 불가**가 되어 DRM 영상이 drm=False 로 나가고,
        #   받는 쪽은 재생 안 되는 매니페스트를 평범한 파일로 내려받는다.
        #   detect_drm() 자체는 멀쩡했다 — 분기 «순서»가 거기 못 가게 막고 있었다.
        if best_src and not best_src.startswith("blob:") and ".mpd" not in best_src.lower() \
                and ("cdn" in best_src or ".mp4" in best_src):
            return [MediaItem(type="vid", url=best_src, quality=str(best_q) if best_q else None)]
        direct_url = video.get("directUrl") or video.get("src")
        if isinstance(direct_url, str) and not direct_url.startswith("blob:") \
                and ".mpd" not in direct_url.lower() and ("cdn" in direct_url or ".mp4" in direct_url):
            return [MediaItem(type="vid", url=direct_url)]
        if detect_drm(video):
            source = video.get("manifestUrl") or video.get("src")
            return [MediaItem(type="vid", url=str(source), quality="dash", drm=True)] if source else []
        if best_src:
            return [MediaItem(type="vid", url=best_src, quality=str(best_q) if best_q else None)]
        return []

    # single_image
    image = page_info.get("image") or {}
    url = image.get("url") if isinstance(image, dict) else page_info.get("imageUrl")
    return [MediaItem(type="img", url=str(url))] if url else []


# --- internal helpers ---

def _to_list(value: Any) -> list:
    return value if isinstance(value, list) else []


def _video_quality_score(label: Optional[str]) -> int:
    if not label:
        return -1
    lowered = str(label).lower()
    if "original" in lowered or "source" in lowered:
        return 10_000
    match = re.search(r"(\d+)", lowered)
    if match:
        return int(match.group(1))
    return -1


def _pick_best_video_source(video_info: Dict[str, Any]) -> tuple:
    """Pick highest quality non-DRM source. Returns (url, label)."""
    sources = _to_list(video_info.get("sources"))
    if not sources:
        src = video_info.get("source") or video_info.get("url") or video_info.get("videoSrc")
        return (str(src) if src else None, None)

    normalized = []
    for src in sources:
        if isinstance(src, str):
            normalized.append({"src": src, "label": None})
        elif isinstance(src, dict) and src.get("src"):
            normalized.append(dict(src))

    normalized = [s for s in normalized if s.get("src")]
    if not normalized:
        return None, None

    normalized.sort(
        key=lambda s: _video_quality_score(s.get("label")),
        reverse=True,
    )
    best = normalized[0]
    return str(best["src"]), best.get("label")


def _collect_swiper_media(slides: list) -> List[MediaItem]:
    items: List[MediaItem] = []
    seen: set = set()

    for slide in slides:
        if not isinstance(slide, dict):
            continue

        kind = str(slide.get("type") or slide.get("mediaType") or "").lower()

        if kind in ("image", "img"):
            url = slide.get("url") or slide.get("src")
            if url and url not in seen:
                seen.add(url)
                items.append(MediaItem(type="img", url=str(url)))
            continue

        if kind in ("video", "vid") or isinstance(slide.get("video"), dict):
            video = slide.get("video") if isinstance(slide.get("video"), dict) else slide
            if not isinstance(video, dict):
                continue
            if detect_drm(video):
                src = video.get("manifestUrl") or video.get("url")
                if src and src not in seen:
                    seen.add(src)
                    items.append(MediaItem(type="vid", url=str(src), quality="dash", drm=True))
            else:
                url, q = _pick_best_video_source(video)
                if url and url not in seen:
                    seen.add(url)
                    items.append(MediaItem(type="vid", url=url, quality=str(q) if q else None))
            continue

    return items
