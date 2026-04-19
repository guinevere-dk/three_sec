# 원세컨 브이로그 (One Second Vlog)

1초 순간으로 만드는 영상 앨범 앱, **원세컨 브이로그** 프로젝트입니다.

## 브랜드 표기 가이드 (Phase 1)

- 국문: `원세컨 브이로그`
- 영문: `One Second Vlog`
- 약칭: `1s Vlog`
- 금지 표기(사용자 노출 문구): `3s`, `Three Sec Vlog`, `3-Second Vlog`, `three_sec_vlog`

## Terminology Update (UI)

- 앱의 하단 네비게이션 탭 명칭을 `Vlog`에서 `Project`로 변경했습니다.
- Project 화면/문구도 동일 용어(`Project`) 기준으로 통일했습니다.
- 데이터 호환성을 위해 저장 경로/DB 키(`vlog_projects`, `vlog_folders` 등)는 기존 네이밍을 유지합니다.

## In-App Purchase Product IDs (Single Source of Truth)

아래 4개 ID를 Play Console / 코드 / 테스트 시나리오에서 동일하게 사용합니다.

- `3s_premium_annual`
- `3s_premium_monthly`
- `3s_standard_annual`
- `3s_standard_monthly`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
