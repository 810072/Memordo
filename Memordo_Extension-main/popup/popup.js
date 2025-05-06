document.addEventListener('DOMContentLoaded', () => {
  const uploadBtn = document.getElementById('upload-button');
  const statusEl = document.getElementById('upload-status');
  const historyBtn = document.getElementById('view-history-button');
  const toggle = document.getElementById('tracking-toggle');

  // 업로드 버튼 중복 방지 처리
  const newUploadBtn = uploadBtn.cloneNode(true);
  uploadBtn.parentNode.replaceChild(newUploadBtn, uploadBtn);

  newUploadBtn.addEventListener('click', () => {
    statusEl.textContent = '업로드 중...';
    chrome.storage.local.get(['visitedUrls'], (data) => {
      chrome.runtime.sendMessage({ action: 'uploadToDrive', data: data.visitedUrls || [] }, (response) => {
        statusEl.textContent = (chrome.runtime.lastError || !response.success) ? '업로드 실패 ❌' : '업로드 완료 ✔️';
        setTimeout(() => statusEl.textContent = '', 3000);
      });
    });
  });

  // 방문 기록 보기 버튼 수정된 경로
  historyBtn.addEventListener('click', () => {
    chrome.windows.create({
      url: chrome.runtime.getURL('history/history.html'),
      type: 'popup',
      width: 600,
      height: 800
    });
  });

  // URL 추적 버튼 상태 로드
  chrome.storage.sync.get(['trackingEnabled'], (result) => {
    toggle.checked = result.trackingEnabled ?? true;
  });

  // URL 추적 상태 변경 저장
  toggle.addEventListener('change', () => {
    chrome.storage.sync.set({ trackingEnabled: toggle.checked });
  });
});
