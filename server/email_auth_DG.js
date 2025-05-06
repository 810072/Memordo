// email_auth.js

const express = require('express');
const Redis = require('ioredis');
const nodemailer = require('nodemailer');

const router = express.Router();
const redis = new Redis();

//메일 전송 및 설정
const { sendVerificationEmail_dg } = require('./mailer_DG');


// Redis 연결 확인용 디버깅 코드
redis.on('connect', () => {
  console.log('[Redis] 연결 성공!');
});

redis.on('error', (err) => {
  console.error('[Redis] 연결 에러:', err);
});	


// POST /api/send-verification
router.post('/send-verification', async (req, res) => {
  const { email } = req.body;
  console.log(`[send-verification] 요청 수신: email=${email}`);

  if (!email) {
    return res.status(400).json({ message: '이메일을 입력해주세요.' });
  }

  const code = Math.floor(100000 + Math.random() * 900000).toString(); // 6자리 코드 생성
  console.log(`[send-verification] 생성된 인증 코드: ${code}`);

  try {
	try {
  		await redis.setex(`verify:${email}`, 300, code);
  		console.log(`[send-verification] 인증 코드 저장 완료: verify:${email}`);
		await sendVerificationEmail_dg(email, code); 
	}catch (err) {
  		console.error(`[send-verification] Redis 저장 실패:`, err);
	}
    return res.status(200).json({ message: '인증 메일 발송 완료' });
  } catch (error) {
    console.error('[send-verification] 메일 발송 실패:', error);
    return res.status(500).json({ message: '메일 발송 중 오류 발생' });
  }
});


// POST /api/verify-code
router.post('/verify-code', async (req, res) => {
  const { email, code } = req.body;
  console.log(`[verify-code] 요청 수신: email=${email}, code=${code}`);

  if (!email || !code) {
    return res.status(400).json({ message: '이메일과 인증 코드를 입력해주세요.' });
  }

  try {
    const storedCode = await redis.get(`verify:${email}`);
    console.log(`[verify-code] Redis에 저장된 코드: ${storedCode}`);

    if (!storedCode) {
      return res.status(400).json({ message: '인증 코드가 만료되었거나 존재하지 않습니다.' });
    }

    if (storedCode !== code) {
      console.log(`[verify-code] 인증 실패: 입력한 코드(${code})가 저장된 코드(${storedCode})와 다름`);
      return res.status(400).json({ message: '인증 코드가 일치하지 않습니다.' });
    }

    await redis.del(`verify:${email}`);
    console.log(`[verify-code] 인증 성공 및 코드 삭제: verify:${email}`);
    await redis.set(`verify:${email}`, 'verified', 'EX', 600); // 인증 완료 표시 (10분 유효)
    
    return res.status(200).json({ message: '인증이 완료되었습니다!' });
  } catch (error) {
    console.error('[verify-code] 인증 과정 오류:', error);
    return res.status(500).json({ message: '서버 오류로 인증 실패' });
  }
});

module.exports = router;
