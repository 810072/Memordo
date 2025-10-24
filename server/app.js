const express = require('express');
const cors = require('cors');
require('dotenv').config();

// 라우트 파일 임포트
const authRoutes_DG = require('./auth_DG'); 
const emailAuthRouter_DG = require('./email_auth_DG');
const authRoutes_MEMO = require('./auth_MEMO'); 
const emailAuthRouter_MEMO = require('./email_auth_MEMO');
const historyRoutes_MEMO = require('./history_MEMO'); // 새 라우트 파일 임포트
const app = express();

// --- CORS 설정 ---
// Chrome 확장 프로그램을 포함한 모든 출처(Origin)의 요청을 허용합니다.
// 이것이 Flutter에서는 동작하고 확장 프로그램에서는 실패했던 문제를 해결합니다.
app.use(cors({
  origin: '*', // 모든 출처 허용
  methods: ['GET', 'POST', 'PUT', 'DELETE'], // 허용할 HTTP 메소드
  allowedHeaders: ['Content-Type', 'Authorization'], // 허용할 헤더
}));

// Body-parser 미들웨어 설정 (JSON 요청 본문을 파싱하기 위해 필수)
app.use(express.json());

// --- API 라우트 설정 ---
// 각 서비스별로 API 경로를 명확하게 분리합니다.
app.use('/api', authRoutes_DG);
app.use('/api/m/', emailAuthRouter_DG);

app.use('/memo/api', authRoutes_MEMO);
app.use('/memo/api/m/', emailAuthRouter_MEMO);
app.use('/memo/api', historyRoutes_MEMO); // 방문 기록 라우트 추가

// 서버 상태 확인을 위한 기본 GET 엔드포인트
app.get('/', (req, res) => {
    res.json({ message: 'Memordo 서버가 정상적으로 실행 중입니다.' });
});


// 서버 실행
const PORT = process.env.PORT || 3000;
const SERVER_URL = process.env.SERVER_URL || 'http://localhost';
app.listen(PORT, () => {
  console.log(`Server running on ${SERVER_URL}:${PORT}`);
});
