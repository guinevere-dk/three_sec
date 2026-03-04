class ErrorCopy {
  static String syncFailureWithAction(String? rawError) {
    final normalized = (rawError ?? '').toLowerCase();

    if (normalized.contains('cloud firestore api has not been used') ||
        normalized.contains('firestore.googleapis.com') ||
        normalized.contains('api is disabled')) {
      return '클라우드 설정 문제로 업로드에 실패했어요. Firebase 콘솔에서 Firestore API 활성화 상태를 확인한 뒤 다시 시도해주세요.';
    }

    if (normalized.contains('network') || normalized.contains('timeout')) {
      return '네트워크가 불안정해 업로드에 실패했어요. WiFi 연결 후 재시도해주세요.';
    }

    if (normalized.contains('permission') || normalized.contains('unauthorized')) {
      return '권한 문제로 업로드에 실패했어요. 로그인 상태를 확인한 뒤 다시 시도해주세요.';
    }

    if (normalized.contains('quota') || normalized.contains('storage')) {
      return '저장 공간 제한으로 업로드에 실패했어요. 용량을 정리하거나 플랜을 업그레이드해주세요.';
    }

    return '업로드에 실패했어요. 네트워크를 확인하고 다시 시도해주세요.';
  }
}

