const express = require('express');
const cors = require('cors');

const authRoutes_DG = require('./auth_DG'); 
const emailAuthRouter_DG = require('./email_auth_DG');

const authRoutes_MEMO = require('./auth_MEMO'); 
const emailAuthRouter_MEMO = require('./email_auth_MEMO');

require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());
// 이렇게 경로 분리
app.use('/api', authRoutes_DG);
app.use('/api/m/', emailAuthRouter_DG);


app.use('/memo/api', authRoutes_MEMO);
app.use('/memo/api/m/', emailAuthRouter_MEMO);


app.get('/get', (req, res) => {
    res.json({ message: 'GET 요청 성공!' });
});


const PORT = process.env.PORT || 3000;
const SERVER_URL = process.env.SERVER_URL;
app.listen(PORT, () => {
  console.log(`Server running on ${SERVER_URL}:${PORT}`);
});


// ... --- ...