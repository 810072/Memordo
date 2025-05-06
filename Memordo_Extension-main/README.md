#  Memordo Chrome Extension

Chrome 확장 프로그램에서 Google Drive API를 연동하여 사용하는 방법입니다.

---

##  확장 프로그램 설치 방법

1. Chrome 확장 프로그램 페이지 chrome://extensions/ 로 이동  
2. 우측 상단의 **개발자 모드**를 켜기  
3. **압축해제된 확장 프로그램을 로드** 클릭  
4. `Memordo_Extension` 폴더 업로드  
5. 확장 프로그램 ID 복사해두기
   
![image](https://github.com/user-attachments/assets/73f7c099-4696-4b7a-8d02-71f1e85e1cf5)

---

##  Google Cloud Console 설정

### 1. 프로젝트 생성

- [Google Cloud Console](https://console.cloud.google.com) 접속  
- 상단 메뉴에서 **새 프로젝트 생성**

### 2. Google Drive API 활성화

- 좌측 메뉴 → **API 및 서비스 > 라이브러리**
- `Google Drive API` 검색 후 **활성화**

### 3. OAuth 동의 화면 구성

- **API 및 서비스 > OAuth 동의 화면**  
- 사용자 유형: **외부**
- 앱 이름, 이메일 등 필수 정보 입력  
- **저장 후 계속**

### 4. OAuth 클라이언트 ID 생성

- **클라이언트 > 클라이언트 ID 만들기** 
- 애플리케이션 유형: **Chrome 확장 프로그램**
- 항목 ID : **복사해둔 확장프로그램ID 입력**
  
![image](https://github.com/user-attachments/assets/5105ea46-4966-4109-87de-6e20cefed6d1)

### 5. 생성된 클라이언트 ID 확인

- 생성 완료 후 아래와 같이 클라이언트 ID가 표시됨  
- `manifest.json` 파일에 Client_id에 값을 입력
