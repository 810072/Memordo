document.addEventListener('DOMContentLoaded', () => {
  // UI 요소 가져오기
  const loginSection = document.getElementById('login-section');
  const mainSection = document.getElementById('main-section');
  const loginButton = document.getElementById('login-button');
  const logoutButton = document.getElementById('logout-button');
  const emailInput = document.getElementById('email-input');
  const passwordInput = document.getElementById('password-input');
  const loginStatus = document.getElementById('login-status');
  const userEmailEl = document.getElementById('user-email');

  const uploadBtn = document.getElementById('upload-button');
  const statusEl = document.getElementById('upload-status');
  const historyBtn = document.getElementById('view-history-button');
  const toggle = document.getElementById('tracking-toggle');

  // 로그인 상태에 따라 UI 업데이트하는 함수
  function updateUI(isLoggedIn, email = '') {
    if (isLoggedIn) {
      loginSection.style.display = 'none';
      mainSection.style.display = 'block';
      userEmailEl.textContent = email;
    } else {
      loginSection.style.display = 'block';
      mainSection.style.display = 'none';
      userEmailEl.textContent = '';
      passwordInput.value = ''; // 로그아웃 시 비밀번호 필드 초기화
    }
  }

  // 팝업이 열릴 때 로그인 상태 확인
  chrome.storage.local.get(['accessToken', 'userEmail'], (data) => {
    if (data.accessToken && data.userEmail) {
      updateUI(true, data.userEmail);
    } else {
      updateUI(false);
    }
  });

  // 로그인 버튼 클릭 이벤트
  loginButton.addEventListener('click', () => {
    const email = emailInput.value.trim();
    const password = passwordInput.value.trim();

    if (!email || !password) {
      loginStatus.textContent = '이메일과 비밀번호를 입력해주세요.';
      return;
    }

    loginStatus.textContent = '로그인 중...';

    // background 스크립트에 로그인 요청
    chrome.runtime.sendMessage({
      action: 'login',
      data: { email, password }
    }, (response) => {
      if (chrome.runtime.lastError) {
        loginStatus.textContent = '로그인 중 오류가 발생했습니다.';
        console.error("Message passing error:", chrome.runtime.lastError);
        return;
      }
      if (response && response.success) {
        loginStatus.textContent = '';
        updateUI(true, email);
      } else {
        loginStatus.textContent = response.message || '이메일 또는 비밀번호를 확인해주세요.';
      }
    });
  });

  // 로그아웃 버튼 클릭 이벤트
  logoutButton.addEventListener('click', () => {
      chrome.runtime.sendMessage({ action: 'logout' }, (response) => {
          if (response && response.success) {
              updateUI(false);
          }
      });
  });

  // Drive 업로드 버튼 이벤트
  uploadBtn.addEventListener('click', () => {
    statusEl.textContent = '업로드 중...';
    chrome.storage.local.get(['visitedUrls'], (data) => {
      chrome.runtime.sendMessage({ action: 'uploadToDrive', data: data.visitedUrls || [] }, (response) => {
        statusEl.textContent = (chrome.runtime.lastError || !response.success) ? '업로드 실패 ❌' : '업로드 완료 ✔️';
        setTimeout(() => statusEl.textContent = '', 3000);
      });
    });
  });

  // 방문 기록 보기 버튼 이벤트
  historyBtn.addEventListener('click', () => {
    chrome.windows.create({
      url: chrome.runtime.getURL('history/history.html'),
      type: 'popup',
      width: 600,
      height: 800
    });
  });

  // 추적 토글 스위치 상태 로드 및 변경 이벤트
  chrome.storage.sync.get(['trackingEnabled'], (result) => {
    toggle.checked = result.trackingEnabled ?? true;
  });

  toggle.addEventListener('change', () => {
    chrome.storage.sync.set({ trackingEnabled: toggle.checked });
  });
});