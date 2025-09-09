// 확장 프로그램 설치 시 초기 설정
chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.sync.get(['trackingEnabled'], (result) => {
    if (typeof result.trackingEnabled === 'undefined') {
      chrome.storage.sync.set({ trackingEnabled: true }, () => {
        console.log('[memordo] trackingEnabled 초기값 설정됨: true');
      });
    }
  });

  chrome.storage.local.get(['bookmarkedUrls'], (result) => {
    if (!result.bookmarkedUrls) {
      chrome.storage.local.set({ bookmarkedUrls: [] }, () => {
        console.log('[memordo] bookmarkedUrls 초기값 설정됨: []');
      });
    }
  });
});

// 탭 정보가 업데이트될 때 방문 기록 저장
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status !== 'complete' || !tab.url || !tab.url.startsWith('http') || !tab.title) {
    return;
  }

  chrome.storage.sync.get(['trackingEnabled'], (syncData) => {
    if (!syncData.trackingEnabled) return;

    chrome.storage.local.get(['visitedUrls'], (localData) => {
      const visited = localData.visitedUrls || [];
      const normalizedNewUrl = normalizeUrl(tab.url);
      const alreadyVisited = visited.some(entry => normalizeUrl(entry.url) === normalizedNewUrl);
      if (!alreadyVisited) {
        visited.push({
          url: tab.url,
          title: tab.title,
          timestamp: new Date().toISOString()
        });
        chrome.storage.local.set({ visitedUrls: visited }, () => {
          console.log('[memordo] URL 및 제목 저장됨:', tab.url, tab.title);
        });
      }
    });
  });
});

// URL 정규화 함수
function normalizeUrl(url) {
  try {
    const parsed = new URL(url);
    const ignoredParams = ['page', 'timestamp'];
    ignoredParams.forEach(param => parsed.searchParams.delete(param));
    return parsed.origin + parsed.pathname;
  } catch (e) {
    return url;
  }
}

// Google 인증 토큰 가져오기
function getAuthToken(callback) {
  chrome.identity.getAuthToken({ interactive: true }, function(token) {
    if (chrome.runtime.lastError || !token) {
      console.error('인증 오류:', chrome.runtime.lastError);
      callback(null);
      return;
    }
    callback(token);
  });
}

// Google Drive 폴더 확인 및 생성
async function getOrCreateFolder(token, folderName) {
  const searchUrl = `https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(
    `name='${folderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false`
  )}&fields=files(id,name)`;
  const response = await fetch(searchUrl, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) { console.error('폴더 검색 실패:', response.statusText); return null; }
  const data = await response.json();
  if (data.files.length > 0) return data.files[0].id;

  const folderMetadata = { name: folderName, mimeType: 'application/vnd.google-apps.folder' };
  const createResp = await fetch('https://www.googleapis.com/drive/v3/files', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(folderMetadata),
  });
  if (!createResp.ok) { console.error('폴더 생성 실패:', createResp.statusText); return null; }
  const folder = await createResp.json();
  return folder.id;
}

// Google Drive에 데이터 업로드
async function uploadToDrive(jsonData) {
  return new Promise((resolve, reject) => {
    getAuthToken(async (token) => {
      if (!token) return reject(new Error('Google 인증 실패'));
      try {
        const folderId = await getOrCreateFolder(token, 'memordo');
        if (!folderId) return reject(new Error('폴더 접근 실패'));

        const metadata = {
          name: `visited_urls_${new Date().toISOString().split('T')[0]}.jsonl`,
          mimeType: 'application/jsonl',
          parents: [folderId],
        };
        const jsonl = jsonData.map((entry) => JSON.stringify(entry)).join('\n');
        const file = new Blob([jsonl], { type: 'application/jsonl' });

        const form = new FormData();
        form.append('metadata', new Blob([JSON.stringify(metadata)], { type: 'application/json' }));
        form.append('file', file);

        const uploadResp = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart', {
          method: 'POST',
          headers: new Headers({ Authorization: `Bearer ${token}` }),
          body: form,
        });
        if (!uploadResp.ok) return reject(new Error(`업로드 실패: ${JSON.stringify(await uploadResp.json())}`));
        resolve();
      } catch (error) {
        reject(error);
      }
    });
  });
}

// 팝업 및 다른 스크립트로부터 메시지를 수신하고 처리
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'login') {
    const { email, password } = message.data;
    const backendUrl = 'https://aidoctorgreen.com/memo/api/login';

    console.log(`[로그인 시도] URL: ${backendUrl}, 이메일: ${email}`);

    fetch(backendUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
    .then(response => {
      console.log('서버 응답 상태:', response.status, response.statusText);
      console.log('서버 응답 헤더:', Object.fromEntries(response.headers.entries()));
      if (!response.ok) {
        return response.text().then(text => {
          throw new Error(`서버 응답 오류: ${response.status} - ${text}`);
        });
      }
      return response.json();
    })
    .then(data => {
      console.log('서버 응답 내용 (JSON):', data);
      if (data.accessToken) {
        chrome.storage.local.set({
          accessToken: data.accessToken,
          refreshToken: data.refreshToken,
          userEmail: email
        }, () => sendResponse({ success: true }));
      } else {
        sendResponse({ success: false, message: data.message || '토큰이 응답에 없습니다.' });
      }
    })
    .catch(error => {
      console.error('[로그인 API 호출 실패]', error);
      sendResponse({ success: false, message: error.message || '서버와 통신할 수 없습니다.' });
    });
    return true; // 비동기 응답
  }

  if (message.action === 'logout') {
    chrome.storage.local.remove(['accessToken', 'refreshToken', 'userEmail'], () => {
      console.log('[로그아웃] 저장된 토큰과 이메일 정보 삭제 완료');
      sendResponse({ success: true });
    });
    return true; // 비동기 응답
  }
  
  if (message.action === 'uploadToDrive') {
    uploadToDrive(message.data)
      .then(() => sendResponse({ success: true }))
      .catch((error) => { console.error('업로드 중 오류:', error); sendResponse({ success: false }); });
    return true; // 비동기 응답
  }

  if (message.action === 'toggleBookmarks') {
    chrome.storage.local.get(['bookmarkedUrls', 'visitedUrls'], (data) => {
      let bookmarked = Array.isArray(data.bookmarkedUrls) ? data.bookmarkedUrls : [];
      const visited = Array.isArray(data.visitedUrls) ? data.visitedUrls : [];
      const itemsToToggle = message.data;
      let addedCount = 0; let removedCount = 0;
      itemsToToggle.forEach(item => {
        const { url, title, timestamp } = item;
        const index = bookmarked.findIndex(b => b.url === url && b.timestamp === timestamp);
        if (index > -1) { bookmarked.splice(index, 1); removedCount++; }
        else { const itemToAdd = visited.find(v => v.url === url && v.timestamp === timestamp) || { url, title, timestamp }; bookmarked.push(itemToAdd); addedCount++; }
      });
      chrome.storage.local.set({ bookmarkedUrls: bookmarked }, () => sendResponse({ success: true, addedCount, removedCount }));
    });
    return true; // 비동기 응답
  }
});