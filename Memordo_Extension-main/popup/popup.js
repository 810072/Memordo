// Memordo_Extension-main/popup/popup.js
document.addEventListener('DOMContentLoaded', () => {
  console.log(">>> DOMContentLoaded event fired!");
  // --- UI 요소 가져오기 (googleLoginButton 제거) ---
  console.log("Getting UI elements..."); 
  const loginSection = document.getElementById('login-section');
  const mainSection = document.getElementById('main-section');
  const loginButton = document.getElementById('login-button');
  const logoutButton = document.getElementById('logout-button');
  const emailInput = document.getElementById('email-input');
  const passwordInput = document.getElementById('password-input');
  const loginStatus = document.getElementById('login-status');
  const userEmailEl = document.getElementById('user-email');
  // const uploadBtn = document.getElementById('upload-button'); 
  const historyBtn = document.getElementById('view-history-button');
  const toggle = document.getElementById('tracking-toggle');
  // const googleLoginButton = document.getElementById('google-login-button'); // << 1. 이 줄 삭제
  console.log("UI elements obtained."); 
  
  // --- 토스트 알림 함수 (변경 없음) ---
  function showToast(message) {
    const existingToast = document.querySelector('.toast-notification');
    if (existingToast) { existingToast.remove(); }
    const toast = document.createElement('div');
    toast.className = 'toast-notification';
    toast.textContent = message;
    document.body.appendChild(toast);
    setTimeout(() => { toast.classList.add('visible'); }, 10);
    setTimeout(() => {
      toast.classList.remove('visible');
      toast.addEventListener('transitionend', () => toast.remove());
    }, 3000);
  }

  // --- UI 업데이트 함수 (변경 없음) ---
  function updateUI(isLoggedIn, email = '') { 
    console.log(`[Popup] Updating UI: isLoggedIn=${isLoggedIn}, email=${email}`);
    if (isLoggedIn) {
      loginSection.style.display = 'none';
      mainSection.style.display = 'block';
      userEmailEl.textContent = email ? email.split('@')[0] : '사용자';
    } else {
      loginSection.style.display = 'block';
      mainSection.style.display = 'none';
      userEmailEl.textContent = '';
      passwordInput.value = ''; 
      }
    }
  

  // --- 팝업 로딩 시 상태 확인 (변경 없음) ---
  chrome.storage.local.get(['accessToken', 'userEmail'], (data) => { 
    console.log('[Popup] Initial storage data:', data); 
    if (data.accessToken && data.userEmail) {
      updateUI(true, data.userEmail); 
    } else {
      updateUI(false); 
    }
  });

  // --- 일반 로그인 버튼 이벤트 (googleLoginButton 관련 코드 제거) ---
  loginButton.addEventListener('click', () => {
    const email = emailInput.value.trim();
    const password = passwordInput.value.trim();
    if (!email || !password) { loginStatus.textContent = '이메일과 비밀번호 입력 필요.'; return; }
    loginStatus.textContent = '로그인 중...';
    loginButton.disabled = true; 
    // googleLoginButton.disabled = true; // << 2. 이 줄 삭제

    chrome.runtime.sendMessage({ action: 'login', data: { email, password } }, (response) => {
      loginButton.disabled = false; 
      // googleLoginButton.disabled = false; // << 3. 이 줄 삭제
      if (chrome.runtime.lastError) { loginStatus.textContent = '로그인 처리 오류'; console.error(chrome.runtime.lastError.message); return; }
      if (response && response.success) {
        loginStatus.textContent = '';
        updateUI(true, email); 
        showToast("로그인되었습니다.");
      } else { loginStatus.textContent = response?.message || '로그인 실패.'; }
    });
  });

  // --- Google 로그인 버튼 이벤트 (블록 전체 삭제) ---
  /* // << 4. 이 블록 전체 삭제
  googleLoginButton.addEventListener('click', () => {
      ...
  });
  */

  // --- 엔터 키 로그인 (변경 없음) ---
  function handleEnterLogin(event) {
      if (event.key === 'Enter') { event.preventDefault(); loginButton.click(); }
  }
  emailInput.addEventListener('keydown', handleEnterLogin);
  passwordInput.addEventListener('keydown', handleEnterLogin);

  // --- 로그아웃 버튼 이벤트 (변경 없음) ---
  logoutButton.addEventListener('click', () => {
      chrome.runtime.sendMessage({ action: 'logout' }, (response) => {
          if (chrome.runtime.lastError) { showToast("로그아웃 오류"); console.error(chrome.runtime.lastError.message); return; }
          if (response && response.success) {
              updateUI(false); 
              emailInput.value = ''; passwordInput.value = ''; 
              showToast("로그아웃 되었습니다.");
          } else { showToast("로그아웃 실패"); }
      });
  });

  // // --- Drive 업로드 버튼 이벤트 (변경 없음) ---
  // uploadBtn.addEventListener('click', () => {
  //   chrome.storage.local.get(['accessToken'], (storageData) => {
  //       if (!storageData.accessToken) {
  //           showToast('로그인이 필요한 기능입니다.');
  //           return;
  //       }

  //       showToast('Google Drive 업로드 중... (Google 인증 필요할 수 있음)');
  //       uploadBtn.disabled = true; 

  //       chrome.storage.local.get(['visitedUrls'], (data) => {
  //         const urlsToUpload = data.visitedUrls || [];
  //         if (urlsToUpload.length === 0) {
  //             showToast("업로드할 방문 기록이 없습니다. (이전에 저장된 기록)");
  //             uploadBtn.disabled = false; 
  //             return;
  //         }
  //         chrome.runtime.sendMessage({ action: 'uploadToDrive', data: urlsToUpload }, (response) => {
  //           uploadBtn.disabled = false; 
  //           if (chrome.runtime.lastError) {
  //               console.error("UploadToDrive message error:", chrome.runtime.lastError.message);
  //               showToast(`업로드 요청 실패 ❌ (${chrome.runtime.lastError.message || ''})`);
  //               return;
  //           }
  //           const uploadMessage = (response && response.success) ? '업로드 완료\u00A0✔️' : `업로드 실패\u00A0❌ (${response?.message || '오류 발생'})`;
  //           showToast(uploadMessage);
  //         });
  //       });
  //   });
  // });

  // --- 방문 기록 보기 버튼 이벤트 (변경 없음) ---
  historyBtn.addEventListener('click', () => {
      chrome.windows.create({ url: chrome.runtime.getURL('history/history.html'), type: 'popup', width: 600, height: 800 });
  });

  // --- 추적 토글 스위치 이벤트 (변경 없음) ---
  chrome.storage.sync.get(['trackingEnabled'], (result) => { toggle.checked = result.trackingEnabled ?? true; });
  toggle.addEventListener('change', () => {
      const newState = toggle.checked;
      chrome.storage.sync.set({ trackingEnabled: newState }, () => {
          console.log(`[Memordo] Tracking ${newState ? 'enabled' : 'disabled'}.`);
          showToast(`방문 기록 추적 ${newState ? '활성화됨' : '비활성화됨'}`);
      });
  });

});