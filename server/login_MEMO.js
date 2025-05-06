const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const validator = require('validator');
const db = require('./db_MEMO');
const router = express.Router();

// POST memo/api/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  try {
    // 필수값 확인 및 유효성 검사
    if (!email || !password || !validator.isEmail(email) || !validator.isLength(password, { min: 6 })) {
      return res.status(400).json({ message: '유효한 이메일과 6자 이상 비밀번호를 입력해주세요.' });
    }

    // 사용자 조회
    const [users] = await db.query('SELECT * FROM users WHERE email = ?', [email]);
    const user = users[0];
    if (!user) {
      return res.status(401).json({ message: '등록되지 않은 사용자입니다.' });
    }

    // 비밀번호 확인
    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: '비밀번호가 일치하지 않습니다.' });
    }

    // JWT 생성
    const token = jwt.sign(
      {
        id: user.id,
        email: user.email,
        role: user.role
      },
      process.env.JWT_SECRET,
      {
        expiresIn: process.env.JWT_EXPIRES_IN || '1h'
      }
    );

    return res.status(200).json({ token });
  } catch (err) {
    console.error('로그인 오류:', err.message, err.stack);
    return res.status(500).json({ message: '서버 오류가 발생했습니다.' });
  }
});

module.exports = router;