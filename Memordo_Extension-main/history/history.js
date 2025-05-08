// history/history.js

document.addEventListener('DOMContentLoaded', () => {
  const historyList = document.getElementById('history-list');
  const deleteButton = document.getElementById('delete-selected-button');
  const deleteStatus = document.getElementById('delete-status');
  const actionBar = document.querySelector('.action-bar');
  const selectAllButton = document.getElementById('select-all-button'); // "전체 선택" 버튼 참조

  // 버튼 텍스트 애니메이션 설정 함수
  function setupButtonAnimation(button) {
    if (button && button.textContent.trim().length > 0) {
      button.innerHTML = '<div><span>' + button.textContent.trim().split('').join('</span><span>') + '</span></div>';
    }
  }

  setupButtonAnimation(deleteButton);
  setupButtonAnimation(selectAllButton); // "전체 선택" 버튼도 애니메이션 적용

  // 액션 바 표시/숨김 상태 업데이트 함수
  function updateActionBarVisibility() {
    if (!actionBar) return;
    const anyCheckboxChecked = historyList.querySelector('.history-item-checkbox:checked');
    if (anyCheckboxChecked) {
      actionBar.classList.add('visible');
    } else {
      actionBar.classList.remove('visible');
    }
  }

  // --- ▼▼▼ "전체 선택" 버튼 상태 및 텍스트 업데이트 함수 ▼▼▼ ---
  function updateSelectAllButtonState() {
    if (!selectAllButton) return;

    const itemCheckboxes = historyList.querySelectorAll('.history-item-checkbox');
    const totalItems = itemCheckboxes.length;
    const checkedItems = historyList.querySelectorAll('.history-item-checkbox:checked').length;

    let buttonText = "전체 선택"; // 기본 텍스트
    if (totalItems > 0 && totalItems === checkedItems) {
      buttonText = "전체 해제"; // 모든 항목이 선택된 경우
    }
    // 버튼 텍스트 변경 및 애니메이션 재설정
    selectAllButton.textContent = buttonText;
    setupButtonAnimation(selectAllButton);

    // 항목이 없으면 "전체 선택" 버튼 비활성화 (또는 숨김 처리도 가능)
    selectAllButton.disabled = totalItems === 0;
    if (totalItems === 0 && actionBar) { // 항목 없으면 액션바도 숨김
        actionBar.classList.remove('visible');
    }
  }
  // --- ▲▲▲ "전체 선택" 버튼 상태 업데이트 함수 끝 ▲▲▲ ---


  // --- ▼▼▼ "전체 선택" 버튼 클릭 이벤트 리스너 ▼▼▼ ---
  if (selectAllButton) {
    selectAllButton.addEventListener('click', () => {
      const itemCheckboxes = historyList.querySelectorAll('.history-item-checkbox');
      // 현재 모든 항목이 선택되어 있는지 여부로 토글 결정
      const areAllSelected = Array.from(itemCheckboxes).every(cb => cb.checked) && itemCheckboxes.length > 0;

      itemCheckboxes.forEach(checkbox => {
        checkbox.checked = !areAllSelected; // 전체 선택/해제 토글
      });

      updateActionBarVisibility(); // 액션 바 상태 업데이트
      updateSelectAllButtonState(); // "전체 선택" 버튼 상태 및 텍스트 업데이트
    });
  }
  // --- ▲▲▲ "전체 선택" 버튼 클릭 이벤트 리스너 끝 ▲▲▲ ---


  // --- 개별 체크박스 변경 감지 이벤트 리스너 ---
  historyList.addEventListener('change', (event) => {
    if (event.target.matches('.history-item-checkbox')) {
      updateActionBarVisibility();
      updateSelectAllButtonState(); // 개별 변경 시 "전체 선택" 버튼 상태 업데이트
    }
  });
  // --- 개별 체크박스 이벤트 리스너 끝 ---


  // 방문 기록 목록을 렌더링하는 함수
  function renderHistory(visited) {
    historyList.innerHTML = '';

    if (!visited || visited.length === 0) {
      historyList.innerHTML = '<p>저장된 방문 기록이 없습니다.</p>';
    } else {
      const groupedByDate = visited.reduce((groups, entry) => {
        if (!entry || !entry.timestamp) return groups;
        const dateKey = new Date(entry.timestamp).toISOString().split('T')[0];
        if (!groups[dateKey]) {
          groups[dateKey] = [];
        }
        groups[dateKey].push(entry);
        return groups;
      }, {});

      const sortedDateKeys = Object.keys(groupedByDate).sort((a, b) => new Date(b) - new Date(a));

      sortedDateKeys.forEach(dateKey => {
        const dateDiv = document.createElement('div');
        dateDiv.className = 'date-group';
        const dateObject = new Date(dateKey + 'T00:00:00');
        const options = { year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short' };
        const formattedDate = dateObject.toLocaleDateString('ko-KR', options);
        dateDiv.innerHTML = `<h3>${formattedDate}</h3>`;
        const ul = document.createElement('ul');

        groupedByDate[dateKey]
          .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
          .forEach(entry => {
            const li = document.createElement('li');
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.className = 'history-item-checkbox';
            checkbox.setAttribute('data-timestamp', entry.timestamp);
            li.appendChild(checkbox);

            const contentDiv = document.createElement('div');
            contentDiv.className = 'entry-content';
            const titleSpan = document.createElement('span');
            titleSpan.className = 'entry-title';
            titleSpan.textContent = entry.title || entry.url;
            titleSpan.title = entry.title || entry.url;
            contentDiv.appendChild(titleSpan);
            const link = document.createElement('a');
            link.href = entry.url;
            link.target = '_blank';
            link.textContent = entry.url;
            link.title = entry.url;
            contentDiv.appendChild(link);
            li.appendChild(contentDiv);

            const timeSpan = document.createElement('span');
            timeSpan.className = 'timestamp';
            const timeString = new Date(entry.timestamp).toLocaleTimeString('ko-KR', { hour: 'numeric', minute: '2-digit', hour12: true });
            timeSpan.textContent = `${timeString}`;
            li.appendChild(timeSpan);
            ul.appendChild(li);
          });
        dateDiv.appendChild(ul);
        historyList.appendChild(dateDiv);
      });
    }
    updateActionBarVisibility();
    updateSelectAllButtonState(); // 목록 렌더링 후 "전체 선택" 버튼 상태 업데이트
  }

  // 삭제 버튼 클릭 이벤트 리스너
  if (deleteButton) {
    deleteButton.addEventListener('click', () => {
      const checkedBoxes = historyList.querySelectorAll('.history-item-checkbox:checked');
      if (checkedBoxes.length === 0) {
        deleteStatus.textContent = '삭제할 항목을 선택하세요.';
        setTimeout(() => deleteStatus.textContent = '', 3000);
        return;
      }
      const timestampsToDelete = Array.from(checkedBoxes).map(box => box.getAttribute('data-timestamp'));
      chrome.storage.local.get('visitedUrls', (data) => {
        let visited = data.visitedUrls || [];
        const updatedVisited = visited.filter(entry => !timestampsToDelete.includes(entry.timestamp));
        chrome.storage.local.set({ visitedUrls: updatedVisited }, () => {
          const deletedCount = visited.length - updatedVisited.length;
          deleteStatus.textContent = `${deletedCount}개의 항목이 삭제되었습니다.`;
          setTimeout(() => deleteStatus.textContent = '', 3000);
          renderHistory(updatedVisited);
        });
      });
    });
  }

  // 페이지 로드 시 초기 방문 기록 로드
  chrome.storage.local.get('visitedUrls', (data) => {
    renderHistory(data.visitedUrls);
  });
});