# Memordo

Memordo는 사용자의 메모와 웹 브라우징 기록을 활용하여 개인화된 AI 기반 지식 관리 및 학습을 돕는 서비스입니다.

## 주요 기능

- **AI 기반 RAG (Retrieval-Augmented Generation)**: 사용자가 작성한 메모를 기반으로 AI가 필요한 정보를 찾아주고 생성해줍니다.
- **자동 메모 생성**: Chrome 브라우저 확장 프로그램이 사용자의 방문 기록을 분석하여 연관된 정보를 자동으로 메모로 정리해줍니다.
- **Google Drive 연동**: Google Drive에 저장된 문서와 파일을 손쉽게 가져와 Memordo의 지식 베이스로 활용할 수 있습니다.

## 작동 방식

1.  Flutter로 만들어진 모바일 앱에서 Google 계정으로 로그인합니다.
2.  PC의 Chrome 브라우저에 Memordo 확장 프로그램을 설치하고 로그인합니다.
3.  확장 프로그램이 사용자의 웹 브라우징 기록을 수집하여 서버로 전송합니다.
4.  서버에서는 수집된 데이터와 사용자의 메모, Google Drive 문서를 AI가 학습하여 개인화된 정보를 제공합니다.

## 기술 스택

- **Frontend**: Flutter
- **Browser Extension**: JavaScript (Chrome Extension)
- **Backend Server**: Node.js
- **AI Server**: Python, Gemini AI
- **Database**: Redis, SQL

## 프로젝트 구조

- **/Frontend**: Flutter 기반의 크로스플랫폼 모바일 앱 코드
- **/Memordo_Extension-main**: Chrome 브라우저 확장 프로그램 코드
- **/server**: 사용자 인증, 데이터 처리 등을 담당하는 Node.js 백엔드 서버
- **/py**: Gemini AI 모델을 활용하여 RAG 등 AI 기능을 처리하는 Python 서버
