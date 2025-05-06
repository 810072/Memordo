// history/history.js

document.addEventListener('DOMContentLoaded', () => {
  const historyList = document.getElementById('history-list');
  const deleteButton = document.getElementById('delete-selected-button'); // 삭제 버튼 참조 (이벤트 리스너용)
  const deleteStatus = document.getElementById('delete-status');     // 삭제 상태 메시지 참조
  const actionBar = document.querySelector('.action-bar'); // 액션 바 참조

  // 삭제 버튼 애니메이션 설정 (버튼이 존재할 경우)
  if (deleteButton) {
      // 버튼 텍스트를 span으로 감싸는 것은 버튼 자체 애니메이션용이므로 유지
      deleteButton.innerHTML = '<div><span>' + deleteButton.textContent.trim().split('').join('</span><span>') + '</span></div>';
  }

  // --- 액션 바 표시/숨김 상태 업데이트 함수 ---
  function updateActionBarVisibility() {
      // 액션 바가 없으면 함수 종료
      if (!actionBar) return;

      // historyList 내에서 체크된 체크박스가 하나라도 있는지 확인
      const anyCheckboxChecked = historyList.querySelector('.history-item-checkbox:checked');

      // 체크된 박스가 있으면 액션 바에 .visible 클래스 추가, 없으면 제거
      if (anyCheckboxChecked) {
          actionBar.classList.add('visible');
      } else {
          actionBar.classList.remove('visible');
      }
  }
  // --- 액션 바 업데이트 함수 끝 ---


  // --- 체크박스 변경 감지 이벤트 리스너 (이벤트 위임 사용) ---
  historyList.addEventListener('change', (event) => {
      if (event.target.matches('.history-item-checkbox')) {
          // 체크박스 상태가 변경되면 액션 바 표시 상태 업데이트
          updateActionBarVisibility();
      }
  });
  // --- 체크박스 이벤트 리스너 끝 ---


  // 방문 기록 목록을 렌더링하는 함수
  function renderHistory(visited) {
    historyList.innerHTML = ''; // 기존 목록 초기화

    // 기록이 없으면 메시지 표시
    if (!visited || visited.length === 0) {
      historyList.innerHTML = '<p>저장된 방문 기록이 없습니다.</p>';
      // 목록이 비었으므로 액션 바 상태 업데이트 (숨김 처리됨)
      updateActionBarVisibility();
      return;
    }

    // 날짜별 그룹화
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
            const timeString = new Date(entry.timestamp).toLocaleTimeString('ko-KR', { hour: 'numeric', minute:'2-digit', hour12: true });
            timeSpan.textContent = `${timeString}`;
            li.appendChild(timeSpan);
            ul.appendChild(li);
          });
        dateDiv.appendChild(ul);
        historyList.appendChild(dateDiv);
      });

      // --- 렌더링 완료 후 액션 바 상태 최종 업데이트 ---
      updateActionBarVisibility();
  }

  // --- 삭제 버튼 클릭 이벤트 리스너 (버튼 존재 시) ---
  if (deleteButton) {
      deleteButton.addEventListener('click', () => {
        const checkedBoxes = historyList.querySelectorAll('.history-item-checkbox:checked');

        if (checkedBoxes.length === 0) {
          deleteStatus.textContent = '삭제할 항목을 선택하세요.';
          setTimeout(() => deleteStatus.textContent = '', 3000);
          return;
        }

        const timestampsToDelete = Array.from(checkedBoxes).map(box => box.getAttribute('data-timestamp'));

        // 데이터 가져오기, 필터링, 저장
        chrome.storage.local.get('visitedUrls', (data) => {
          let visited = data.visitedUrls || [];
          const initialCount = visited.length;
          const updatedVisited = visited.filter(entry => !timestampsToDelete.includes(entry.timestamp));

          chrome.storage.local.set({ visitedUrls: updatedVisited }, () => {
            const deletedCount = initialCount - updatedVisited.length;
            console.log(`[Memordo] ${deletedCount}개의 방문 기록 삭제됨`);
            deleteStatus.textContent = `${deletedCount}개의 항목이 삭제되었습니다.`;
            setTimeout(() => deleteStatus.textContent = '', 3000);

            // 목록 다시 렌더링 (renderHistory 내부에서 액션 바 상태 업데이트 호출됨)
            renderHistory(updatedVisited);
          });
        });
      });
  }
  // ----------------------------------

  // 페이지 로드 시 초기 방문 기록 로드 및 렌더링
  chrome.storage.local.get('visitedUrls', (data) => {
    renderHistory(data.visitedUrls);
    // 초기 액션 바 상태는 CSS와 renderHistory 내의 update 호출로 설정됨
  });
});