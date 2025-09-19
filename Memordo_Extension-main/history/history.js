document.addEventListener('DOMContentLoaded', () => {
  const historyList = document.getElementById('history-list');
  const deleteButton = document.getElementById('delete-selected-button');
  const bookmarkButton = document.getElementById('bookmark-selected-button');

  const filterAllButton = document.getElementById('filter-all');
  const filterBookmarksButton = document.getElementById('filter-bookmarks');
  let currentFilter = 'all';

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
      const dateKey = new Date(entry.timestamp).toISOString().split('T')[0];
      if (!groups[dateKey]) {
        groups[dateKey] = { date: new Date(entry.timestamp), entries: [] };
      }
      groups[dateKey].entries.push(entry);
      return groups;
    }, {});

    const sortedDateKeys = Object.keys(groupedByDate).sort((a, b) => new Date(b) - new Date(a));

    // ==========================================================
    // <<<<<<< 각 날짜 그룹별로 헤더와 목록을 생성하도록 수정 >>>>>>>
    // ==========================================================
    sortedDateKeys.forEach(dateKey => {
      const group = groupedByDate[dateKey];
      
      // 1. 날짜 그룹을 감싸는 div 생성
      const dateDiv = document.createElement('div');
      dateDiv.className = 'date-group';
      
      // 2. 날짜 헤더 생성
      const dateHeader = document.createElement('div');
      dateHeader.className = 'date-header';
      const options = { year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short' };
      dateHeader.textContent = group.date.toLocaleDateString('ko-KR', options);
      dateDiv.appendChild(dateHeader); // 그룹에 날짜 헤더 추가

      // 3. 방문 기록 목록(ul) 생성
      const ul = document.createElement('ul');
      group.entries
        .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
        .forEach(entry => {
          const li = document.createElement('li');
          const timeString = new Date(entry.timestamp).toLocaleTimeString('ko-KR', { hour: 'numeric', minute: '2-digit', hour12: true });
          li.innerHTML = `
            <input type="checkbox" class="history-item-checkbox" data-timestamp="${entry.timestamp}">
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
      dateDiv.appendChild(ul); // 그룹에 목록 추가

      historyList.appendChild(dateDiv); // 최종적으로 historyList에 그룹 추가
    });
    updateHeaderActions();
  }

  function loadAndRenderHistory() {
    chrome.storage.local.get(['visitedUrls', 'bookmarkedUrls'], (data) => {
      const visited = Array.isArray(data.visitedUrls) ? data.visitedUrls : [];
      const bookmarked = Array.isArray(data.bookmarkedUrls) ? data.bookmarkedUrls : [];
      renderHistory(visited, bookmarked);
    });
  }

  historyList.addEventListener('change', (event) => {
    if (event.target.matches('.history-item-checkbox')) {
      updateHeaderActions();
    }
  });

  deleteButton.addEventListener('click', () => {
    const checkedBoxes = historyList.querySelectorAll('.history-item-checkbox:checked');
    if (checkedBoxes.length === 0) return;
    const timestampsToDelete = Array.from(checkedBoxes).map(box => box.getAttribute('data-timestamp'));
    
    chrome.storage.local.get(['visitedUrls', 'bookmarkedUrls'], (data) => {
      let visited = data.visitedUrls || [];
      let bookmarked = data.bookmarkedUrls || [];
      let updatedVisited = visited.filter(entry => !timestampsToDelete.includes(entry.timestamp));
      let updatedBookmarked = bookmarked.filter(entry => !timestampsToDelete.includes(entry.timestamp));
      
      chrome.storage.local.set({ visitedUrls: updatedVisited, bookmarkedUrls: updatedBookmarked }, () => {
        showToast(`${timestampsToDelete.length}개의 항목을 삭제했습니다.`);
        loadAndRenderHistory();
      });
    });
  });

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
      // 검색 결과가 없는 날짜 그룹은 숨김
      group.style.display = groupHasVisibleItems ? 'block' : 'none';
    });
  });

  loadAndRenderHistory();
});