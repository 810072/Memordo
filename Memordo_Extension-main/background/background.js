// Memordo_Extension-main/background/background.js

// --- 상단 ---
// 백엔드 API 주소 (실제 배포 시 HTTPS 주소로 변경)
const BACKEND_API_URL = 'https://aidoctorgreen.com'; // 웹 서버 주소로 변경

// 확장 프로그램 설치 시 초기 설정 (visitedUrls 초기화 유지)
chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.sync.get(['trackingEnabled'], (result) => {
    if (typeof result.trackingEnabled === 'undefined') {
      chrome.storage.sync.set({ trackingEnabled: true }, () => {
        console.log('[memordo] trackingEnabled 초기값 설정됨: true');
      });
    }
  });
  chrome.storage.local.get(['bookmarkedUrls', 'visitedUrls'], (result) => {
    if (!result.bookmarkedUrls) {
      chrome.storage.local.set({ bookmarkedUrls: [] }, () => {
        console.log('[memordo] bookmarkedUrls 초기값 설정됨: []');
      });
    }
    // visitedUrls는 수동 Drive 업로드 시 사용될 수 있으므로 초기화 유지
    if (!result.visitedUrls) {
      chrome.storage.local.set({ visitedUrls: [] }, () => {
        console.log('[memordo] visitedUrls 초기값 설정됨: []');
      });
    }
  });
});

// --- ✨ 방문 기록 처리: 로그인 시 항상 백엔드 API 호출 ---
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  // 유효한 URL, 상태, 제목인지 확인
  if (changeInfo.status !== 'complete' || !tab.url || !tab.url.startsWith('http') || !tab.title) {
    return;
  }

  // 추적 활성화 상태 확인
  chrome.storage.sync.get(['trackingEnabled'], (syncData) => {
    if (!syncData.trackingEnabled) {
      // console.log('[Memordo] Tracking disabled.'); // 필요 시 로그 활성화
      return;
    }

    // --- ✨ 로그인 상태 확인 (accessToken 유무) ---
    chrome.storage.local.get(['accessToken'], (localData) => {
      if (localData.accessToken) {
        // === 로그인 상태: 백엔드 API로 데이터 전송 ===
        const newEntry = {
          url: tab.url,
          title: tab.title,
          timestamp: new Date().toISOString() // ISO 8601 형식
        };
        sendHistoryToBackend([newEntry]); // 배열 형태로 백엔드 전송 함수 호출 (아래 정의됨)

        // === Google Drive 업로드용 로컬 저장 (선택적 유지) ===
        // 사용자가 'Drive 업로드' 버튼을 눌렀을 때 업로드할 데이터를 위해 로컬에도 저장
        chrome.storage.local.get(['visitedUrls'], (driveData) => {
            const visitedForGoogleDrive = driveData.visitedUrls || [];
            const normalizedNewUrl = normalizeUrl(tab.url); // URL 정규화 함수 (아래 정의됨)
            // 이미 저장된 URL인지 확인 (정규화된 URL 기준)
            const alreadyVisited = visitedForGoogleDrive.some(entry => normalizeUrl(entry.url) === normalizedNewUrl);
            if (!alreadyVisited) {
                visitedForGoogleDrive.push(newEntry);
                chrome.storage.local.set({ visitedUrls: visitedForGoogleDrive }, () => {
                    // console.log('[Memordo] URL 저장됨 (For potential Drive Upload):', tab.url); // 필요 시 로그 활성화
                });
            }
        });

      } else {
        // === 비로그인 상태: 아무 작업 안 함 ===
        // console.log('[Memordo] Not logged in, skipping history send.'); // 필요 시 로그 활성화
      }
    });
  });
});

// URL 정규화 함수 (쿼리 파라미터 일부 유지하도록 수정)
function normalizeUrl(url) {
  try {
    const parsed = new URL(url);
    const ignoredParams = ['timestamp']; // page 등 불필요한 파라미터 추가 가능
    ignoredParams.forEach(param => parsed.searchParams.delete(param));
    // 예: UTM 파라미터 등 추적 파라미터 제거
    Array.from(parsed.searchParams.keys()).forEach(key => {
        if (key.startsWith('utm_')) { parsed.searchParams.delete(key); }
    });
    // 호스트 + 경로 + 정리된 검색 파라미터 반환
    return parsed.origin + parsed.pathname + parsed.search;
  } catch (e) {
    console.warn(`[Memordo] Failed to normalize URL: ${url}`, e);
    return url; // 파싱 실패 시 원본 반환
  }
}

// 백엔드로 방문 기록 전송 함수 (async/await 사용)
async function sendHistoryToBackend(historyData) {
  if (!historyData || historyData.length === 0) {
    // console.log('[Memordo] No history data to send to backend.'); // 필요 시 로그 활성화
    return;
  }

  // 로컬 스토리지에서 Access Token 가져오기
  const tokenData = await chrome.storage.local.get(['accessToken']);
  const token = tokenData.accessToken;

  if (!token) {
    console.log('[Memordo] Backend send failed: User not logged in (no access token found).');
    // TODO: 사용자에게 로그인 필요 알림 (예: 팝업 상태 변경 또는 브라우저 알림)
    return; // 토큰 없으면 전송 중단
  }

  console.log(`[Memordo] Sending ${historyData.length} history entries to backend...`);

  try {
    const response = await fetch(`${BACKEND_API_URL}/memo/api/h/history/collect`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}` // <<< 인증 토큰 추가
      },
      body: JSON.stringify(historyData), // 데이터를 JSON 문자열로 변환
    });

    // 응답 상태 확인
    if (!response.ok) {
      // 오류 응답 처리
      let errorDetails = `Status: ${response.status}`;
      
      // 1. 응답 본문을 텍스트로 *딱 한 번만* 읽습니다.
      const errorText = await response.text(); 
      
      try {
        // 2. 읽어온 텍스트를 JSON으로 파싱 시도합니다.
        const errorJson = JSON.parse(errorText); 
        errorDetails += `, Message: ${errorJson.error || errorJson.message || 'Unknown error'}`;
      } catch (e) {
        // 3. 파싱에 실패하면 그냥 텍스트를 그대로 사용합니다.
        errorDetails += `, Response: ${errorText.substring(0, 100)}`;
      }
      console.error(`[Memordo] History send failed: ${errorDetails}`);
      
    } else {
      // 성공 응답 처리
      const result = await response.json();
      console.log('[Memordo] History send successful:', result.message || 'OK');
      // TODO: 성공적으로 전송된 데이터는 로컬 임시 저장소에서 삭제 (만약 임시 저장 방식을 사용한다면)
    }
  } catch (error) {
    // 네트워크 오류 등 예외 처리
    console.error('[Memordo] Network error during history send:', error);
    // TODO: 전송 실패 시 데이터를 로컬에 임시 저장하고 나중에 재시도하는 로직 구현
  }
}

// --- Google Drive 관련 함수 (유지) ---
// Google 인증 토큰 가져오기
function getAuthToken(callback, interactive = true) { // interactive 파라미터 추가
  chrome.identity.getAuthToken({ interactive: interactive }, function(token) { // interactive 사용
    if (chrome.runtime.lastError || !token) {
      const level = interactive ? 'error' : 'warn';
      console[level](`Google 인증 토큰 획득 ${interactive ? '실패' : '자동 실패'}:`, chrome.runtime.lastError?.message || '토큰 없음');
      callback(null); // 실패 시 null 콜백
      return;
    }
    // console.log("Google 인증 토큰 획득 성공."); // 성공 로그는 필요시에만
    callback(token); // 성공 시 토큰 콜백
  });
}

// Google Drive 폴더 확인 및 생성
async function getOrCreateFolder(token, folderName) {
  const searchUrl = `https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(
    `name='${folderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false`
  )}&fields=files(id,name)`;
  try {
    const response = await fetch(searchUrl, { headers: { Authorization: `Bearer ${token}` } });
    if (!response.ok) {
        const errorBody = await response.json().catch(() => ({}));
        console.error('Google Drive 폴더 검색 실패:', response.status, errorBody);
        throw new Error(`폴더 검색 실패: ${response.status}`);
    }
    const data = await response.json();
    if (data.files && data.files.length > 0) {
        console.log(`Google Drive 폴더 '${folderName}' 찾음 (ID: ${data.files[0].id})`);
        return data.files[0].id;
    }

    // 폴더가 없으면 생성
    console.log(`Google Drive 폴더 '${folderName}' 생성 시도...`);
    const folderMetadata = { name: folderName, mimeType: 'application/vnd.google-apps.folder' };
    const createResp = await fetch('https://www.googleapis.com/drive/v3/files', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(folderMetadata),
    });
    if (!createResp.ok) {
        const errorBody = await createResp.json().catch(() => ({}));
        console.error('Google Drive 폴더 생성 실패:', createResp.status, errorBody);
        throw new Error(`폴더 생성 실패: ${createResp.status}`);
    }
    const folder = await createResp.json();
    console.log(`Google Drive 폴더 '${folderName}' 생성 성공 (ID: ${folder.id})`);
    return folder.id;
  } catch(error) {
      console.error("getOrCreateFolder 함수 오류:", error);
      return null; // 실패 시 null 반환
  }
}

// Google Drive에 데이터 업로드 (내부 호출용으로 이름 변경 및 Promise 반환)
async function _internalUploadToDrive(jsonData) {
  console.log(`Google Drive 업로드 시작 (${jsonData?.length || 0} 항목)...`);
  return new Promise((resolve, reject) => {
    // Google 인증 토큰 가져오기 (사용자 인터랙션 가능)
    getAuthToken(async (token) => { // getAuthToken 콜백을 async로 변경
      if (!token) {
          console.error('Google Drive 업로드 실패: 인증 토큰 없음.');
          // 인증 실패 시 사용자에게 알림 (팝업에서 처리될 수도 있음)
          return reject(new Error('Google 인증 실패. 팝업에서 다시 시도해주세요.'));
      }
      try {
        // 'memordo' 폴더 ID 가져오기 (없으면 생성)
        const folderId = await getOrCreateFolder(token, 'memordo'); // 폴더 이름 확인
        if (!folderId) {
            console.error('Google Drive 업로드 실패: 폴더 ID 없음.');
            return reject(new Error('Google Drive 폴더 접근 실패'));
        }

        // 파일 이름에 날짜 포함
        const timestamp = new Date().toISOString().split('T')[0]; // YYYY-MM-DD
        const metadata = {
          name: `visited_urls_${timestamp}.jsonl`, // 파일 이름 형식
          mimeType: 'application/jsonl', // MIME 타입 확인
          parents: [folderId], // 'memordo' 폴더 안에 저장
        };

        // 데이터를 JSONL 형식 문자열로 변환
        const jsonl = jsonData.map((entry) => JSON.stringify(entry)).join('\n');
        const file = new Blob([jsonl], { type: 'application/jsonl' }); // Blob 타입 확인

        // FormData 구성
        const form = new FormData();
        form.append('metadata', new Blob([JSON.stringify(metadata)], { type: 'application/json' }));
        form.append('file', file, metadata.name); // 파일 이름 명시

        // 파일 업로드 요청 (multipart)
        console.log(`Google Drive에 파일 '${metadata.name}' 업로드 시도...`);
        const uploadResp = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart', {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${token}` }, // 헤더 간소화
          body: form,
        });

        // 업로드 결과 확인
        if (!uploadResp.ok) {
          const errorBody = await uploadResp.json().catch(() => ({}));
          console.error('Google Drive 업로드 실패:', uploadResp.status, errorBody);
          return reject(new Error(`업로드 실패 (${uploadResp.status}): ${errorBody.error?.message || 'Unknown error'}`));
        }

        const uploadedFile = await uploadResp.json();
        console.log(`Google Drive 업로드 성공! 파일 ID: ${uploadedFile.id}`);
        resolve(); // 성공 시 resolve

      } catch (error) { // getOrCreateFolder 또는 fetch 중 예외 발생 시
        console.error('Google Drive 업로드 처리 중 예외 발생:', error);
        reject(error); // 오류 시 reject
      }
    }, true); // interactive: true 로 설정하여 필요 시 사용자 인증 창 표시
  });
}


// --- ✨ 메시지 리스너 (loginType 관련 로직 제거) ---
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // 1. 일반 로그인 처리
  if (message.action === 'login') {
    const { email, password } = message.data;
    const backendUrl = `${BACKEND_API_URL}/memo/api/login`;
    console.log(`[Background] 일반 로그인 시도: ${email}`);
    fetch(backendUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) })
    .then(response => { if (!response.ok) throw new Error('Login failed'); return response.json(); }) // 간략화
    .then(data => {
        if (data.accessToken) {
            // loginType 저장 제거
            chrome.storage.local.set({
                accessToken: data.accessToken, refreshToken: data.refreshToken, userEmail: email
            }, () => {
                 console.log('[Memordo] 일반 로그인 성공, 토큰 저장됨.');
                 sendResponse({ success: true });
            });
        } else { sendResponse({ success: false, message: data.message || '토큰 없음' }); }
    })
    .catch(error => { console.error('[Memordo] 일반 로그인 API 호출 실패:', error); sendResponse({ success: false, message: error.message || '서버 통신 오류' }); });
    return true; // 비동기
  }

  // 2. Google 로그인 처리
  if (message.action === 'googleLogin') {
    console.log('[Background] Google 로그인 시도...');
    getAuthToken(async (googleToken) => {
        if (!googleToken) { sendResponse({ success: false, message: 'Google 인증 실패' }); return; }
        console.log('[Memordo] Google 인증 토큰 획득, 백엔드 전송 시도...');
        const backendUrl = `${BACKEND_API_URL}/memo/api/google-login`;
        try {
            const response = await fetch(backendUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ googleAccessToken: googleToken }) });
            if (!response.ok) { throw new Error('Server auth failed'); }
            const data = await response.json();
            if (data.accessToken && data.email) {
                // loginType 저장 제거
                chrome.storage.local.set({
                    accessToken: data.accessToken, refreshToken: data.refreshToken, userEmail: data.email,
                    googleAccessToken: data.googleAccessToken, googleRefreshToken: data.googleRefreshToken // 구글 토큰 저장 유지
                }, () => {
                    console.log('[Memordo] Google 로그인 성공, 토큰 저장됨.');
                    sendResponse({ success: true, email: data.email });
                });
            } else { throw new Error(data.message || '백엔드 응답 오류'); }
        } catch (error) { console.error('[Memordo] Google 로그인 백엔드 통신 실패:', error); sendResponse({ success: false, message: error.message || '서버 통신 오류' }); }
    }, true);
    return true; // 비동기
  }

  // 3. 로그아웃 처리
  if (message.action === 'logout') {
    chrome.storage.local.remove([
        'accessToken', 'refreshToken', 'userEmail',
        'googleAccessToken', 'googleRefreshToken' // 구글 관련 토큰도 삭제
        // loginType 제거 불필요
        ], () => {
      console.log('[Memordo] 로그아웃 성공, 관련 정보 삭제 완료.');
      sendResponse({ success: true });
    });
    return true; // 비동기
  }

  // 4. Google Drive 업로드 처리 (loginType 확인 불필요)
  if (message.action === 'uploadToDrive') {
     console.log("Google Drive 업로드 요청 수신");
     // _internalUploadToDrive는 내부적으로 getAuthToken(interactive: true) 호출
     _internalUploadToDrive(message.data)
          .then(() => sendResponse({ success: true }))
          .catch((error) => {
              console.error('Google Drive 업로드 처리 중 오류:', error);
              // 오류 메시지를 팝업에 전달
              sendResponse({ success: false, message: error.message || '업로드 실패' });
          });
     return true; // 비동기
  }

  // 5. 북마크 토글 처리 (변경 없음)
  if (message.action === 'toggleBookmarks') {
    chrome.storage.local.get(['bookmarkedUrls', 'visitedUrls'], (data) => {
        let bookmarked = Array.isArray(data.bookmarkedUrls) ? data.bookmarkedUrls : [];
        const visited = Array.isArray(data.visitedUrls) ? data.visitedUrls : []; // visitedUrls는 Drive 업로드용 데이터
        const itemsToToggle = message.data;
        let addedCount = 0; let removedCount = 0;
        itemsToToggle.forEach(item => {
            const { url, title, timestamp } = item;
            const index = bookmarked.findIndex(b => b.url === url && b.timestamp === timestamp);
            if (index > -1) { bookmarked.splice(index, 1); removedCount++; }
            else {
                // visitedUrls에서 해당 항목 찾거나 새로 생성
                const itemToAdd = visited.find(v => v.url === url && v.timestamp === timestamp) || { url, title, timestamp };
                bookmarked.push(itemToAdd); addedCount++;
            }
        });
        chrome.storage.local.set({ bookmarkedUrls: bookmarked }, () => {
            sendResponse({ success: true, addedCount, removedCount });
        });
    });
    return true; // 비동기
  }

}); // addListener 끝