# 실제 번역 서버

클라이언트 → HTTPS 중계 서버 → DeepL 순서로 동작합니다. DeepL API 키는 서버 환경변수에만 둡니다. 개발 의존성 없이 Node 22 이상에서 실행됩니다.

## 개인 개발/파일럿 실행

1. `.env.example`을 `.env`로 복사합니다. `.env`는 Git에서 제외됩니다.
2. `DEEPL_API_KEY`에 본인의 DeepL API 키를 넣습니다.
3. 계약에 따라 `DEEPL_PLAN=free` 또는 `pro`를 설정합니다.
4. 암호학적으로 안전한 32자 이상의 무작위 토큰을 생성하여 `CLIENT_TOKEN`에 넣습니다. 제공자 API 키와는 별개의 값입니다.
5. `RATE_PER_MINUTE`(기본 60), `DAILY_REQUEST_LIMIT`(기본 1000), `PORT`(기본 8787)를 설정합니다.
6. `Server` 디렉터리에서 실행합니다.

```sh
node --env-file=.env server.mjs
```

서버는 `127.0.0.1`에만 바인딩합니다. iPhone에서 접근하려면 운영자가 **유효한 인증서의 HTTPS 리버스 프록시**를 구성해야 합니다. 앱의 ATS 예외나 HTTP 허용을 추가하지 않습니다. 리버스 프록시에서 요청/응답 본문과 Authorization 헤더 로깅을 비활성화하고, 요청 크기·동시 연결·시간 제한을 적용합니다. 서버 배포는 이 저장소 작성만으로 수행되지 않습니다.

메인 앱 설정에서 네트워크 서비스를 선택하고:

- 엔드포인트: `https://YOUR_HOST/v1/translate`
- 접근 토큰: 서버의 `CLIENT_TOKEN`과 동일한 개인 토큰
- 전송 동의: ON
- iOS 키보드 설정의 전체 접근 허용: ON

토큰은 Keychain에 저장되며 앱 패키지에는 포함하지 않습니다. 앱 설정에서 삭제할 수 있습니다. 엔드포인트 변경 시 전송 동의가 해제됩니다.

## HTTP 계약

`POST /v1/translate`, `Content-Type: application/json`, `Authorization: Bearer <개인 토큰>`

```json
{"text":"안녕하세요","sourceLanguage":null,"targetLanguage":"ja"}
```

`sourceLanguage`는 생략 또는 null이면 자동 감지입니다. 지원 언어 코드는 `ko`, `en`, `ja`, `zh`입니다.

```json
{"translatedText":"こんにちは","detectedSourceLanguage":"ko","provider":"DeepL"}
```

오류는 본문을 포함하지 않는 고정 코드로 반환합니다. 400 입력 오류, 401 인증 실패, 415 콘텐츠 타입, 429 제한/제공자 할당량, 502 제공자 실패, 504 타임아웃을 구분합니다. 응답은 `Cache-Control: no-store`입니다. `GET /health`는 단순 상태만 반환합니다.

## 데이터 처리와 운영 범위

- 입력·결과·인증 토큰을 로그나 파일/DB에 기록하지 않습니다.
- 요청과 응답은 처리 중 메모리에 존재합니다. JavaScript/Swift 관리형 메모리의 물리적 즉시 덮어쓰기까지 보장하지 않습니다.
- 최대 500 grapheme / 2000 Unicode scalar / 16KB 본문, 64KB 제공자 응답, 최대 8개 동시 번역을 제한합니다.
- 제한 카운터는 메모리이며 서버 재시작 시 초기화됩니다. 텍스트 캐시는 없습니다.
- 7초 뒤 제공자 요청을 중단합니다. 앱 연결 종료도 제공자 취소로 전달합니다.
- 제공자 URL은 코드에서 DeepL 공식 Free/Pro 호스트로 제한합니다. 리디렉션을 따르지 않습니다.
- 앱의 개인 서버 연결도 리디렉션을 거부하여 토큰/본문 전달을 막습니다.

**현재 인증은 한 명의 개인 사용자/파일럿을 위한 토큰 방식입니다.** 공개 App Store 서비스 운영 전에는 사용자별 토큰 발급·회수·만료, 계정별 분산 제한, 제공자 예산 상한, 악용 방지 및 비텍스트 운영 모니터링이 추가로 필요합니다. 같은 토큰을 앱에 하드코딩하거나 여러 사용자에게 배포하면 안 됩니다.

DeepL 및 호스팅 제공자의 실제 보관·국외 이전·계약 조건은 계정 플랜에 맞춰 별도 검토해야 합니다. 자체 서버가 기록하지 않는다는 사실만으로 제공자도 보관하지 않는다고 주장하면 안 됩니다. 개인정보 매니페스트와 App Store 개인정보 응답은 실제 운영 정책에 맞춰 재검토합니다.

## 제공자 교체

`deepLTranslate`와 같은 `(body, signal) → {translatedText, detectedSourceLanguage, provider}` 어댑터를 구현하고 `createRelay`의 `translate`에 주입하면 됩니다. 인증·요청 제한·취소·입력 검증은 공통 서버 계층에 유지합니다. 클라이언트의 `TranslationService`는 변경할 필요가 없습니다.

참고: [DeepL 공식 Node SDK 및 API 사용법](https://github.com/DeepL/deepl-node).
