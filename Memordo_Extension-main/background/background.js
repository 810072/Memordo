// Memordo_Extension-main/background/background.js

// --- 상단 ---
const BACKEND_API_URL = 'https://aidoctorgreen.com'; 

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
    // if (!result.visitedUrls) {
    //   chrome.storage.local.set({ visitedUrls: [] }, () => {
    //     console.log('[memordo] visitedUrls 초기값 설정됨: []');
    //   });
    // }
  });
});

// --- 방문 기록 처리 ---
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status !== 'complete' || !tab.url || !tab.url.startsWith('http') || !tab.title) {
    return;
  }

  chrome.storage.sync.get(['trackingEnabled'], (syncData) => {
    if (!syncData.trackingEnabled) {
      return;
    }

    chrome.storage.local.get(['accessToken'], (localData) => {
      if (localData.accessToken) {
        const newEntry = {
          url: tab.url,
          title: tab.title,
          timestamp: new Date().toISOString()
        };
        sendHistoryToBackend([newEntry]); 

        // chrome.storage.local.get(['visitedUrls'], (driveData) => {
        //     const visitedForGoogleDrive = driveData.visitedUrls || [];
        //     const normalizedNewUrl = normalizeUrl(tab.url); 
        //     const alreadyVisited = visitedForGoogleDrive.some(entry => normalizeUrl(entry.url) === normalizedNewUrl);
        //     if (!alreadyVisited) {
        //         visitedForGoogleDrive.push(newEntry);
        //         chrome.storage.local.set({ visitedUrls: visitedForGoogleDrive });
        //     }
        // });

      } else {
        // console.log('[Memordo] Not logged in, skipping history send.');
      }
    });
  });
});

function normalizeUrl(url) {
  try {
    const parsed = new URL(url);
    const ignoredParams = ['timestamp']; 
    ignoredParams.forEach(param => parsed.searchParams.delete(param));
    Array.from(parsed.searchParams.keys()).forEach(key => {
        if (key.startsWith('utm_')) { parsed.searchParams.delete(key); }
    });
    return parsed.origin + parsed.pathname + parsed.search;
  } catch (e) {
    console.warn(`[Memordo] Failed to normalize URL: ${url}`, e);
    return url; 
  }
}

// --- ✨ 'sendHistoryToBackend' 함수 수정 ---
async function sendHistoryToBackend(historyData) {
  if (!historyData || historyData.length === 0) {
    return;
  }

  const tokenData = await chrome.storage.local.get(['accessToken']);
  const token = tokenData.accessToken;

  if (!token) {
    console.log('[Memordo] Backend send failed: User not logged in (no access token found).');
    return; 
  }

  console.log(`[Memordo] Sending ${historyData.length} history entries to backend...`);

  try {
    const response = await fetch(`${BACKEND_API_URL}/memo/api/h/history/collect`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}` 
      },
      body: JSON.stringify(historyData), 
    });

    if (!response.ok) {
      // ==========================================================
      // <<<<<<< (수정) 403 오류 시 자동 로그아웃 호출 >>>>>>>
      // ==========================================================
      if (response.status === 403) {
        console.error('[Memordo] Token is invalid (403). Performing auto-logout.');
        performLogout(); // 토큰이 유효하지 않으므로 로그아웃 수행
      }
      // ==========================================================

      let errorDetails = `Status: ${response.status}`;
      const errorText = await response.text(); 
      try {
        const errorJson = JSON.parse(errorText); 
        errorDetails += `, Message: ${errorJson.message || 'Unknown error'}`;
      } catch (e) {
        errorDetails += `, Response: ${errorText.substring(0, 100)}`;
      }
      console.error(`[Memordo] History send failed: ${errorDetails}`);
      
    } else {
      const result = await response.json();
      console.log('[Memordo] History send successful:', result.message || 'OK');
    }
  } catch (error) {
    console.error('[Memordo] Network error during history send:', error);
  }
}

// // --- Google Drive 관련 함수 (변경 없음) ---
// function getAuthToken(callback, interactive = true) { 
//   chrome.identity.getAuthToken({ interactive: interactive }, function(token) { 
//     if (chrome.runtime.lastError || !token) {
//       const level = interactive ? 'error' : 'warn';
//       console[level](`Google 인증 토큰 획득 ${interactive ? '실패' : '자동 실패'}:`, chrome.runtime.lastError?.message || '토큰 없음');
//       callback(null); 
//       return;
//     }
//     callback(token); 
//   });
// }

// async function getOrCreateFolder(token, folderName) {
//   const searchUrl = `https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(
//     `name='${folderName}' and mimeType='application/vnd.google-apps.folder' and trashed=false`
//   )}&fields=files(id,name)`;
//   try {
//     const response = await fetch(searchUrl, { headers: { Authorization: `Bearer ${token}` } });
//     if (!response.ok) {
//         const errorBody = await response.json().catch(() => ({}));
//         console.error('Google Drive 폴더 검색 실패:', response.status, errorBody);
//         throw new Error(`폴더 검색 실패: ${response.status}`);
//     }
//     const data = await response.json();
//     if (data.files && data.files.length > 0) {
//         console.log(`Google Drive 폴더 '${folderName}' 찾음 (ID: ${data.files[0].id})`);
//         return data.files[0].id;
//     }

//     console.log(`Google Drive 폴더 '${folderName}' 생성 시도...`);
//     const folderMetadata = { name: folderName, mimeType: 'application/vnd.google-apps.folder' };
//     const createResp = await fetch('https://www.googleapis.com/drive/v3/files', {
//         method: 'POST',
//         headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
//         body: JSON.stringify(folderMetadata),
//     });
//     if (!createResp.ok) {
//         const errorBody = await createResp.json().catch(() => ({}));
//         console.error('Google Drive 폴더 생성 실패:', createResp.status, errorBody);
//         throw new Error(`폴더 생성 실패: ${createResp.status}`);
//     }
//     const folder = await createResp.json();
//     console.log(`Google Drive 폴더 '${folderName}' 생성 성공 (ID: ${folder.id})`);
//     return folder.id;
//   } catch(error) {
//       console.error("getOrCreateFolder 함수 오류:", error);
//       return null; 
//   }
// }

// async function _internalUploadToDrive(jsonData) {
//   console.log(`Google Drive 업로드 시작 (${jsonData?.length || 0} 항목)...`);
//   return new Promise((resolve, reject) => {
//     getAuthToken(async (token) => { 
//       if (!token) {
//           console.error('Google Drive 업로드 실패: 인증 토큰 없음.');
//           return reject(new Error('Google 인증 실패. 팝업에서 다시 시도해주세요.'));
//       }
//       try {
//         const folderId = await getOrCreateFolder(token, 'memordo'); 
//         if (!folderId) {
//             console.error('Google Drive 업로드 실패: 폴더 ID 없음.');
//             return reject(new Error('Google Drive 폴더 접근 실패'));
//         }

//         const timestamp = new Date().toISOString().split('T')[0]; 
//         const metadata = {
//           name: `visited_urls_${timestamp}.jsonl`, 
//           mimeType: 'application/jsonl', 
//           parents: [folderId], 
//         };

//         const jsonl = jsonData.map((entry) => JSON.stringify(entry)).join('\n');
//         const file = new Blob([jsonl], { type: 'application/jsonl' }); 

//         const form = new FormData();
//         form.append('metadata', new Blob([JSON.stringify(metadata)], { type: 'application/json' }));
//         form.append('file', file, metadata.name); 

//         console.log(`Google Drive에 파일 '${metadata.name}' 업로드 시도...`);
//         const uploadResp = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart', {
//           method: 'POST',
//           headers: { 'Authorization': `Bearer ${token}` }, 
//           body: form,
//         });

//         if (!uploadResp.ok) {
//           const errorBody = await uploadResp.json().catch(() => ({}));
//           console.error('Google Drive 업로드 실패:', uploadResp.status, errorBody);
//           return reject(new Error(`업로드 실패 (${uploadResp.status}): ${errorBody.error?.message || 'Unknown error'}`));
//         }

//         const uploadedFile = await uploadResp.json();
//         console.log(`Google Drive 업로드 성공! 파일 ID: ${uploadedFile.id}`);
//         resolve(); 

//       } catch (error) { 
//         console.error('Google Drive 업로드 처리 중 예외 발생:', error);
//         reject(error); 
//       }
//     }, true); 
//   });
// }

// ==========================================================
// <<<<<<< (추가) 공용 로그아웃 함수 >>>>>>>
// ==========================================================
function performLogout(sendResponse) {
  chrome.storage.local.remove([
      'accessToken', 'refreshToken', 'userEmail',
      ], () => {
    if (chrome.runtime.lastError) {
      console.error('[Memordo] 로그아웃 중 스토리지 삭제 실패:', chrome.runtime.lastError.message);
      if (sendResponse) sendResponse({ success: false, message: chrome.runtime.lastError.message });
    } else {
      console.log('[Memordo] 로그아웃 성공 (토큰 등 정보 삭제 완료).');
      if (sendResponse) sendResponse({ success: true });
    }
  });
}
// ==========================================================


// --- 메시지 리스너 ---
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  // 1. 일반 로그인
  if (message.action === 'login') {
    const { email, password } = message.data;
    const backendUrl = `${BACKEND_API_URL}/memo/api/login`;
    console.log(`[Background] 일반 로그인 시도: ${email}`);
    fetch(backendUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) })
    .then(response => { if (!response.ok) throw new Error('Login failed'); return response.json(); }) 
    .then(data => {
        if (data.accessToken) {
            chrome.storage.local.set({
                accessToken: data.accessToken, refreshToken: data.refreshToken, userEmail: email
            }, () => {
                 console.log('[Memordo] 일반 로그인 성공, 토큰 저장됨.');
                 sendResponse({ success: true });
            });
        } else { sendResponse({ success: false, message: data.message || '토큰 없음' }); }
    })
    .catch(error => { console.error('[Memordo] 일반 로그인 API 호출 실패:', error); sendResponse({ success: false, message: error.message || '서버 통신 오류' }); });
    return true; 
  }

  // // 2. Google 로그인
  // if (message.action === 'googleLogin') {
  //   console.log('[Background] Google 로그인 시도...');
  //   getAuthToken(async (googleToken) => {
  //       if (!googleToken) { sendResponse({ success: false, message: 'Google 인증 실패' }); return; }
  //       console.log('[Memordo] Google 인증 토큰 획득, 백엔드 전송 시도...');
        
  //       // --- (수정) 이전 단계에서 수정한 서버 API 호출 방식 (AccessToken 전송) ---
  //       const backendUrl = `${BACKEND_API_URL}/memo/api/google-login`;
  //       try {
  //           const response = await fetch(backendUrl, { 
  //               method: 'POST', 
  //               headers: { 'Content-Type': 'application/json' }, 
  //               // 'code' 대신 'googleAccessToken' 전송
  //               body: JSON.stringify({ googleAccessToken: googleToken }) 
  //           });
            
  //           if (!response.ok) { 
  //             const errorData = await response.json().catch(() => ({}));
  //             throw new Error(errorData.message || 'Server auth failed'); 
  //           }
            
  //           const data = await response.json();
            
  //           if (data.accessToken && data.email) {
  //               chrome.storage.local.set({
  //                   accessToken: data.accessToken, 
  //                   refreshToken: data.refreshToken, 
  //                   userEmail: data.email,
  //                   googleAccessToken: googleToken // 백엔드가 아닌 원본 Google 토큰 저장
  //                   // googleRefreshToken은 이 방식(implicit flow)으로는 얻을 수 없음
  //               }, () => {
  //                   console.log('[Memordo] Google 로그인 성공, 토큰 저장됨.');
  //                   sendResponse({ success: true, email: data.email });
  //               });
  //           } else { throw new Error(data.message || '백엔드 응답 오류'); }
  //       } catch (error) { console.error('[Memordo] Google 로그인 백엔드 통신 실패:', error); sendResponse({ success: false, message: error.message || '서버 통신 오류' }); }
  //   }, true);
  //   return true; 
  //  }

  // 3. 로그아웃 (공용 함수 호출로 변경)
  if (message.action === 'logout') {
    performLogout(sendResponse); // 공용 로그아웃 함수 호출
    return true; // 비동기 응답
  }

  // // 4. Google Drive 업로드
  // if (message.action === 'uploadToDrive') {
  //    console.log("Google Drive 업로드 요청 수신");
  //    _internalUploadToDrive(message.data)
  //         .then(() => sendResponse({ success: true }))
  //         .catch((error) => {
  //             console.error('Google Drive 업로드 처리 중 오류:', error);
  //             sendResponse({ success: false, message: error.message || '업로드 실패' });
  //         });
  //    return true; 
  // }

  // 5. 북마크 토글
  if (message.action === 'toggleBookmarks') {
    chrome.storage.local.get(['bookmarkedUrls', 'visitedUrls'], (data) => {
        let bookmarked = Array.isArray(data.bookmarkedUrls) ? data.bookmarkedUrls : [];
        // const visited = Array.isArray(data.visitedUrls) ? data.visitedUrls : []; 
        const itemsToToggle = message.data;
        let addedCount = 0; let removedCount = 0;
        itemsToToggle.forEach(item => {
            const { url, title, timestamp } = item;
            
            // (수정) 서버에서 오는 타임스탬프(YYYY-MM-DD HH:MM:SS)와 로컬(ISO) 형식을 모두 비교
            const normalizedTimestamp = timestamp.includes('T') ? timestamp : timestamp.replace(' ', 'T') + 'Z';
            
            const index = bookmarked.findIndex(b => 
                b.url === url && 
                (b.timestamp === timestamp || b.timestamp === normalizedTimestamp)
            );
            
            if (index > -1) { 
                bookmarked.splice(index, 1); 
                removedCount++; 
            } else {
                // 북마크에 추가할 때, background.js가 사용하는 ISO 형식으로 통일
                const itemToAdd = { url, title, timestamp: normalizedTimestamp };
                bookmarked.push(itemToAdd); 
                addedCount++;
            }
        });
        chrome.storage.local.set({ bookmarkedUrls: bookmarked }, () => {
            sendResponse({ success: true, addedCount, removedCount });
        });
    });
    return true; 
  }
// ==========================================================
  // <<<<<<< (추가) 6. 서버에서 기록 삭제 핸들러 >>>>>>>
  // ==========================================================
  if (message.action === 'deleteHistoryFromServer') {
    const itemsToDelete = message.data;
    
    (async () => {
      const tokenData = await chrome.storage.local.get(['accessToken']);
      const token = tokenData.accessToken;

      if (!token) {
        sendResponse({ success: false, message: '로그인이 필요합니다.' });
        return;
      }

      try {
        const response = await fetch(`${BACKEND_API_URL}/memo/api/h/history/delete`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
          },
          body: JSON.stringify(itemsToDelete)
        });

        if (response.status === 403) {
          performLogout(); // 자동 로그아웃
          sendResponse({ success: false, message: '토큰 만료. 자동 로그아웃됨.' });
          return;
        }

        if (!response.ok) {
          const errorData = await response.json().catch(() => ({}));
          throw new Error(errorData.message || `서버 오류 (${response.status})`);
        }

        const result = await response.json();
        sendResponse({ success: true, message: result.message });

      } catch (error) {
        console.error('Failed to delete history from server:', error);
        sendResponse({ success: false, message: error.message });
      }
    })(); // async IIFE 실행
    
    return true; // 비동기 응답
  }
  // ==========================================================
});