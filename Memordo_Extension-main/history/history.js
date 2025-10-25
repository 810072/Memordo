document.addEventListener('DOMContentLoaded', () => {
  const historyList = document.getElementById('history-list');
  const deleteButton = document.getElementById('delete-selected-button');
  const bookmarkButton = document.getElementById('bookmark-selected-button');

  const filterAllButton = document.getElementById('filter-all');
  const filterBookmarksButton = document.getElementById('filter-bookmarks');
  let currentFilter = 'all';

  const BACKEND_API_URL = 'https://aidoctorgreen.com';

  function showToast(message) {
    const existingToast = document.querySelector('.toast-notification');
    if (existingToast) {
      existingToast.remove();
    }

    const toast = document.createElement('div');
    toast.className = 'toast-notification';
    toast.textContent = message;
    document.body.appendChild(toast);

    setTimeout(() => {
      toast.classList.add('visible');
    }, 10);

    setTimeout(() => {
      toast.classList.remove('visible');
      toast.addEventListener('transitionend', () => toast.remove());
    }, 3000);
  }

  function updateHeaderActions() {
    const anyCheckboxChecked = historyList.querySelector('.history-item-checkbox:checked');
    deleteButton.disabled = !anyCheckboxChecked;
    bookmarkButton.disabled = !anyCheckboxChecked;
  }

  function renderHistory(visited, bookmarked) {
    historyList.innerHTML = '';
    const dataToRender = currentFilter === 'bookmarks' ? bookmarked : visited;

    if (!Array.isArray(dataToRender) || dataToRender.length === 0) {
      const message = currentFilter === 'bookmarks' ? '저장된 북마크가 없습니다.' : '저장된 방문 기록이 없습니다.';
      historyList.innerHTML = `<p class="empty-message">${message}</p>`;
      updateHeaderActions();
      return;
    }

    const groupedByDate = dataToRender.reduce((groups, entry) => {
      if (!entry || !entry.timestamp) return groups;
      
      const normalizedTimestampStr = entry.timestamp.includes('T') 
          ? entry.timestamp 
          : entry.timestamp.replace(' ', 'T');
      
      const entryDate = new Date(normalizedTimestampStr); 

      const year = entryDate.getFullYear();
      const month = (entryDate.getMonth() + 1).toString().padStart(2, '0');
      const day = entryDate.getDate().toString().padStart(2, '0');
      const dateKey = `${year}-${month}-${day}`;
      
      if (!groups[dateKey]) {
        groups[dateKey] = { date: entryDate, entries: [] };
      }
      groups[dateKey].entries.push(entry);
      return groups;
    }, {});

    const sortedDateKeys = Object.keys(groupedByDate).sort((a, b) => new Date(b) - new Date(a));

    sortedDateKeys.forEach(dateKey => {
      const group = groupedByDate[dateKey];
      
      const dateDiv = document.createElement('div');
      dateDiv.className = 'date-group';
      
      const dateHeader = document.createElement('div');
      dateHeader.className = 'date-header';
      const options = { year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short' };
      dateHeader.textContent = group.date.toLocaleDateString('ko-KR', options);
      dateDiv.appendChild(dateHeader); 

      const ul = document.createElement('ul');
      group.entries
        .sort((a, b) => {
           const timeA = new Date(a.timestamp.replace(' ', 'T'));
           const timeB = new Date(b.timestamp.replace(' ', 'T'));
           return timeB - timeA;
        })
        .forEach(entry => {
          const li = document.createElement('li');
          
          const entryTimestampStr = entry.timestamp.includes('T') ? entry.timestamp : entry.timestamp.replace(' ', 'T');
          const timeString = new Date(entryTimestampStr).toLocaleTimeString('ko-KR', { hour: 'numeric', minute: '2-digit', hour12: true });
          
          // ==========================================================
          // <<<<<<< (수정) 체크박스에 data-url 추가 >>>>>>>
          // ==========================================================
          li.innerHTML = `
            <input type="checkbox" class="history-item-checkbox" 
                   data-timestamp="${entry.timestamp}" 
                   data-url="${entry.url}">
            <div class="entry-details">
              <div class="entry-line-1">
                <span class="entry-title" title="${entry.title || ''}">${entry.title || entry.url}</span>
                <span class="timestamp">${timeString}</span>
              </div>
              <a href="${entry.url}" target="_blank" class="entry-url" title="${entry.url}">${entry.url}</a>
            </div>
          `;
          ul.appendChild(li);
        });
      dateDiv.appendChild(ul); 
      historyList.appendChild(dateDiv);
    });
    updateHeaderActions();
  }


  function loadAndRenderHistory() {
    chrome.storage.local.get(['bookmarkedUrls', 'accessToken'], (data) => {
      const bookmarked = Array.isArray(data.bookmarkedUrls) ? data.bookmarkedUrls : [];
      const token = data.accessToken;

      if (!token) {
        historyList.innerHTML = `<p class="empty-message">서버 기록을 보려면 로그인이 필요합니다.</p>`;
        updateHeaderActions();
        if (currentFilter === 'bookmarks') {
          renderHistory([], bookmarked); 
        }
        return;
      }

      fetch(`${BACKEND_API_URL}/memo/api/h/history/list?page=1&limit=1000`, { 
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        }
      })
      .then(response => {
        if (response.status === 403) {
          chrome.runtime.sendMessage({ action: 'logout' }); 
          throw new Error('로그인 토큰이 만료되었습니다. 팝업에서 다시 로그인해주세요.');
        }
        
        if (!response.ok) {
          throw new Error(`서버 오류 발생 (${response.status})`);
        }
        return response.json();
      })
      .then(apiData => {
        const visitedFromServer = apiData.results || []; 
        renderHistory(visitedFromServer, bookmarked);
      })
      .catch(error => {
        console.error('Failed to fetch server history:', error);
        historyList.innerHTML = `<p class="empty-message">기록을 불러오는 데 실패했습니다: ${error.message}</p>`;
        updateHeaderActions();
        if (currentFilter === 'bookmarks') {
          renderHistory([], bookmarked);
        }
      });
    });
  }

  historyList.addEventListener('change', (event) => {
    if (event.target.matches('.history-item-checkbox')) {
      updateHeaderActions();
    }
  });

  // ==========================================================
  // <<<<<<< (수정) deleteButton 클릭 이벤트 수정 >>>>>>>
  // ==========================================================
  deleteButton.addEventListener('click', () => {
    const checkedBoxes = historyList.querySelectorAll('.history-item-checkbox:checked');
    if (checkedBoxes.length === 0) return;

    if (currentFilter === 'all') {
      // --- '전체 기록' (서버) 탭일 경우 ---
      const itemsToDelete = Array.from(checkedBoxes).map(box => {
        return {
          url: box.getAttribute('data-url'),
          timestamp: box.getAttribute('data-timestamp')
        };
      });

      // background.js에 서버 삭제 요청
      chrome.runtime.sendMessage({ action: 'deleteHistoryFromServer', data: itemsToDelete }, (response) => {
        if (response && response.success) {
          showToast(response.message || '서버에서 삭제되었습니다.');
          loadAndRenderHistory(); // 목록 새로고침
        } else {
          showToast(`삭제 실패: ${response?.message || '알 수 없는 오류'}`);
        }
      });

    } else {
      // --- '북마크' (로컬) 탭일 경우 (기존 로직) ---
      const timestampsToDelete = Array.from(checkedBoxes).map(box => box.getAttribute('data-timestamp'));
      
      chrome.storage.local.get(['bookmarkedUrls'], (data) => {
        let bookmarked = data.bookmarkedUrls || [];
        let updatedBookmarked = bookmarked.filter(entry => !timestampsToDelete.includes(entry.timestamp));
        
        chrome.storage.local.set({ bookmarkedUrls: updatedBookmarked }, () => {
          showToast(`${timestampsToDelete.length}개의 항목을 (북마크에서) 삭제했습니다.`);
          loadAndRenderHistory();
        });
      });
    }
  });
  // ==========================================================


  bookmarkButton.addEventListener('click', () => {
    const checkedBoxes = historyList.querySelectorAll('.history-item-checkbox:checked');
    if (checkedBoxes.length === 0) return;
    const itemsToToggle = Array.from(checkedBoxes).map(box => {
      const li = box.closest('li');
      return {
        url: li.querySelector('a').href,
        title: li.querySelector('.entry-title').textContent,
        timestamp: box.getAttribute('data-timestamp') 
      };
    });

    chrome.runtime.sendMessage({ action: 'toggleBookmarks', data: itemsToToggle }, (response) => {
      if (response && response.success) {
        let message = '';
        if (response.addedCount > 0 && response.removedCount > 0) {
          message = `${response.addedCount}개 추가, ${response.removedCount}개 제거했습니다.`;
        } else if (response.addedCount > 0) {
          message = `${response.addedCount}개의 항목을 북마크에 추가했습니다.`;
        } else if (response.removedCount > 0) {
          message = `${response.removedCount}개의 항목을 북마크에서 제거했습니다.`;
        }
        if (message) showToast(message);
        
        loadAndRenderHistory();
      }
    });
  });

  filterAllButton.addEventListener('click', () => {
    currentFilter = 'all';
    filterAllButton.classList.add('active');
    filterBookmarksButton.classList.remove('active');
    loadAndRenderHistory();
  });

  filterBookmarksButton.addEventListener('click', () => {
    currentFilter = 'bookmarks';
    filterBookmarksButton.classList.add('active');
    filterAllButton.classList.remove('active');
    loadAndRenderHistory();
  });

  const searchInput = document.getElementById('search-input');
  searchInput.addEventListener('input', function(event) {
    const query = event.target.value.trim().toLowerCase();
    
    document.querySelectorAll('.date-group').forEach(group => {
      let groupHasVisibleItems = false;
      group.querySelectorAll('li').forEach(item => {
        const title = item.querySelector('.entry-title').textContent.toLowerCase();
        const url = item.querySelector('.entry-url').textContent.toLowerCase();
        const match = title.includes(query) || url.includes(query);
        item.style.display = match ? 'flex' : 'none';
        if (match) {
          groupHasVisibleItems = true;
        }
      });
      group.style.display = groupHasVisibleItems ? 'block' : 'none';
    });
  });

  loadAndRenderHistory();
});