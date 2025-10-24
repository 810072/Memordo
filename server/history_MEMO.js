// server/history_MEMO.js
const express = require('express');
const db = require('./db_MEMO'); // MEMO DB 연결 가져오기
const { verifyToken } = require('./auth_MEMO'); // 인증 미들웨어 가져오기
const router = express.Router();

// POST /memo/api/history/collect
router.post('/history/collect', verifyToken, async (req, res) => {
  const userId = req.user.id; // verifyToken에서 설정된 사용자 ID
  const historyData = req.body;

  if (!Array.isArray(historyData)) {
    return res.status(400).json({ message: '데이터는 배열 형태여야 합니다.' });
  }

  if (historyData.length === 0) {
    return res.status(200).json({ message: '처리할 데이터 없음', status: 'ok' });
  }

  let insertedCount = 0;
  let skippedCount = 0;
  let errorCount = 0;

  const connection = await db.getConnection(); // 커넥션 풀 사용 권장

  try {
    await connection.beginTransaction(); // 트랜잭션 시작

    for (const entry of historyData) {
      const { url, title, timestamp } = entry;
      if (!url || !timestamp) {
        skippedCount++; // 유효하지 않은 데이터 건너뛰기
        continue;
      }

      try {
        // ISO 문자열 timestamp를 MySQL DATETIME 형식으로 변환 시도
        const sqlTimestamp = new Date(timestamp).toISOString().slice(0, 19).replace('T', ' ');

        // INSERT IGNORE: UNIQUE 제약조건 위반 시 무시하고 다음으로 진행
        const [result] = await connection.query(
          `INSERT IGNORE INTO visit_history (user_id, url, title, timestamp)
           VALUES (?, ?, ?, ?)`,
          [userId, url, title || null, sqlTimestamp]
        );
        if (result.affectedRows > 0) {
          insertedCount++;
        } else if (result.warningStatus === 0) { // IGNORE된 경우 warningStatus가 0이 아닐 수 있음
            skippedCount++; // 중복으로 간주
        }
      } catch (insertError) {
        console.error('DB Insert Error:', insertError.message, 'Data:', entry);
        errorCount++;
        // 실패해도 계속 진행 (부분 성공 가능하도록)
      }
    }

    await connection.commit(); // 모든 처리 후 커밋

    const status = errorCount > 0 ? (insertedCount > 0 ? 'partial_error' : 'error') : 'ok';
    const statusCode = status === 'ok' ? 200 : (status === 'partial_error' ? 207 : 500);

    return res.status(statusCode).json({
      message: `처리 완료. 성공: ${insertedCount}, 건너뜀(중복/무효): ${skippedCount}, 오류: ${errorCount}.`,
      status: status
    });

  } catch (err) {
    await connection.rollback(); // 전체 트랜잭션 롤백
    console.error('History Collect API Error:', err.message);
    return res.status(500).json({ message: '서버 오류 발생' });
  } finally {
    connection.release(); // 커넥션 반환
  }
});

const { URL } = require('url'); // Node.js 내장 URL 파서

// GET /memo/api/history/stats
router.get('/history/stats', verifyToken, async (req, res) => {
  const userId = req.user.id;

  try {
    // TODO: 기간 필터링 로직 추가 (쿼리 파라미터 사용)
    const [rows] = await db.query(
      `SELECT url, timestamp FROM visit_history WHERE user_id = ? ORDER BY timestamp DESC`, // 최근 데이터 위주
      [userId]
    );

    if (rows.length === 0) {
      return res.status(200).json({ /* 빈 통계 데이터 */ message: '분석할 데이터 없음' });
    }

    const totalVisits = rows.length;
    const domainCounts = {};
    const hourlyCounts = Array(24).fill(0);
    const dailyCounts = Array(7).fill(0); // 0:일요일, 1:월요일 ... 6:토요일

    rows.forEach(row => {
      try {
        // 도메인 추출 및 카운트
        const parsedUrl = new URL(row.url);
        const domain = parsedUrl.hostname.toLowerCase();
        domainCounts[domain] = (domainCounts[domain] || 0) + 1;

        // 시간대별/요일별 카운트
        const visitDate = new Date(row.timestamp);
        hourlyCounts[visitDate.getHours()]++;
        dailyCounts[visitDate.getDay()]++;
      } catch (e) {
        // URL 파싱 오류 등은 무시
      }
    });

    // Top 도메인 정렬
    const topDomains = Object.entries(domainCounts)
      .sort(([, countA], [, countB]) => countB - countA)
      .slice(0, 10)
      .reduce((obj, [domain, count]) => {
        obj[domain] = count;
        return obj;
      }, {});

    // 요일 순서 맞추기 (월~일)
    const dayNames = ["월", "화", "수", "목", "금", "토", "일"];
    const dailyStats = {};
    for (let i = 0; i < 7; i++) {
        // JS getDay()는 일(0)~토(6), Python weekday()는 월(0)~일(6) -> 조정 필요
        const pythonDayIndex = (i === 0) ? 6 : i - 1; // 일요일(0) -> 6, 월(1) -> 0 ...
        dailyStats[dayNames[pythonDayIndex]] = dailyCounts[i];
    }


    const hourlyStats = {};
     for (let i = 0; i < 24; i++) {
        hourlyStats[i] = hourlyCounts[i];
     }


    return res.status(200).json({
      total_visits: totalVisits,
      top_domains: topDomains,
      visits_by_hour: hourlyStats,
      visits_by_day: dailyStats // Python 코드와 순서 맞춤
    });

  } catch (err) {
    console.error('History Stats API Error:', err.message);
    return res.status(500).json({ message: '서버 오류 발생' });
  }
});

// server/history_MEMO.js (계속)

// GET /memo/api/history/search
router.get('/history/search', verifyToken, async (req, res) => {
  const userId = req.user.id;
  const query = req.query.q || '';
  const page = parseInt(req.query.page || '1', 10);
  const limit = parseInt(req.query.limit || '50', 10);

  if (!query) {
    return res.status(400).json({ message: '검색어(q)가 필요합니다.' });
  }
  if (isNaN(page) || page < 1 || isNaN(limit) || limit < 1) {
     return res.status(400).json({ message: 'page와 limit은 1 이상의 숫자여야 합니다.' });
  }

  const offset = (page - 1) * limit;
  const searchTerm = `%${query.toLowerCase()}%`;

  try {
    // 검색 결과 조회 (최신순)
    const [results] = await db.query(
      `SELECT url, title, timestamp
       FROM visit_history
       WHERE user_id = ? AND (LOWER(title) LIKE ? OR LOWER(url) LIKE ?)
       ORDER BY timestamp DESC
       LIMIT ? OFFSET ?`,
      [userId, searchTerm, searchTerm, limit, offset]
    );

    // 전체 결과 수 조회 (페이지네이션 용)
    const [[{ total }]] = await db.query( // 구조 분해 할당으로 total 값 바로 추출
      `SELECT COUNT(*) as total
       FROM visit_history
       WHERE user_id = ? AND (LOWER(title) LIKE ? OR LOWER(url) LIKE ?)`,
      [userId, searchTerm, searchTerm]
    );

    return res.status(200).json({
      results: results,
      page: page,
      limit: limit,
      total_results: total,
      total_pages: Math.ceil(total / limit)
    });

  } catch (err) {
    console.error('History Search API Error:', err.message);
    return res.status(500).json({ message: '서버 오류 발생' });
  }
});

// --- ✨ 새로운 GET 엔드포인트 추가 ---
// GET /memo/api/h/history/list (모든 기록 조회)
router.get('/history/list', verifyToken, async (req, res) => {
  const userId = req.user.id;
  const page = parseInt(req.query.page || '1', 10);
  const limit = parseInt(req.query.limit || '100', 10); // 한 번에 가져올 개수 (조절 가능)

  if (isNaN(page) || page < 1 || isNaN(limit) || limit < 1) {
    return res.status(400).json({ message: 'page와 limit은 1 이상의 숫자여야 합니다.' });
  }

  const offset = (page - 1) * limit;

  try {
    // 사용자의 모든 방문 기록 조회 (최신순)
    const [results] = await db.query(
      `SELECT url, title, timestamp
       FROM visit_history
       WHERE user_id = ?
       ORDER BY timestamp DESC
       LIMIT ? OFFSET ?`,
      [userId, limit, offset]
    );

    // 전체 결과 수 조회 (페이지네이션 용)
    const [[{ total }]] = await db.query(
      `SELECT COUNT(*) as total
       FROM visit_history
       WHERE user_id = ?`,
      [userId]
    );

    return res.status(200).json({
      results: results,
      page: page,
      limit: limit,
      total_results: total,
      total_pages: Math.ceil(total / limit)
    });

  } catch (err) {
    console.error('History List API Error:', err.message);
    return res.status(500).json({ message: '서버 오류 발생' });
  }
});
// --- ✨ 추가 끝 ---

module.exports = router; // 이 줄은 파일 맨 끝에 있어야 합니다.