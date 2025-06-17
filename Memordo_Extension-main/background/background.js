chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.sync.get(['trackingEnabled'], (result) => {
    if (typeof result.trackingEnabled === 'undefined') {
      chrome.storage.sync.set({ trackingEnabled: true }, () => {
        console.log('[memordo] trackingEnabled 초기값 설정됨: true');
      });
    }
  });

  // 북마크된 URL 초기화 (새로운 설치 시)
  chrome.storage.local.get(['bookmarkedUrls'], (result) => {
    if (!result.bookmarkedUrls) {
      chrome.storage.local.set({ bookmarkedUrls: [] }, () => {
        console.log('[memordo] bookmarkedUrls 초기값 설정됨: []');
      });
    }
  });
});

// 탭 변경 시 실행
// background/background.js

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  // 페이지 로딩이 완료되고, 유효한 URL이며, 제목이 있을 때만 처리
  if (changeInfo.status !== 'complete' || !tab.url || !tab.url.startsWith('http') || !tab.title) {
    return;
  }

  chrome.storage.sync.get(['trackingEnabled'], (syncData) => {
    if (!syncData.trackingEnabled) return;

    chrome.storage.local.get(['visitedUrls'], (localData) => {
      const visited = localData.visitedUrls || [];
      const normalizedNewUrl = normalizeUrl(tab.url);
      // URL 중복 확인 (기존과 동일)
      const alreadyVisited = visited.some(entry => normalizeUrl(entry.url) === normalizedNewUrl);
      if (!alreadyVisited) {
        // title 추가
        visited.push({
          url: tab.url,
          title: tab.title, // 페이지 제목 저장
          timestamp: new Date().toISOString()
        });

        // local에 저장
        chrome.storage.local.set({ visitedUrls: visited }, () => {
          console.log('[memordo] URL 및 제목 저장됨:', tab.url, tab.title); // 로그 수정
        });
      }
    });
  });
});

//URL 정규화 함수
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

// 인증 토큰 받기
function getAuthToken(callback) {
  chrome.identity.getAuthToken({ interactive: true }, function(token) {
    if (chrome.runtime.lastError || !token) {
      console.error('인증 오류:', chrome.runtime.lastError);
      return;
    }
    callback(token);
  });
}

// 폴더 확인 및 생성
async function getOrCreateFolder(token, folderName) {
  const searchUrl = `https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(
    `name='${folderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false`
  )}&fields=files(id,name)`;

  const response = await fetch(searchUrl, {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (!response.ok) {
    console.error('폴더 검색 실패:', response.statusText);
    return null;
  }

  const data = await response.json();

  if (data.files.length > 0) {
    console.log('기존 폴더 사용:', data.files[0].id);
    return data.files[0].id;
  } else {
    // 폴더 생성
    const folderMetadata = {
      name: folderName,
      mimeType: 'application/vnd.google-apps.folder',
    };

    const createResp = await fetch('https://www.googleapis.com/drive/v3/files', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(folderMetadata),
    });

    if (!createResp.ok) {
      console.error('폴더 생성 실패:', createResp.statusText);
      return null;
    }

    const folder = await createResp.json();
    console.log('새 폴더 생성됨:', folder.id);
    return folder.id;
  }
}

// 드라이브 업로드 함수
async function uploadToDrive(jsonData) {
  return new Promise((resolve, reject) => {
    getAuthToken(async (token) => {
      try {
        const folderId = await getOrCreateFolder(token, 'memordo');
        if (!folderId) {
          reject(new Error('폴더 접근 실패'));
          return;
        }

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

        if (!uploadResp.ok) {
          const errorInfo = await uploadResp.json();
          reject(new Error(`업로드 실패: ${JSON.stringify(errorInfo)}`));
          return;
        }

        const uploadedFile = await uploadResp.json();
        console.log('업로드 성공:', uploadedFile);
        resolve();
      } catch (error) {
        reject(error);
      }
    });
  });
}


//메세지 리스너 (toggleBookmark -> toggleBookmarks로 변경, 여러 항목 처리)
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'uploadToDrive') {
    uploadToDrive(message.data)
      .then(() => sendResponse({ success: true }))
      .catch((error) => {
        console.error('업로드 중 오류:', error);
        sendResponse({ success: false });
      });
    return true; // 비동기 응답 시 반드시 필요
  } else if (message.action === 'toggleBookmarks') { // 변경된 액션명
    chrome.storage.local.get(['bookmarkedUrls', 'visitedUrls'], (data) => {
      // bookmarkedUrls가 배열이 아닐 경우 []로 초기화 (방어적 코드)
      let bookmarked = Array.isArray(data.bookmarkedUrls) ? data.bookmarkedUrls : [];
      const visited = Array.isArray(data.visitedUrls) ? data.visitedUrls : []; // visitedUrls도 방어적으로 초기화

      const itemsToToggle = message.data; // 이제 배열을 받음
      let addedCount = 0;
      let removedCount = 0;

      itemsToToggle.forEach(item => {
        const { url, title, timestamp } = item;
        // 기존 북마크에 해당 항목이 있는지 정확히 확인
        const existingBookmarkIndex = bookmarked.findIndex(b => b.url === url && b.timestamp === timestamp);

        if (existingBookmarkIndex > -1) {
          // 이미 북마크되어 있으면 제거
          bookmarked.splice(existingBookmarkIndex, 1);
          removedCount++;
          console.log('[memordo] 북마크 제거됨:', title || url);
        } else {
          // 북마크되지 않았으면 추가
          // 방문 기록에서 해당 항목을 정확히 찾아와서 북마크에 추가 (title이 없을 수도 있으므로)
          const itemToBookmark = visited.find(v => v.url === url && v.timestamp === timestamp);
          if (itemToBookmark) {
              bookmarked.push(itemToBookmark);
          } else {
              // visitedUrls에 없는 경우 (예: 검색 후 북마크) - 이 시나리오에선 발생 가능성이 낮음
              // 하지만 안전을 위해, 받은 정보 그대로 추가
              bookmarked.push({ url, title, timestamp });
          }
          addedCount++;
          console.log('[memordo] 북마크 추가됨:', title || url);
        }
      });

      chrome.storage.local.set({ bookmarkedUrls: bookmarked }, () => {
        sendResponse({ success: true, addedCount, removedCount });
      });
    });
    return true; // 비동기 응답 시 반드시 필요
  }
});