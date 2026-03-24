#!/usr/bin/env node
// 유튜브 뮤직 탭 정리: 첫 번째 탭만 남기고 나머지 모두 닫기
const CDP_HOST = 'http://172.25.160.1:9222';

async function run() {
  const res = await fetch(`${CDP_HOST}/json`);
  const tabs = await res.json();
  const ytmTabs = tabs.filter(t => t.url && t.url.includes('music.youtube.com'));

  if (ytmTabs.length === 0) {
    console.log('YTM 탭 없음');
    return;
  }

  console.log(`YTM 탭 ${ytmTabs.length}개 발견`);

  // 첫 번째만 남기고 나머지 닫기
  const toClose = ytmTabs.slice(1);
  for (const tab of toClose) {
    await fetch(`${CDP_HOST}/json/close/${tab.id}`);
    console.log(`닫음: ${tab.id} (${tab.url.substring(0, 60)})`);
  }

  console.log(`정리 완료. YTM 탭 1개 유지 중`);
}

run().catch(console.error);
