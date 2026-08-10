# config/models.sh — 서브 Claude 세션이 쓸 모델 id. **여기가 유일한 자리다.**
#
# 🔴 왜 한 곳인가 (2026-08-10): 같은 값이 `scripts/vault-append.sh` 와
#    `scripts/vault-audit-llm.sh` 에 따로 박혀 있었고, 둘 다 `claude-sonnet-4-6` 에서
#    멈춰 있었다. 사본이 둘이면 **한쪽만 고쳐지고 다른 쪽이 조용히 낡는다** —
#    실제로 그 지적이 `memory/ref_yaksu_marketplace.md:86` 에 적혀 있었는데도 방치됐다.
#    🔑 「적어두는 것」과 「도구가 잡는 것」은 다르다. 여기로 모으고
#       `tests/model-names-single-source.test.sh` 가 사본이 다시 생기는 걸 막는다.
#
# ⚠️ **이 값이 낡는 것 자체는 여기서 못 막는다.** 시험은 「사본이 하나인가」만 재고
#    「그 하나가 최신인가」는 못 잰다(그건 조회라 CI 에서 판정 불가가 된다).
#    ⇒ 모델 세대가 바뀌면 **여기 한 줄**만 고치면 된다는 게 이 파일의 값이다.
#
# 실측 2026-08-10: 아래 셋과 옛 `claude-opus-4-8`·`claude-sonnet-4-6` 이 **전부 응답한다**.
#   ⇒ 낡은 이름은 「깨진」 게 아니라 「낡은」 것이었다. 판정 불가였던 축을 불러서 갈랐다.

NINO_MODEL_OPUS="${NINO_MODEL_OPUS:-claude-opus-5}"        # 복잡한 판단·긴 추론
NINO_MODEL_SONNET="${NINO_MODEL_SONNET:-claude-sonnet-5}"  # 복잡한 코딩·멀티스텝
NINO_MODEL_HAIKU="${NINO_MODEL_HAIKU:-claude-haiku-4-5-20251001}"  # 간단한 검색·짧은 작업
