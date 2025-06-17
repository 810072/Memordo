// history/history.js

document.addEventListener('DOMContentLoaded', () => {
  const historyList = document.getElementById('history-list');
  const deleteButton = document.getElementById('delete-selected-button');
  const deleteStatus = document.getElementById('delete-status');
  const actionBar = document.querySelector('.action-bar');
  const selectAllButton = document.getElementById('select-all-button');
  const bookmarkSelectedButton = document.getElementById('bookmark-selected-button'); // 북마크 버튼 참조 추가
  const bookmarkStatus = document.getElementById('bookmark-status'); // 북마크 상태 메시지 요소

  // 필터 탭 버튼 참조
  const filterAllButton = document.getElementById('filter-all');
  const filterBookmarksButton = document.getElementById('filter-bookmarks');

  let currentFilter = 'all'; // 'all' 또는 'bookmarks'

  // 버튼 텍스트 애니메이션 설정 함수
  function setupButtonAnimation(button) {
    if (button && button.textContent.trim().length > 0) {
      button.innerHTML = '<div><span>' + button.textContent.trim().split('').join('</span><span>') + '</span></div>';
    }
  }

  setupButtonAnimation(deleteButton);
  setupButtonAnimation(selectAllButton);
  setupButtonAnimation(bookmarkSelectedButton); // 북마크 버튼도 애니메이션 적용

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

  // "전체 선택" 버튼 상태 및 텍스트 업데이트 함수
  function updateSelectAllButtonState() {
    if (!selectAllButton) return;

    const itemCheckboxes = historyList.querySelectorAll('.history-item-checkbox');
    const totalItems = itemCheckboxes.length;
    const checkedItems = historyList.querySelectorAll('.history-item-checkbox:checked').length;

    let buttonText = "전체 선택";
    if (totalItems > 0 && totalItems === checkedItems) {
      buttonText = "전체 해제";
    }
    selectAllButton.textContent = buttonText;
    setupButtonAnimation(selectAllButton);

    selectAllButton.disabled = totalItems === 0;
    if (totalItems === 0 && actionBar) {
        actionBar.classList.remove('visible');
    }
  }


  // "전체 선택" 버튼 클릭 이벤트 리스너
  if (selectAllButton) {
    selectAllButton.addEventListener('click', () => {
      const itemCheckboxes = historyList.querySelectorAll('.history-item-checkbox');
      const areAllSelected = Array.from(itemCheckboxes).every(cb => cb.checked) && itemCheckboxes.length > 0;

      itemCheckboxes.forEach(checkbox => {
        checkbox.checked = !areAllSelected;
      });

      updateActionBarVisibility();
      updateSelectAllButtonState();
    });
  }

  // 개별 체크박스 변경 감지 이벤트 리스너
  historyList.addEventListener('change', (event) => {
    if (event.target.matches('.history-item-checkbox')) {
      updateActionBarVisibility();
      updateSelectAllButtonState();
    }
  });

  // 북마크 버튼 클릭 이벤트 핸들러 (새로 추가)
  if (bookmarkSelectedButton) {
      bookmarkSelectedButton.addEventListener('click', () => {
          const checkedBoxes = historyList.querySelectorAll('.history-item-checkbox:checked');
          if (checkedBoxes.length === 0) {
              bookmarkStatus.textContent = '북마크할 항목을 선택하세요.';
              setTimeout(() => bookmarkStatus.textContent = '', 3000);
              return;
          }

          const itemsToToggle = Array.from(checkedBoxes).map(box => {
              const li = box.closest('li');
              return {
                  url: li.querySelector('a').href,
                  title: li.querySelector('.entry-title').textContent,
                  timestamp: box.getAttribute('data-timestamp')
              };
          });

          chrome.runtime.sendMessage({
              action: 'toggleBookmarks', // 복수형으로 변경
              data: itemsToToggle
          }, (response) => {
              if (response && response.success) {
                  const addedCount = response.addedCount || 0;
                  const removedCount = response.removedCount || 0;
                  let message = '';
                  if (addedCount > 0) message += `${addedCount}개 북마크 추가됨. `;
                  if (removedCount > 0) message += `${removedCount}개 북마크 제거됨.`;
                  if (message === '') message = '선택된 항목의 북마크 상태가 변경되었습니다.';
                  bookmarkStatus.textContent = message;
                  setTimeout(() => bookmarkStatus.textContent = '', 3000);
                  loadAndRenderHistory(); // 북마크 상태 변경 후 UI 업데이트
              } else {
                  bookmarkStatus.textContent = '북마크 처리 실패 ❌';
                  setTimeout(() => bookmarkStatus.textContent = '', 3000);
              }
          });
      });
  }


  // 방문 기록 목록을 렌더링하는 함수 (기존 개별 북마크 아이콘 로직 제거)
  async function renderHistory(visited, bookmarked) {
    historyList.innerHTML = '';
    const dataToRender = currentFilter === 'bookmarks' ? bookmarked : visited; // 필터에 따라 렌더링할 데이터 선택

    // dataToRender가 배열인지 한 번 더 확인 (reduce 오류 방지)
    if (!Array.isArray(dataToRender) || dataToRender.length === 0) {
      historyList.innerHTML = `<p>${currentFilter === 'bookmarks' ? '저장된 북마크가 없습니다.' : '저장된 방문 기록이 없습니다.'}</p>`;
    } else {
      const groupedByDate = dataToRender.reduce((groups, entry) => {
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

            // 타임스탬프는 그대로 유지
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
    updateSelectAllButtonState();
    // 검색창 초기화
    document.getElementById('search-input').value = '';
    resultCount.textContent = '';
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

      // 현재 필터에 따라 삭제 대상 변경 (북마크에서도 삭제되도록)
      chrome.storage.local.get(['visitedUrls', 'bookmarkedUrls'], (data) => {
        let visited = data.visitedUrls || [];
        let bookmarked = data.bookmarkedUrls || [];

        let updatedVisited = visited.filter(entry => !timestampsToDelete.includes(entry.timestamp));
        let updatedBookmarked = bookmarked.filter(entry => !timestampsToDelete.includes(entry.timestamp));

        chrome.storage.local.set({ visitedUrls: updatedVisited, bookmarkedUrls: updatedBookmarked }, () => {
          const deletedCount = (currentFilter === 'bookmarks' ?
                               bookmarked.length - updatedBookmarked.length :
                               visited.length - updatedVisited.length); // 삭제된 개수 계산
          deleteStatus.textContent = `${deletedCount}개의 항목이 삭제되었습니다.`;
          setTimeout(() => deleteStatus.textContent = '', 3000);
          loadAndRenderHistory(); // 삭제 후 다시 로드
        });
      });
    });
  }

  // 방문 기록 로드 및 렌더링 함수 (수정됨: visited와 bookmarked를 모두 가져와 renderHistory에 전달)
  function loadAndRenderHistory() {
    chrome.storage.local.get(['visitedUrls', 'bookmarkedUrls'], (data) => {
        // 가져온 데이터가 배열이 아니면 빈 배열로 초기화
        const visited = Array.isArray(data.visitedUrls) ? data.visitedUrls : [];
        const bookmarked = Array.isArray(data.bookmarkedUrls) ? data.bookmarkedUrls : [];
        renderHistory(visited, bookmarked); // visited와 bookmarked 모두 전달
    });
  }

  // 페이지 로드 시 초기 방문 기록 로드
  loadAndRenderHistory();

  // 필터 탭 클릭 이벤트 리스너
  filterAllButton.addEventListener('click', () => {
    currentFilter = 'all';
    filterAllButton.classList.add('active');
    filterBookmarksButton.classList.remove('active');
    loadAndRenderHistory(); // 모든 기록 다시 로드
  });

  filterBookmarksButton.addEventListener('click', () => {
    currentFilter = 'bookmarks';
    filterBookmarksButton.classList.add('active');
    filterAllButton.classList.remove('active');
    loadAndRenderHistory(); // 북마크 기록 다시 로드
  });

  // 초성 추출 함수
  function getChosung(text) {
    const CHOSUNG_LIST = [
      'ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ',
      'ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ',
      'ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'
    ];

    let result = "";
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i) - 44032;
      if (code > -1 && code < 11172) {
        result += CHOSUNG_LIST[Math.floor(code / 588)];
      } else {
        result += text[i];
      }
    }
    return result;
  }
  const resultCount = document.getElementById('result-count');

  document.getElementById('search-input').addEventListener('input', function(event) {
    const query = event.target.value.trim().toLowerCase();
    let matchedCount = 0;

    // 검색은 현재 활성화된 필터의 데이터에 대해서만 수행
    document.querySelectorAll('.date-group').forEach(group => {
      let groupHasMatch = false;

      group.querySelectorAll('li').forEach(item => {
        const title = item.querySelector('.entry-title').textContent.toLowerCase();
        const url = item.querySelector('a').textContent.toLowerCase();

        const titleChosung = getChosung(title);
        const queryChosung = getChosung(query);

        const match = title.includes(query) ||
                      url.includes(query) ||
                      titleChosung.includes(queryChosung);

        item.style.display = match ? '' : 'none';

        if (match) {
          groupHasMatch = true;
          matchedCount++;
        }
      });

      group.style.display = groupHasMatch ? '' : 'none';
    });

    resultCount.textContent = query ? `검색 결과: ${matchedCount}개` : '';
  });
});