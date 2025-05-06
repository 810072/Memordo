// mailer_DG
const nodemailer = require('nodemailer');
require('dotenv').config(); // 반드시 env 읽기

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT),
  secure: process.env.SMTP_SECURE === 'true', // 문자열이라서 비교 필요
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
  tls: {
    rejectUnauthorized: false,
  },
});

async function sendVerificationEmail_dg(to, code) {
  console.log(`코드 : ${code}`);
  const mailOptions = {
    from: `"AI Doctor Green" <no-reply@aidoctorgreen.com>`,
    to,
    subject: '이메일 인증 코드',
    text: `인증 코드: ${code}`,
    html: `<h1>인증 코드: ${code}</h1>`,
  };

  return transporter.sendMail(mailOptions);
}

module.exports = { sendVerificationEmail_dg };