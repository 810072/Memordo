const express = require('express');
const bcrypt = require('bcryptjs');
const validator = require('validator');
const db = require('./db_MEMO');
const jwt = require('jsonwebtoken');
const Redis = require('ioredis');
const redis = new Redis();
const router = express.Router();

// POST /memo/api/signup
router.post('/signup', async (req, res) => {
  const { email, password } = req.body;
  console.log("post-signup 호출");
  try {
    if (!email || !password || !validator.isEmail(email) || !validator.isLength(password, { min: 6 })) {
      return res.status(400).json({ message: '유효한 이메일과 6자 이상 비밀번호를 입력해주세요.' });
    }

    // ✅ 이메일 인증 여부 확인
    const verified = await redis.get(`verify:${email}`);
    if (verified !== 'verified') {
      return res.status(403).json({ message: '이메일 인증을 먼저 완료해주세요.' });
    }

    const [existing] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
    if (existing.length > 0) {
      return res.status(409).json({ message: '이미 등록된 이메일입니다.' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    await db.query('INSERT INTO users (email, password) VALUES (?, ?)', [email, hashedPassword]);

    // ✅ 인증 상태 삭제 (선택)
    await redis.del(`verify:${email}`);

    return res.status(201).json({ message: '회원가입이 완료되었습니다.' });
  } catch (err) {
    console.error('회원가입 오류:', err.message, err.stack);
    return res.status(500).json({ message: '서버 오류가 발생했습니다.' });
  }
});


// POST /memo/api/login
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

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: '비밀번호가 일치하지 않습니다.' });
    }

    const accessToken = jwt.sign(
      { id: user.id, email: user.email, role: user.role || 'user' },
      process.env.JWT_SECRET,
      { expiresIn: '15m' }
    );

    const refreshToken = jwt.sign(
      { id: user.id },
      process.env.JWT_SECRET,
      { expiresIn: '7d' }
    );

    await db.query('UPDATE users SET refresh_token = ? WHERE id = ?', [refreshToken, user.id]);

    const now = new Date();
    await db.query('INSERT INTO login_logs (user_id, email, login_time, ip_address) VALUES (?, ?, ?, ?)', [
      user.id,
      user.email,
      now,
      req.ip
    ]);

    return res.status(200).json({ accessToken, refreshToken });
  } catch (err) {
    console.error('로그인 오류:', err.message, err.stack);
    return res.status(500).json({ message: '서버 오류가 발생했습니다.' });
  }
});

// POST /memo/api/refresh
router.post('/refresh', async (req, res) => {
  const { refreshToken } = req.body;

  if (!refreshToken) return res.status(401).json({ message: 'Refresh Token이 필요합니다.' });

  try {
    const decoded = jwt.verify(refreshToken, process.env.JWT_SECRET);
    const [users] = await db.query('SELECT * FROM users WHERE id = ?', [decoded.id]);
    const user = users[0];

    if (!user || user.refresh_token !== refreshToken) {
      return res.status(403).json({ message: '유효하지 않은 Refresh Token입니다.' });
    }

    const newAccessToken = jwt.sign(
      { id: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '15m' }
    );

    return res.status(200).json({ accessToken: newAccessToken });
  } catch (err) {
    return res.status(403).json({ message: '토큰이 만료되었거나 유효하지 않습니다.' });
  }
});

//토큰 확인
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

// POST /memo/api/profile
router.get('/profile', verifyToken, async (req, res) => {
  try {
    const [users] = await db.query('SELECT id, email, role, created_at FROM users WHERE id = ?', [req.user.id]);
    const user = users[0];
    if (!user) return res.status(404).json({ message: '사용자를 찾을 수 없습니다.' });
    return res.status(200).json(user);
  } catch (err) {
    console.error('프로필 조회 오류:', err.message, err.stack);
    return res.status(500).json({ message: '서버 오류가 발생했습니다.' });
  }
});

// POST /memo/api/logout
router.post('/logout', verifyToken, async (req, res) => {
  try {
    await db.query('UPDATE users SET refresh_token = NULL WHERE id = ?', [req.user.id]);
    return res.status(200).json({ message: '로그아웃 되었습니다.' });
  } catch (err) {
    console.error('로그아웃 오류:', err.message, err.stack);
    return res.status(500).json({ message: '서버 오류가 발생했습니다.' });
  }
});


// POST /memo/api/check-email
router.post('/check-email', async (req, res) => {
  const { email } = req.body;

  if (!email) {
    return res.status(400).json({ message: '이메일을 입력하세요.' });
  }

  try {
    const [rows] = await db.query('SELECT id FROM users WHERE email = ?', [email]);

    if (rows.length > 0) {
      return res.json({ isDuplicate: true });
    } else {
      return res.json({ isDuplicate: false });
    }
  } catch (err) {
    console.error('이메일 중복 확인 오류:', err.message);
    return res.status(500).json({ message: '서버 오류' });
  }
});



// POST /memo/api/reset-password
router.post('/reset-password', async (req, res) => {
  const { email, newPassword } = req.body;
  console.log(`🔐 Reset Password 요청: email=${email}, newPassword=${newPassword}`);

  try {
    if (!email || !newPassword || !validator.isEmail(email) || !validator.isLength(newPassword, { min: 6 })) {
      return res.status(400).json({ message: '유효한 이메일과 6자 이상 새 비밀번호를 입력해주세요.' });
    }

    // Redis에서 이메일 인증 여부 확인
    const verified = await redis.get(`verify:${email}`);
    if (verified !== 'verified') {
      return res.status(403).json({ message: '이메일 인증이 필요합니다.' });
    }

    const [users] = await db.query('SELECT id FROM users WHERE email = ?', [email]);
    const user = users[0];
    if (!user) {
      return res.status(404).json({ message: '등록되지 않은 이메일입니다.' });
    }

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await db.query('UPDATE users SET password = ?, refresh_token = NULL WHERE email = ?', [hashedPassword, email]);

    // 인증 키 삭제: 재사용 방지
    await redis.del(`verify:${email}`);

    return res.status(200).json({ message: '비밀번호가 성공적으로 변경되었습니다. 다시 로그인해주세요.' });
  } catch (err) {
    console.error('비밀번호 재설정 오류:', err.message, err.stack);
    return res.status(500).json({ message: '서버 오류가 발생했습니다.' });
  }
});

module.exports = router;
