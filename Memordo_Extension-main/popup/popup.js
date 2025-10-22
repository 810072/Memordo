// Memordo_Extension-main/popup/popup.js
document.addEventListener('DOMContentLoaded', () => {
  console.log(">>> DOMContentLoaded event fired!");
  // --- UI 요소 가져오기 (변경 없음) ---
  console.log("Getting UI elements..."); // 요소 가져오기 시작 로그
  const loginSection = document.getElementById('login-section');
  const mainSection = document.getElementById('main-section');
  const loginButton = document.getElementById('login-button');
  const logoutButton = document.getElementById('logout-button');
  const emailInput = document.getElementById('email-input');
  const passwordInput = document.getElementById('password-input');
  const loginStatus = document.getElementById('login-status');
  const userEmailEl = document.getElementById('user-email');
  const uploadBtn = document.getElementById('upload-button'); // Drive 업로드 버튼
  const historyBtn = document.getElementById('view-history-button');
  const toggle = document.getElementById('tracking-toggle');
  const googleLoginButton = document.getElementById('google-login-button');
  console.log("UI elements obtained."); // 요소 가져오기 완료 로그
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

  // --- ✨ UI 업데이트 함수 (loginType 제거) ---
  function updateUI(isLoggedIn, email = '') { // loginType 파라미터 제거
    console.log(`[Popup] Updating UI: isLoggedIn=${isLoggedIn}, email=${email}`);
    if (isLoggedIn) {
      // === 로그인 상태 UI ===
      loginSection.style.display = 'none';
      mainSection.style.display = 'block';
      userEmailEl.textContent = email ? email.split('@')[0] : '사용자';

      // --- Drive 업로드 버튼 상태 업데이트 (항상 활성화) ---
      if (uploadBtn) {
        uploadBtn.disabled = false; // 로그인 상태면 항상 활성화
        uploadBtn.style.display = 'flex';
        uploadBtn.title = 'Google Drive에 방문 기록 업로드 (클릭 시 Google 인증 필요)'; // 툴팁 변경
      }

    } else {
      // === 비로그인 상태 UI ===
      loginSection.style.display = 'block';
      mainSection.style.display = 'none';
      userEmailEl.textContent = '';
      passwordInput.value = ''; // 비밀번호 필드 초기화
      if (uploadBtn) {
          uploadBtn.disabled = true; // 비로그인 시 비활성화
          uploadBtn.style.display = 'flex'; // 보이도록 유지
          uploadBtn.title = '로그인 후 사용 가능'; // 툴팁 업데이트
      }
    }
  }

  // --- ✨ 팝업 로딩 시 상태 확인 (loginType 제거) ---
  chrome.storage.local.get(['accessToken', 'userEmail'], (data) => { // loginType 제거
    console.log('[Popup] Initial storage data:', data); // 저장된 데이터 확인 로그
    if (data.accessToken && data.userEmail) {
      updateUI(true, data.userEmail); // loginType 전달 안 함
    } else {
      updateUI(false); // 비로그인 상태 UI
    }
  });

  // --- ✨ 일반 로그인 버튼 이벤트 (loginType 관련 제거) ---
  loginButton.addEventListener('click', () => {
    const email = emailInput.value.trim();
    const password = passwordInput.value.trim();
    if (!email || !password) { loginStatus.textContent = '이메일과 비밀번호 입력 필요.'; return; }
    loginStatus.textContent = '로그인 중...';
    loginButton.disabled = true; googleLoginButton.disabled = true; // 버튼 비활성화

    chrome.runtime.sendMessage({ action: 'login', data: { email, password } }, (response) => {
      loginButton.disabled = false; googleLoginButton.disabled = false; // 버튼 다시 활성화
      if (chrome.runtime.lastError) { loginStatus.textContent = '로그인 처리 오류'; console.error(chrome.runtime.lastError.message); return; }
      if (response && response.success) {
        loginStatus.textContent = '';
        updateUI(true, email); // UI 업데이트
        showToast("로그인되었습니다.");
      } else { loginStatus.textContent = response?.message || '로그인 실패.'; }
    });
  });

  // --- ✨ Google 로그인 버튼 이벤트 (loginType 관련 제거) ---
  googleLoginButton.addEventListener('click', () => {
      loginStatus.textContent = 'Google 로그인 진행 중...';
      googleLoginButton.disabled = true; loginButton.disabled = true; // 버튼 비활성화

      chrome.runtime.sendMessage({ action: 'googleLogin' }, (response) => {
          googleLoginButton.disabled = false; loginButton.disabled = false; // 버튼 다시 활성화
          if (chrome.runtime.lastError) { loginStatus.textContent = 'Google 로그인 처리 오류'; console.error(chrome.runtime.lastError.message); return; }
          if (response && response.success) {
              loginStatus.textContent = '';
              updateUI(true, response.email); // UI 업데이트
              showToast("Google 계정으로 로그인되었습니다.");
          } else { loginStatus.textContent = response?.message || 'Google 로그인 실패.'; }
      });
  });

  // 엔터 키 로그인 (변경 없음)
  function handleEnterLogin(event) {
      if (event.key === 'Enter') { event.preventDefault(); loginButton.click(); }
  }
  emailInput.addEventListener('keydown', handleEnterLogin);
  passwordInput.addEventListener('keydown', handleEnterLogin);

  // --- ✨ 로그아웃 버튼 이벤트 (loginType 관련 제거) ---
  logoutButton.addEventListener('click', () => {
      chrome.runtime.sendMessage({ action: 'logout' }, (response) => {
          if (chrome.runtime.lastError) { showToast("로그아웃 오류"); console.error(chrome.runtime.lastError.message); return; }
          if (response && response.success) {
              updateUI(false); // UI 업데이트
              emailInput.value = ''; passwordInput.value = ''; // 필드 초기화
              showToast("로그아웃 되었습니다.");
          } else { showToast("로그아웃 실패"); }
      });
  });

  // --- ✨ Drive 업로드 버튼 이벤트 (loginType 확인 제거) ---
  uploadBtn.addEventListener('click', () => {
    // === 로그인 상태 확인 (accessToken 유무만 확인) ===
    chrome.storage.local.get(['accessToken'], (storageData) => {
        if (!storageData.accessToken) {
            showToast('로그인이 필요한 기능입니다.');
            return;
        }

        // === Google Drive 업로드 실행 (클릭 시 인증 시작) ===
        showToast('Google Drive 업로드 중... (Google 인증 필요할 수 있음)');
        uploadBtn.disabled = true; // 업로드 중 버튼 비활성화

        // 로컬 저장소('visitedUrls')에서 데이터를 가져와 background로 전송
        chrome.storage.local.get(['visitedUrls'], (data) => {
          const urlsToUpload = data.visitedUrls || [];
          if (urlsToUpload.length === 0) {
              showToast("업로드할 방문 기록이 없습니다. (이전에 저장된 기록)");
              uploadBtn.disabled = false; // 버튼 다시 활성화
              return;
          }
          // background.js의 'uploadToDrive' 액션 호출
          chrome.runtime.sendMessage({ action: 'uploadToDrive', data: urlsToUpload }, (response) => {
            uploadBtn.disabled = false; // 버튼 다시 활성화
            if (chrome.runtime.lastError) {
                console.error("UploadToDrive message error:", chrome.runtime.lastError.message);
                showToast(`업로드 요청 실패 ❌ (${chrome.runtime.lastError.message || ''})`);
                return;
            }
            // Non-breaking space(\u00A0) 사용하여 줄바꿈 방지
            const uploadMessage = (response && response.success) ? '업로드 완료\u00A0✔️' : `업로드 실패\u00A0❌ (${response?.message || '오류 발생'})`;
            showToast(uploadMessage);

            // 성공 시 로컬 visitedUrls 비우기 (선택사항)
            // if (response && response.success) {
            //   chrome.storage.local.remove('visitedUrls');
            // }
          });
        });
    });
  });

  // 방문 기록 보기 버튼 이벤트 (변경 없음)
  historyBtn.addEventListener('click', () => {
      chrome.windows.create({ url: chrome.runtime.getURL('history/history.html'), type: 'popup', width: 600, height: 800 });
  });

  // 추적 토글 스위치 이벤트 (변경 없음)
  chrome.storage.sync.get(['trackingEnabled'], (result) => { toggle.checked = result.trackingEnabled ?? true; });
  toggle.addEventListener('change', () => {
      const newState = toggle.checked;
      chrome.storage.sync.set({ trackingEnabled: newState }, () => {
          console.log(`[Memordo] Tracking ${newState ? 'enabled' : 'disabled'}.`);
          showToast(`방문 기록 추적 ${newState ? '활성화됨' : '비활성화됨'}`);
      });
  });

}); // DOMContentLoaded 끝