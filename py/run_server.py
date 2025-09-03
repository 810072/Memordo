from waitress import serve
from app import app # app.py에서 Flask app 객체를 가져옵니다.

# host='0.0.0.0'은 모든 IP에서의 접속을 허용합니다.
# port=5001은 app.py와 동일하게 설정합니다.
serve(app, host='0.0.0.0', port=5001)