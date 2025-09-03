const express = require('express');
const bcrypt = require('bcryptjs');
const validator = require('validator');
const db = require('./db_MEMO');
const jwt = require('jsonwebtoken');
const Redis = require('ioredis');
const { OAuth2Client } = require('google-auth-library');
const axios = require('axios');
const redis = new Redis();
const router = express.Router();

const client = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

// ✅ 회원가입
router.post('/signup', async (req, res) => {
  const { email, password } = req.body;
  console.log("post-signup 호출");

  try {
    if (!email || !password || !validator.isEmail(email) || !validator.isLength(password, { min: 6 })) {
      return res.status(400).json({ message: '유효한 이메일과 6자 이상 비밀번호를 입력해주세요.' });
    }

    const verified = await redis.get(`verify:${email}`);
    if (verified !== 'verified') {
      return res.status(403).json({ message: '이메일 인증을 먼저 완료해주세요.' });
    }

    const [existing] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
    if (existing.length > 0) {
      return res.status(409).json({ message: '이미 등록된 이메일입니다.' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    await db.query('INSERT INTO users (email, password, provider) VALUES (?, ?, ?)', [email, hashedPassword, 'email']);
    await redis.del(`verify:${email}`);

    return res.status(201).json({ message: '회원가입이 완료되었습니다.' });
  } catch (err) {
    console.error('회원가입 오류:', err.message);
    return res.status(500).json({ message: '서버 오류가 발생했습니다.' });
  }
});

// ✅ 이메일 로그인
router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  try {
    if (!email || !password || !validator.isEmail(email) || !validator.isLength(password, { min: 6 })) {
      return res.status(400).json({ message: '유효한 이메일과 6자 이상 비밀번호를 입력해주세요.' });
    }

    const [users] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
    const user = users[0];
    if (!user) {
      return res.status(401).json({ message: '등록되지 않은 사용자입니다.' });
    }

    if (user.provider !== 'email') {
      return res.status(403).json({ message: '이메일/비밀번호 로그인은 이 계정에 사용할 수 없습니다.' });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: '비밀번호가 일치하지 않습니다.' });
    }

    const accessToken = jwt.sign(
      {
      id: user.id,
      email: user.email,
      role: user.role || 'user',
      // DB 대신 환경변수에서 공통 API 키를 가져옵니다.
      geminiApiKey: process.env.GEMINI_API_KEY // 👈 이 부분만 수정!
    },
      process.env.JWT_SECRET,
      { expiresIn: '15m' }
    );

    const refreshToken = jwt.sign(
      { id: user.id },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    await db.query('UPDATE users SET refresh_token = ? WHERE id = ?', [refreshToken, user.id]);
    await db.query('INSERT INTO login_logs (user_id, email, login_time, ip_address) VALUES (?, ?, ?, ?)', [
      user.id,
      user.email,
      new Date(),
      req.ip
    ]);

    return res.status(200).json({ accessToken, refreshToken });
  } catch (err) {
    console.error('로그인 오류:', err.message);
    return res.status(500).json({ message: '서버 오류가 발생했습니다.' });
  }
});

// ✅ OAuth2 Google 로그인 (code 기반 + Drive 토큰 저장 포함)
router.post('/google-login', async (req, res) => {
  const { code } = req.body;
  if (!code) return res.status(400).json({ message: 'Google 인증 코드(code)가 필요합니다.' });
  console.log('🔐 받은 Google 인증 코드:', code);

  try {
    console.log('📡 Google 토큰 요청 시작');
    const tokenRes = await axios.post('https://oauth2.googleapis.com/token', null, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      params: {
        code,
        client_id: process.env.GOOGLE_CLIENT_ID,
        client_secret: process.env.GOOGLE_CLIENT_SECRET,
        redirect_uri: process.env.REDIRECT_URI,
        grant_type: 'authorization_code',
      },
    });
    console.log('✅ Google 토큰 응답:', tokenRes.data);

    const idToken = tokenRes.data.id_token;
    const accessTokenFromGoogle = tokenRes.data.access_token;
    const refreshTokenFromGoogle = tokenRes.data.refresh_token;
    const expiresIn = tokenRes.data.expires_in;
    const expiryDate = new Date(Date.now() + expiresIn * 1000);

    const ticket = await client.verifyIdToken({
      idToken,
      audience: process.env.GOOGLE_CLIENT_ID,
    });

    const payload = ticket.getPayload();
    const email = payload.email;
    const name = payload.name;
    const picture = payload.picture;
    const googleId = payload.sub;

    const [users] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
    let user = users[0];

    if (user && user.provider !== 'google') {
      return res.status(409).json({ message: '이미 이메일 로그인으로 가입된 계정입니다.' });
    }

    if (!user) {
      const [result] = await db.query(
        `INSERT INTO users (email, provider, google_id, name, picture, role, is_verified, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`,
        [email, 'google', googleId, name, picture, 'user', 1]
      );
      user = { id: result.insertId, email, role: 'user' };
    }

await db.query(`
  UPDATE users SET 
    google_access_token = ?, 
    google_refresh_token = ?, 
    google_token_expiry = ?, 
    last_login = NOW()
  WHERE id = ?`,
  [accessTokenFromGoogle, refreshTokenFromGoogle, expiryDate, user.id]
);
    const jwtAccessToken = jwt.sign(
    {
      id: user.id,
      email: user.email,
      role: user.role || 'user',
      // DB 대신 환경변수에서 공통 API 키를 가져옵니다.
      geminiApiKey: process.env.GEMINI_API_KEY // 👈 이 부분만 수정!
    },
    process.env.JWT_SECRET,
    { expiresIn: '15m' }
    );

    const jwtRefreshToken = jwt.sign(
      { id: user.id },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    await db.query('UPDATE users SET refresh_token = ? WHERE id = ?', [jwtRefreshToken, user.id]);

    return res.status(200).json({
      accessToken: jwtAccessToken,
      refreshToken: jwtRefreshToken,
      googleAccessToken: accessTokenFromGoogle
    });
  } catch (err) {
    console.error('[OAuth2 Google Login Error]', err.message);
    if (err.response) {
      console.error('🔴 Google 응답 오류 코드:', err.response.status);
      console.error('🔴 Google 응답 내용:', err.response.data);
    }
    return res.status(500).json({ message: 'Google 로그인 처리 중 오류가 발생했습니다.' });
  }
});


router.get('/google-access-token', verifyToken, async (req, res) => {
 consloe.log(`${req.users}`);

	try {
    const [users] = await db.query('SELECT google_access_token FROM users WHERE id = ?', [req.user.id]);
    const user = users[0];

    if (!user || !user.google_access_token) {
      return res.status(404).json({ message: 'Google access token이 없습니다.' });
    }

    return res.status(200).json({ googleAccessToken: user.google_access_token });
  } catch (err) {
    console.error('Google access token 조회 오류:', err.message);
    return res.status(500).json({ message: '서버 오류' });
  }
});


function verifyToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  if (!token) return res.status(401).json({ message: '토큰이 필요합니다.' });

  jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
    if (err) return res.status(403).json({ message: '유효하지 않은 토큰입니다.' });
    req.user = user;
    next();
  });
}



// ✅ 모든 토큰 상태 조회
router.get('/token/status', verifyToken, async (req, res) => {
  try {
    const [users] = await db.query(
      `SELECT refresh_token, google_access_token, google_refresh_token, google_token_expiry 
       FROM users WHERE id = ?`,
      [req.user.id]
    );
    const user = users[0];

    if (!user) {
      return res.status(404).json({ message: '사용자를 찾을 수 없습니다.' });
    }

    const accessTokenValid = true; // verifyToken을 통과했기 때문에 유효
    let refreshTokenValid = false;
    let googleAccessTokenValid = false;
    let googleRefreshTokenValid = false;

    // ✅ Refresh Token 유효성 검사
    if (user.refresh_token) {
      try {
        const decoded = jwt.verify(user.refresh_token, process.env.JWT_SECRET);
        refreshTokenValid = decoded?.id === req.user.id;
      } catch (_) {
        refreshTokenValid = false;
      }
    }

    // ✅ Google Access Token 만료 여부 검사
    if (user.google_access_token && user.google_token_expiry) {
      const expiryTime = new Date(user.google_token_expiry);
      googleAccessTokenValid = expiryTime > new Date();
    }

    // ✅ Google Refresh Token 존재 여부
    googleRefreshTokenValid = !!user.google_refresh_token;

    return res.status(200).json({
      accessTokenValid,
      refreshTokenValid,
      googleAccessTokenValid,
      googleRefreshTokenValid
    });
  } catch (err) {
    console.error('토큰 상태 확인 오류:', err.message);
    return res.status(500).json({ message: '서버 오류가 발생했습니다.' });
  }
});



module.exports = router;