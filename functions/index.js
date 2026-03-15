const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');

admin.initializeApp();

const REGION = 'asia-northeast3';
const FUNCTION_NAME = 'social';
const EXCHANGE_PATH = '/exchange';
const FUNCTION_SERVICE_ACCOUNT = 'fir-3s-8edb9@appspot.gserviceaccount.com';
const MAX_BODY_BYTES = 10 * 1024;
const KAKAO_DEFAULT_PROPERTY_KEYS = [
  'kakao_account.profile.nickname',
  'kakao_account.profile.profile_image_url',
];
const KAKAO_MINIMAL_PROPERTY_KEYS = [
  'kakao_account.profile.nickname',
  'kakao_account.profile.profile_image_url',
];
const KAKAO_USE_PROPERTY_KEYS = parseBooleanEnv('KAKAO_USE_PROPERTY_KEYS', true);
const KAKAO_PROPERTY_KEYS = parseKakaoPropertyKeys(process.env.KAKAO_PROPERTY_KEYS);
const KAKAO_EFFECTIVE_PROPERTY_KEYS =
  KAKAO_USE_PROPERTY_KEYS && KAKAO_PROPERTY_KEYS.length > 0
    ? KAKAO_PROPERTY_KEYS
    : KAKAO_USE_PROPERTY_KEYS
    ? KAKAO_MINIMAL_PROPERTY_KEYS
    : [];
console.log('[social/exchange] Kakao property-key config', {
  usePropertyKeys: KAKAO_USE_PROPERTY_KEYS,
  propertyKeyCount: KAKAO_EFFECTIVE_PROPERTY_KEYS.length,
  propertyKeys: KAKAO_EFFECTIVE_PROPERTY_KEYS,
  fallbackPropertyKeys: KAKAO_EFFECTIVE_PROPERTY_KEYS,
});

function parseBooleanEnv(name, defaultValue) {
  const raw = process.env[name];
  if (raw === undefined || raw === null) {
    return defaultValue;
  }

  if (['1', 'true', 'yes', 'y', 'on'].includes(String(raw).trim().toLowerCase())) {
    return true;
  }

  if (['0', 'false', 'no', 'off', 'disabled', 'off'].includes(String(raw).trim().toLowerCase())) {
    return false;
  }

  return defaultValue;
}

function parseKakaoPropertyKeys(raw) {
  if (!raw || String(raw).trim().length === 0) {
    return KAKAO_DEFAULT_PROPERTY_KEYS;
  }

  const normalized = String(raw).trim();

  try {
    const parsed = JSON.parse(normalized);
    if (Array.isArray(parsed)) {
      const items = parsed
        .map((item) => String(item || '').trim())
        .filter((item) => item.length > 0);
      return Array.from(new Set(items));
    }
  } catch (error) {
    // JSON parse 실패는 쉼표 구분 문자열로 fallback
  }

  const fallback = normalized
    .split(',')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);

  const deduped = Array.from(new Set(fallback));
  return deduped.length > 0 ? deduped : KAKAO_DEFAULT_PROPERTY_KEYS;
}

function parseRequestId(req) {
  const direct = req.get ? req.get('x-request-id') : undefined;
  const header = direct || req.headers?.['x-request-id'] || req.headers?.['x_request_id'];
  if (typeof header === 'string' && header.trim().length > 0) {
    return header.trim();
  }

  const cloudTrace = req.get
    ? req.get('x-cloud-trace-context')
    : req.headers?.['x-cloud-trace-context'];

  if (typeof cloudTrace === 'string' && cloudTrace.includes('/')) {
    const traceId = cloudTrace.split('/')[0].trim();
    if (traceId.length > 0) {
      return `trace-${traceId}`;
    }
  }

  return `req-${Date.now()}-${crypto.randomUUID().slice(0, 8)}`;
}

function truncateText(value, maxLength = 400) {
  if (value === undefined || value === null) {
    return null;
  }

  const text = String(value);
  if (text.length <= maxLength) {
    return text;
  }

  return `${text.slice(0, maxLength)}... (truncated ${text.length - maxLength} chars)`;
}

function safeParseJson(text) {
  try {
    return JSON.parse(String(text || ''));
  } catch (error) {
    return null;
  }
}

function summarizeKakaoResponse(payload, rawText) {
  if (payload && typeof payload === 'object') {
    const code = payload.code || payload.error || payload.error_code;
    const message = payload.msg || payload.message || payload.error_description;
    const keys = Object.keys(payload || {}).slice(0, 20);
    return {
      hasId: Boolean(payload.id),
      keys,
      keyCount: Object.keys(payload || {}).length,
      code: code || null,
      message: typeof message === 'string' ? truncateText(message, 240) : null,
    };
  }

  if (typeof rawText === 'string' && rawText.length > 0) {
    return {
      rawText: truncateText(rawText, 240),
    };
  }

  return null;
}

function summarizeFailurePattern(payload, rawText) {
  const code = payload?.error || payload?.code || payload?.error_code || payload?.error_description || null;
  const message =
    payload?.msg || payload?.message || payload?.error_description || payload?.detail || null;

  const normalizedCode = String(code || '').toLowerCase();
  const normalizedMessage = String(message || '').toLowerCase();
  const normalizedRaw = String(rawText || '').toLowerCase();

  return {
    code: code || null,
    message: typeof message === 'string' ? truncateText(message, 240) : null,
    normalizedCode,
    normalizedMessage,
    normalizedRaw,
  };
}

function isRecoverableMissingPropertyError(payload, rawText, status, withPropertyKeys = true) {
  if (!withPropertyKeys || status !== 400) {
    return false;
  }

  const summary = summarizeFailurePattern(payload, rawText);
  const text = `${summary.normalizedCode} ${summary.normalizedMessage} ${summary.normalizedRaw}`;

  const tokens = [
    'user property not found',
    'property not found',
    'required property',
    'required_property',
    'property key',
    'property not allowed',
    'no permission for property',
    'app does not have permission',
  ];

  return tokens.some((token) => text.includes(token));
}

function appendRequestMeta(details, requestId) {
  if (!details || typeof details !== 'object') {
    return { requestId };
  }

  return {
    ...details,
    requestId,
  };
}

function pickFirstStringWithSource(entries) {
  for (const entry of entries) {
    if (!entry) {
      continue;
    }

    const value = toTrimmedString(entry.value);
    if (value !== null) {
      return { value, source: entry.source || 'unknown' };
    }
  }
  return { value: null, source: 'none' };
}

function hasMeaningfulProfile(data) {
  const kakaoAccount = data?.kakao_account || {};
  const kakaoProfile = kakaoAccount.profile || {};
  const properties = data?.properties || {};

  const nameSource = pickFirstStringWithSource([
    { source: 'kakao_profile.nickname', value: kakaoProfile.nickname },
    { source: 'kakao_profile.name', value: kakaoProfile.name },
    { source: 'properties.nickname', value: properties.nickname },
    { source: 'properties.profile_nickname', value: properties.profile_nickname },
    { source: 'data.profile_nickname', value: data.profile_nickname },
    { source: 'data.nickname', value: data.nickname },
  ]);

  const photoSource = pickFirstStringWithSource([
    { source: 'kakao_profile.profile_image_url', value: kakaoProfile.profile_image_url },
    { source: 'kakao_profile.image_url', value: kakaoProfile.image_url },
    { source: 'properties.profile_image', value: properties.profile_image },
    { source: 'properties.profile_image_url', value: properties.profile_image_url },
    { source: 'properties.thumbnail_image', value: properties.thumbnail_image },
    { source: 'data.profile_image_url', value: data.profile_image_url },
    { source: 'data.thumbnail_image', value: data.thumbnail_image },
  ]);

  return Boolean(nameSource.value || photoSource.value);
}

const DEFAULT_ALLOWED_ORIGINS = ['*'];

function toTrimmedString(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function pickFirstString(values) {
  for (const value of values) {
    const normalized = toTrimmedString(value);
    if (normalized !== null) {
      return normalized;
    }
  }
  return null;
}

function pickFirstBool(values) {
  for (const value of values) {
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'string') {
      const normalized = value.trim().toLowerCase();
      if (['true', '1', 'yes', 'y', 'on'].includes(normalized)) {
        return true;
      }
      if (['false', '0', 'no', 'off', 'disabled'].includes(normalized)) {
        return false;
      }
    }
    if (typeof value === 'number') {
      if (value === 1) return true;
      if (value === 0) return false;
    }
  }

  return null;
}

function getAllowedOrigins() {
  let rawOrigins = process.env.SOCIAL_EXCHANGE_ALLOWED_ORIGINS;

  if (!rawOrigins) {
    try {
      // Firebase CLI config: `functions.config().social_exchange.allowed_origins`
      const config = functions.config();
      rawOrigins = config?.social_exchange?.allowed_origins;
    } catch (error) {
      // config() 미설정 환경에서는 무시
      rawOrigins = undefined;
    }
  }

  if (!rawOrigins) {
    return DEFAULT_ALLOWED_ORIGINS;
  }

  const parsed = rawOrigins
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

  return parsed.length > 0 ? parsed : DEFAULT_ALLOWED_ORIGINS;
}

function isOriginAllowed(origin) {
  const allowed = getAllowedOrigins();
  if (allowed.includes('*')) {
    return true;
  }
  if (!origin) {
    return false;
  }
  return allowed.includes(origin);
}

function setCorsHeaders(req, res) {
  const origin = req.get('Origin');
  if (isOriginAllowed(origin)) {
    res.set('Access-Control-Allow-Origin', origin || '*');
  }

  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-request-id');
  res.set('Access-Control-Max-Age', '3600');
}

function writeError(res, code, status, message, details = null) {
  res.status(status).json({
    success: false,
    error: {
      code,
      message,
      ...(details ? { details } : {}),
      timestamp: new Date().toISOString(),
    },
  });
}

async function readJsonBody(req) {
  if (req.body !== undefined && req.body !== null) {
    if (typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
      return req.body;
    }
    if (Buffer.isBuffer(req.body)) {
      return JSON.parse(req.body.toString('utf8') || '{}');
    }
    if (typeof req.body === 'string') {
      return JSON.parse(req.body || '{}');
    }
  }

  const chunks = [];
  let total = 0;

  for await (const chunk of req) {
    const buffer = Buffer.from(chunk);
    total += buffer.length;
    if (total > MAX_BODY_BYTES) {
      throw new Error('REQUEST_BODY_TOO_LARGE');
    }
    chunks.push(buffer);
  }

  if (chunks.length === 0) {
    return {};
  }

  const bodyText = Buffer.concat(chunks).toString('utf8');
  return JSON.parse(bodyText || '{}');
}

function sanitizeToken(token) {
  return (token || '').trim();
}

function sanitizeOptionalString(value) {
  if (value === undefined || value === null) {
    return '';
  }
  return String(value).trim();
}

function decodeJwtPayloadUnsafe(token) {
  const normalized = sanitizeOptionalString(token);
  if (!normalized) {
    return null;
  }
  const chunks = normalized.split('.');
  if (chunks.length < 2) {
    return null;
  }

  try {
    const payloadRaw = chunks[1].replace(/-/g, '+').replace(/_/g, '/');
    const payloadBuffer = Buffer.from(payloadRaw.padEnd(Math.ceil(payloadRaw.length / 4) * 4, '='), 'base64');
    const decoded = JSON.parse(payloadBuffer.toString('utf8'));
    return decoded && typeof decoded === 'object' ? decoded : null;
  } catch (error) {
    return null;
  }
}

function normalizeAudience(aud) {
  if (typeof aud === 'string' && aud.trim()) {
    return [aud.trim()];
  }
  if (Array.isArray(aud)) {
    return aud.map((value) => sanitizeOptionalString(value)).filter(Boolean);
  }
  return [];
}

function verifyOidcIdTokenClaims(idToken, requestContext = {}) {
  const token = sanitizeOptionalString(idToken);
  if (!token) {
    return { verified: false, reason: 'OIDC_ID_TOKEN_NOT_PROVIDED' };
  }

  const payload = decodeJwtPayloadUnsafe(token);
  if (!payload) {
    const error = new Error('OIDC_ID_TOKEN_INVALID');
    error.code = 'OIDC_ID_TOKEN_INVALID';
    throw error;
  }

  const nowSec = Math.floor(Date.now() / 1000);
  const exp = Number(payload.exp || 0);
  if (exp > 0 && exp <= nowSec) {
    const error = new Error('OIDC_ID_TOKEN_EXPIRED');
    error.code = 'OIDC_ID_TOKEN_EXPIRED';
    throw error;
  }

  const expectedNonce = sanitizeOptionalString(requestContext?.nonce);
  const tokenNonce = sanitizeOptionalString(payload.nonce);
  if (expectedNonce && tokenNonce && expectedNonce !== tokenNonce) {
    const error = new Error('OIDC_NONCE_MISMATCH');
    error.code = 'OIDC_NONCE_MISMATCH';
    throw error;
  }

  const expectedAudience = sanitizeOptionalString(requestContext?.providerAudience)
    || sanitizeOptionalString(requestContext?.clientId);
  const tokenAudiences = normalizeAudience(payload.aud);
  if (expectedAudience && tokenAudiences.length > 0 && !tokenAudiences.includes(expectedAudience)) {
    const error = new Error('OIDC_AUDIENCE_MISMATCH');
    error.code = 'OIDC_AUDIENCE_MISMATCH';
    throw error;
  }

  return {
    verified: true,
    reason: 'OIDC_ID_TOKEN_CLAIMS_VERIFIED',
    payload,
    issuer: sanitizeOptionalString(payload.iss) || null,
    subject: sanitizeOptionalString(payload.sub) || null,
    audience: tokenAudiences,
    hasNonce: Boolean(tokenNonce),
  };
}

function createProviderUid(provider, providerUserId) {
  const safeProvider = String(provider || '')
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, '_');
  const safeUserId = String(providerUserId || '')
    .replace(/[^a-zA-Z0-9._-]/g, '_')
    .slice(0, 100);

  const uid = `${safeProvider}_${safeUserId}`;
  if (!uid) {
    throw new Error('INVALID_UID');
  }
  if (uid.length > 128) {
    return uid.slice(0, 128);
  }
  return uid;
}

async function verifyKakao(accessToken, idToken, requestContext = {}) {
  const requestId = requestContext?.requestId || null;

  if (!accessToken) {
    const error = new Error('MISSING_ACCESS_TOKEN');
    error.code = 'MISSING_ACCESS_TOKEN';
    throw error;
  }

  const kakaoUserMeUrl = new URL('https://kapi.kakao.com/v2/user/me');
  const usePropertyKeys = KAKAO_USE_PROPERTY_KEYS && KAKAO_EFFECTIVE_PROPERTY_KEYS.length > 0;
  let usedFallbackUserMe = false;
  const requestAttempts = [];

  const requestProfile = async (withPropertyKeys, attempt) => {
    const requestUrl = new URL(kakaoUserMeUrl.toString());
    const effectivePropertyKeys = withPropertyKeys && usePropertyKeys;
    const propertyKeys = effectivePropertyKeys ? KAKAO_EFFECTIVE_PROPERTY_KEYS : [];

    if (effectivePropertyKeys) {
      requestUrl.searchParams.set('property_keys', JSON.stringify(propertyKeys));
    }

    const requestUrlString = requestUrl.toString();
    const startedAt = Date.now();
    console.log('[social/exchange] kakao user/me request', {
      requestId,
      provider: 'kakao',
      attempt,
      withPropertyKeys: effectivePropertyKeys,
      propertyKeyCount: effectivePropertyKeys ? propertyKeys.length : 0,
      requestUrlLength: requestUrlString.length,
      hasQuery: requestUrl.search.length > 0,
      hasRequestId: Boolean(requestId),
    });

    const response = await fetch(requestUrlString, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: 'application/json',
      },
    });

    const durationMs = Date.now() - startedAt;
    const status = response.status;
    const contentType = response.headers.get('content-type') || null;
    const text = await response.text();
    const parsed = safeParseJson(text);
    const responseSummary = summarizeKakaoResponse(parsed, text);

    requestAttempts.push({
      attempt,
      withPropertyKeys: effectivePropertyKeys,
      propertyKeyCount: effectivePropertyKeys ? propertyKeys.length : 0,
      status,
      ok: response.ok,
      durationMs,
      contentType,
      summary: responseSummary,
    });

    console.log('[social/exchange] kakao user/me response', {
      requestId,
      provider: 'kakao',
      attempt,
      withPropertyKeys: effectivePropertyKeys,
      status,
      contentType,
      durationMs,
      ...(responseSummary || {}),
    });

    if (!response.ok) {
      const isMissingProperty =
        effectivePropertyKeys && isRecoverableMissingPropertyError(parsed, text, status, effectivePropertyKeys);

      const error = new Error(
        isMissingProperty
          ? 'KAKAO_REQUIRED_PROPERTY_NOT_ALLOWED'
          : 'KAKAO_TOKEN_INVALID',
      );
      error.code = isMissingProperty ? 'KAKAO_REQUIRED_PROPERTY_NOT_ALLOWED' : 'KAKAO_TOKEN_INVALID';
      error.httpStatus = status;
      error.requestId = requestId;
      error.withPropertyKeys = effectivePropertyKeys;
      error.attempt = attempt;
      error.kakaoError = responseSummary || null;
      error.kakaoRaw = truncateText(text, 1200);
      error.requestAttempts = requestAttempts.slice();
      throw error;
    }

    if (!parsed || typeof parsed !== 'object') {
      const error = new Error('KAKAO_TOKEN_INVALID');
      error.code = 'KAKAO_TOKEN_INVALID';
      error.httpStatus = status;
      error.requestId = requestId;
      error.withPropertyKeys = effectivePropertyKeys;
      error.attempt = attempt;
      error.kakaoError = {
        code: 'NON_JSON_RESPONSE',
        message: 'Kakao /user/me 응답이 JSON 형식이 아닙니다.',
      };
      error.kakaoRaw = truncateText(text, 1200);
      error.requestAttempts = requestAttempts.slice();
      throw error;
    }

    return parsed;
  };

  let data;
  try {
    data = await requestProfile(true, 1);
  } catch (error) {
    if (error.code === 'KAKAO_REQUIRED_PROPERTY_NOT_ALLOWED') {
      usedFallbackUserMe = true;
      console.warn('[social/exchange] kakao user/me property key missing. fallback 시작', {
        requestId,
        reason: error.code,
        attempt: 1,
        kakaoError: error.kakaoError,
      });

      data = await requestProfile(false, 2);
      console.log('[social/exchange] kakao user/me fallback 완료', {
        requestId,
        attempt: 2,
        usedFallbackUserMe,
      });
    } else {
      error.requestId = requestId;
      throw error;
    }
  }

  if (!usedFallbackUserMe && usePropertyKeys && !hasMeaningfulProfile(data)) {
    try {
      const fallbackData = await requestProfile(false, requestAttempts.length + 1);
      if (hasMeaningfulProfile(fallbackData)) {
        usedFallbackUserMe = true;
        data = fallbackData;
        console.log('[social/exchange] kakao user/me 의미있는 프로필 없어서 fallback 수행', {
          requestId,
          attempt: requestAttempts.length,
          usedFallbackUserMe,
        });
      }
    } catch (error) {
      error.requestId = requestId;
      throw error;
    }
  }

  if (!data?.id) {
    const error = new Error('KAKAO_TOKEN_USER_NOT_FOUND');
    error.code = 'KAKAO_TOKEN_USER_NOT_FOUND';
    error.requestId = requestId;
    throw error;
  }

  let oidcStatus = {
    verified: false,
    reason: 'OIDC_ID_TOKEN_NOT_PROVIDED',
  };
  try {
    oidcStatus = verifyOidcIdTokenClaims(idToken, requestContext);
  } catch (error) {
    error.requestId = requestId;
    error.httpStatus = 401;
    error.requestAttempts = requestAttempts.slice();
    throw error;
  }

  const properties = data.properties || {};
  const kakaoAccount = data.kakao_account || {};
  const kakaoProfile = kakaoAccount.profile || {};

  const { value: displayName, source: resolvedDisplayNameSource } =
    pickFirstStringWithSource([
      { source: 'kakaoAccount.profile.nickname', value: kakaoProfile.nickname },
      { source: 'kakaoAccount.profile.name', value: kakaoProfile.name },
      { source: 'properties.nickname', value: properties.nickname },
      { source: 'properties.profile_nickname', value: properties.profile_nickname },
      { source: 'data.profile_nickname', value: data.profile_nickname },
      { source: 'data.nickname', value: data.nickname },
    ]);

  const { value: resolvedPhotoUrl, source: resolvedPhotoUrlSource } =
    pickFirstStringWithSource([
      { source: 'kakaoAccount.profile.profile_image_url', value: kakaoProfile.profile_image_url },
      { source: 'kakaoAccount.profile.image_url', value: kakaoProfile.image_url },
      {
        source: 'kakaoAccount.profile.thumbnail_image_url',
        value: kakaoProfile.thumbnail_image_url,
      },
      { source: 'properties.profile_image', value: properties.profile_image },
      { source: 'properties.profile_image_url', value: properties.profile_image_url },
      { source: 'properties.thumbnail_image', value: properties.thumbnail_image },
      { source: 'data.profile_image_url', value: data.profile_image_url },
        { source: 'data.profile_image', value: data.profile_image },
        { source: 'data.thumbnail_image', value: data.thumbnail_image },
      ]);

  const { value: resolvedEmail, source: resolvedEmailSource } =
    pickFirstStringWithSource([
      { source: 'kakao_account.email', value: kakaoAccount.email },
      { source: 'data.email', value: data.email },
    ]);

  const profileSource =
    KAKAO_USE_PROPERTY_KEYS && KAKAO_EFFECTIVE_PROPERTY_KEYS.length > 0
      ? (usedFallbackUserMe ? 'kakao_user_me_fallback' : 'kakao_user_me_property_keys')
      : 'kakao_user_me_basic';

  const hasDisplayName = Boolean(resolvedDisplayName);
  const hasPhotoUrl = Boolean(resolvedPhotoUrl);
  const hasEmail = Boolean(resolvedEmail);

  console.log('[social/exchange] kakao verify', {
    requestId,
    requestAttemptCount: requestAttempts.length,
    userMeAttempts: requestAttempts,
    usedFallbackUserMe,
    provider: 'kakao',
    providerUserId: data.id,
    hasKakaoAccount: Boolean(kakaoAccount && Object.keys(kakaoAccount).length > 0),
    hasProperties: Boolean(properties && Object.keys(properties).length > 0),
    kakaoDataKeys: Object.keys(data || {}).slice(0, 30),
    kakaoAccountKeys: Object.keys(kakaoAccount || {}).slice(0, 30),
    propertiesKeys: Object.keys(properties || {}).slice(0, 30),
    kakaoProfileKeys: Object.keys(kakaoProfile || {}).slice(0, 30),
    usedFallbackUserMe,
    extractedDisplayName: displayName,
    profileDisplayNameSource: resolvedDisplayNameSource,
    extractedPhotoUrl: resolvedPhotoUrl,
    photoUrlSource: resolvedPhotoUrlSource,
    extractedEmail: resolvedEmail,
    emailSource: resolvedEmailSource,
    hasPhotoUrl,
    hasDisplayName,
    hasEmail,
    kakaoErrorCount: requestAttempts.filter((it) => !it.ok || it.status >= 400).length,
    profileSource,
    oidcStatus,
  });

  return {
    uid: createProviderUid('kakao', String(data.id)),
    provider: 'kakao',
    providerUserId: String(data.id),
    tokenSource: 'access_token_info',
    displayName,
    email: resolvedEmail,
    photoUrl: resolvedPhotoUrl,
    profileStatus: {
      hasDisplayName,
      hasPhotoUrl,
      hasEmail,
      source: profileSource,
      displayNameSource: resolvedDisplayNameSource,
      photoUrlSource: resolvedPhotoUrlSource,
      emailSource: resolvedEmailSource,
      usedFallbackUserMe,
      requestAttemptCount: requestAttempts.length,
      oidcVerified: Boolean(oidcStatus.verified),
      oidcReason: oidcStatus.reason || null,
    },
    providerInfo: {
      provider: 'kakao',
      providerUserId: String(data.id),
      source: profileSource,
      usedFallbackUserMe,
      requestAttemptCount: requestAttempts.length,
      oidcVerified: Boolean(oidcStatus.verified),
      oidcReason: oidcStatus.reason || null,
    },
    raw: data,
    usedFallbackUserMe,
    requestAttempts,
  };
}

async function verifyNaver(accessToken, idToken, requestContext = {}) {
  const requestId = requestContext?.requestId || null;
  if (!accessToken) {
    const error = new Error('MISSING_ACCESS_TOKEN');
    error.code = 'MISSING_ACCESS_TOKEN';
    throw error;
  }

  const requestAttempts = [];
  const startedAt = Date.now();

  const response = await fetch('https://openapi.naver.com/v1/nid/me', {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: 'application/json',
    },
  });

  const durationMs = Date.now() - startedAt;
  const text = await response.text();
  const data = safeParseJson(text);
  requestAttempts.push({
    attempt: 1,
    status: response.status,
    ok: response.ok,
    durationMs,
    contentType: response.headers.get('content-type') || null,
  });

  if (!data || typeof data !== 'object') {
    const error = new Error('NAVER_TOKEN_INVALID');
    error.code = 'NAVER_TOKEN_INVALID';
    error.httpStatus = response.status;
    error.requestId = requestId;
    error.kakaoError = {
      code: 'NON_JSON_RESPONSE',
      message: 'Naver /v1/nid/me 응답이 JSON 형식이 아닙니다.',
    };
    error.requestAttempts = requestAttempts;
    throw error;
  }

  if (!response.ok || data?.resultcode !== '00') {
    const message =
      (typeof data === 'object' && data) ? `${data.resultcode || response.status}:${data.message || 'Naver token invalid'}` : `HTTP_${response.status}`;
    const error = new Error('NAVER_TOKEN_INVALID');
    error.code = 'NAVER_TOKEN_INVALID';
    error.httpStatus = response.status;
    error.requestId = requestId;
    error.kakaoError = {
      code: data?.code || data?.message_code || null,
      message: `${message}`,
    };
    error.requestAttempts = requestAttempts;
    throw error;
  }

  const naverId = data?.response?.id;
  if (!naverId) {
    const error = new Error('NAVER_TOKEN_USER_NOT_FOUND');
    error.code = 'NAVER_TOKEN_USER_NOT_FOUND';
    error.requestId = requestId;
    error.requestAttempts = requestAttempts;
    throw error;
  }

  const naverResponse = data?.response || {};
  const naverDisplayName =
    pickFirstString([
      naverResponse?.name,
      naverResponse?.nickname,
    ]) || null;
  const naverPhotoUrl =
    pickFirstString([
      naverResponse?.profile_image,
      naverResponse?.thumbnail_image,
      naverResponse?.image,
    ]) || null;
  const naverEmail = pickFirstString([naverResponse?.email, naverResponse?.enc_email]) || null;
  const hasDisplayName = Boolean(naverDisplayName);
  const hasPhotoUrl = Boolean(naverPhotoUrl);
  const hasEmail = Boolean(naverEmail);
  let oidcStatus = {
    verified: false,
    reason: 'OIDC_ID_TOKEN_NOT_PROVIDED',
  };

  try {
    oidcStatus = verifyOidcIdTokenClaims(idToken, requestContext);
  } catch (error) {
    error.requestId = requestId;
    error.httpStatus = 401;
    error.requestAttempts = requestAttempts.slice();
    throw error;
  }

  return {
    uid: createProviderUid('naver', String(naverId)),
    provider: 'naver',
    providerUserId: String(naverId),
    tokenSource: 'nid/me',
    displayName: naverDisplayName,
    photoUrl: naverPhotoUrl,
    email: naverEmail,
    profileStatus: {
      hasDisplayName,
      hasPhotoUrl,
      hasEmail,
      source: 'naver_profile',
      displayNameSource: hasDisplayName ? 'response.name' : 'none',
      photoUrlSource: hasPhotoUrl ? 'response.profile_image' : 'none',
      emailSource: hasEmail ? 'response.email' : 'none',
      usedFallbackUserMe: false,
      requestAttemptCount: requestAttempts.length,
      oidcVerified: Boolean(oidcStatus.verified),
      oidcReason: oidcStatus.reason || null,
    },
    providerInfo: {
      provider: 'naver',
      providerUserId: String(naverId),
      profileSource: 'naver_profile',
      usedFallbackUserMe: false,
      requestAttemptCount: requestAttempts.length,
      oidcVerified: Boolean(oidcStatus.verified),
      oidcReason: oidcStatus.reason || null,
    },
    raw: data.response,
    requestAttempts,
  };
}

async function handleExchange(req, res, requestId) {
  try {
    const requestStartedAt = Date.now();
    console.log('[social/exchange] 요청 시작', {
      requestId,
      method: req.method,
      path: req.path,
      hasAuthorizationHeader: Boolean(req.get('Authorization')),
      hasXRequestId: Boolean(requestId),
      requestSizeBytes: req.get('content-length') || null,
    });

    const path = (req.path || '/').replace(/\/+$/, '') || '/';
    const normalizedPath = path === '' ? '/' : path;
    if (
      normalizedPath !== EXCHANGE_PATH &&
      normalizedPath !== '/'
    ) {
      return writeError(
        res,
        'NOT_FOUND',
        404,
        `지원하지 않는 경로입니다. POST ${EXCHANGE_PATH} 또는 함수 루트 경로만 허용합니다.`,
        appendRequestMeta({ normalizedPath }, requestId),
      );
    }

    if (req.method !== 'POST') {
      return writeError(
        res,
        'METHOD_NOT_ALLOWED',
        405,
        `허용되지 않은 메서드입니다. ${req.method}`,
        appendRequestMeta({ path: req.path }, requestId),
      );
    }

    const payload = await readJsonBody(req);
    if (!payload || typeof payload !== 'object') {
      return writeError(
        res,
        'INVALID_REQUEST',
        400,
        '요청 본문이 유효하지 않습니다.',
        appendRequestMeta({ path: req.path }, requestId),
      );
    }

    const provider = String(payload.provider || '').toLowerCase().trim();
    const accessToken = sanitizeToken(payload.accessToken);
    const idToken = sanitizeToken(payload.idToken);
    const nonce = sanitizeOptionalString(payload.nonce);
    const providerAudience = sanitizeOptionalString(payload.providerAudience);
    const clientId = sanitizeOptionalString(payload.clientId);
    const rawProviderUserId = sanitizeOptionalString(payload.rawProviderUserId);
    const appVersion = sanitizeOptionalString(payload.appVersion);

    if (!provider || !['kakao', 'naver'].includes(provider)) {
      return writeError(
        res,
        'INVALID_PROVIDER',
        400,
        '지원하지 않는 provider 입니다. kakao 또는 naver 만 지원합니다.',
        appendRequestMeta({
          provider,
          reason: 'INVALID_PROVIDER',
          requestAttemptCount: 0,
          fallbackAttempts: 0,
          fallbackUsed: false,
        }, requestId),
      );
    }
    if (!accessToken) {
      return writeError(
        res,
        'MISSING_ACCESS_TOKEN',
        400,
        'accessToken이 비어 있습니다.',
        appendRequestMeta({
          provider,
          reason: 'MISSING_ACCESS_TOKEN',
          requestAttemptCount: 0,
          fallbackAttempts: 0,
          fallbackUsed: false,
        }, requestId),
      );
    }

    console.log('[social/exchange] request parsed', {
      requestId,
      provider,
      hasAccessToken: Boolean(accessToken),
      hasIdToken: Boolean(idToken),
      hasNonce: Boolean(nonce),
      hasProviderAudience: Boolean(providerAudience),
      hasClientId: Boolean(clientId),
      hasRawProviderUserId: Boolean(rawProviderUserId),
      hasAppVersion: Boolean(appVersion),
      accessTokenLength: accessToken.length,
    });

    let profile;
    try {
      if (provider === 'kakao') {
        profile = await verifyKakao(accessToken, idToken, {
          requestId,
          nonce,
          providerAudience,
          clientId,
          rawProviderUserId,
          appVersion,
        });
      } else {
        profile = await verifyNaver(accessToken, idToken, {
          requestId,
          nonce,
          providerAudience,
          clientId,
          rawProviderUserId,
          appVersion,
        });
      }
    } catch (error) {
      const errorCode = error?.code || error?.message;
      const requestAttempts = Array.isArray(error?.requestAttempts)
        ? error.requestAttempts
        : [];
      const requestAttemptCount = requestAttempts.length;
      const fallbackAttempts = requestAttempts.filter((entry) => Number(entry?.attempt || 0) > 1).length;
      const fallbackUsed = Boolean(error?.usedFallbackUserMe) || fallbackAttempts > 0;

      if (errorCode === 'MISSING_ACCESS_TOKEN') {
        return writeError(
          res,
          'MISSING_ACCESS_TOKEN',
          400,
          'accessToken이 비어 있습니다.',
          appendRequestMeta({
            provider,
            requestId,
            reason: errorCode,
            requestAttemptCount,
            fallbackUsed,
          }, requestId),
        );
      }

      if (
        errorCode === 'KAKAO_TOKEN_INVALID' ||
        errorCode === 'NAVER_TOKEN_INVALID' ||
        errorCode === 'KAKAO_REQUIRED_PROPERTY_NOT_ALLOWED' ||
        errorCode === 'OIDC_ID_TOKEN_INVALID' ||
        errorCode === 'OIDC_NONCE_MISMATCH' ||
        errorCode === 'OIDC_AUDIENCE_MISMATCH' ||
        errorCode === 'OIDC_ID_TOKEN_EXPIRED'
      ) {
        return writeError(
          res,
          'INVALID_SOCIAL_TOKEN',
          401,
          '소셜 토큰 검증 실패',
          {
            provider,
            requestId,
            reason:
              errorCode === 'KAKAO_REQUIRED_PROPERTY_NOT_ALLOWED'
                ? 'REQUIRED_PROPERTY_NOT_ALLOWED'
                : errorCode,
            kakaoError: error.kakaoError || null,
            fallbackAttempts,
            fallbackUsed,
            requestAttemptCount,
            status: error.httpStatus || null,
          },
        );
      }

      if (
        errorCode === 'KAKAO_TOKEN_USER_NOT_FOUND' ||
        errorCode === 'NAVER_TOKEN_USER_NOT_FOUND'
      ) {
        return writeError(
          res,
          'SOCIAL_USER_NOT_FOUND',
          422,
          '토큰에서 사용자 정보를 조회할 수 없습니다.',
          appendRequestMeta({
            provider,
            requestId,
            reason: errorCode,
            fallbackAttempts,
            fallbackUsed,
            requestAttemptCount,
            status: error.httpStatus || null,
          }, requestId),
        );
      }

      console.error('[social/exchange] 토큰 검증 중 알 수 없는 오류', {
        requestId,
        provider,
        reason: errorCode,
        error: truncateText(error?.message, 300),
      });
      return writeError(
        res,
        'EXTERNAL_TOKEN_VERIFY_FAILED',
        502,
        '소셜 토큰 검증 중 예기치 않은 오류가 발생했습니다.',
        appendRequestMeta({
          provider,
          requestId,
          reason: errorCode,
          fallbackAttempts,
          fallbackUsed,
          requestAttemptCount,
          status: error.httpStatus || null,
        }, requestId),
      );
    }

  let firebaseToken;
  let displayName = null;
  let photoUrl = null;
  let email = null;
  let profileStatus = null;
  try {
      displayName =
        pickFirstString([
          profile?.displayName,
          profile?.display_name,
          profile?.nickname,
          profile?.name,
          profile?.kakaoProfile?.nickname,
        ]) || null;

      photoUrl =
        pickFirstString([
          profile?.photoUrl,
          profile?.photo_url,
          profile?.profile_image_url,
          profile?.profileImageUrl,
          profile?.profileImage,
          profile?.thumbnail_url,
        ]) || null;

      email =
        pickFirstString([
          profile?.email,
          profile?.emailAddress,
          profile?.kakao_account?.email,
          profile?.response?.email,
        ]) || null;

      profileStatus =
        profile?.profileStatus && typeof profile.profileStatus === 'object'
          ? {
              ...profile.profileStatus,
              hasDisplayName: pickFirstBool([
                profile.profileStatus?.hasDisplayName,
                Boolean(displayName),
              ]),
              hasPhotoUrl: pickFirstBool([
                profile.profileStatus?.hasPhotoUrl,
                Boolean(photoUrl),
              ]),
              hasEmail: pickFirstBool([
                profile.profileStatus?.hasEmail,
                Boolean(email),
              ]),
            }
          : {
              hasDisplayName: Boolean(displayName),
              hasPhotoUrl: Boolean(photoUrl),
              hasEmail: Boolean(email),
              source: profile?.provider ? `${profile.provider}_resolved` : 'exchange_resolved',
            };

      console.log('[social/exchange] resolved profile', {
        provider,
        requestId,
        displayName,
        email,
        profileStatus,
        hasPhotoUrl: Boolean(photoUrl),
        hasEmail: Boolean(email),
        usedFallbackUserMe: profile?.usedFallbackUserMe || false,
        requestAttemptCount: profile?.requestAttempts?.length || 0,
        providerUidLength: profile?.providerUserId?.length || 0,
      });

      const customClaims = {
        provider,
        provider_uid: profile.providerUserId,
        source: profile.tokenSource,
      };
      if (displayName) {
        customClaims.profileDisplayName = displayName;
      }
      if (photoUrl) {
        customClaims.profilePhotoUrl = photoUrl;
      }
      if (email) {
        customClaims.email = email;
      }
      if (profileStatus && typeof profileStatus === 'object') {
        customClaims.profileStatus = profileStatus;
      }

      const providerInfo =
          profile?.providerInfo && typeof profile.providerInfo === 'object'
            ? profile.providerInfo
            : {
                provider,
                providerUserId: profile?.providerUserId,
                source: profile?.tokenSource || 'exchange',
                usedFallbackUserMe: Boolean(profile?.usedFallbackUserMe),
                requestAttemptCount: profile?.requestAttempts?.length || 0,
              };

      console.log('[social/exchange] custom token 생성 시도', {
        provider,
        requestId,
        uid: profile.uid,
        uidLength: profile.uid?.length || 0,
        hasEmail: Boolean(email),
        providerInfo,
        requestAttempts: profile?.requestAttempts || [],
      });
      firebaseToken = await admin.auth().createCustomToken(profile.uid, customClaims);
    } catch (error) {
      console.error('[social/exchange] Firebase token 생성 실패', {
        requestId,
        provider,
        message: truncateText(error?.message, 300),
      });
      console.error('[social/exchange] provider profile', {
        provider: profile?.provider,
        providerUserId: profile?.providerUserId,
        uid: profile?.uid,
        uidLength: profile?.uid?.length || 0,
        requestId,
      });
      return writeError(
        res,
        'FIREBASE_TOKEN_ERROR',
        500,
        'Firebase custom token 생성에 실패했습니다.',
        appendRequestMeta({ provider, requestId }, requestId),
      );
    }

    const elapsedMs = Date.now() - requestStartedAt;
    console.log('[social/exchange] 처리 완료', {
      requestId,
      provider,
      uid: profile?.uid,
      elapsedMs,
    });

      res.json(appendRequestMeta({
        success: true,
        provider,
        displayName,
        photoUrl,
        email,
        profileStatus,
        providerInfo,
        uid: profile.uid,
        displayNameType: typeof displayName,
        photoUrlType: typeof photoUrl,
      emailType: typeof email,
      displayNameSource: typeof displayName === 'string' ? 'exchange_resolved' : null,
      photoUrlSource: typeof photoUrl === 'string' ? 'exchange_resolved' : null,
      emailSource: typeof email === 'string' ? 'exchange_resolved' : null,
      firebaseToken,
      requestAttemptCount: profile?.requestAttempts?.length || 0,
      usedFallbackUserMe: profile?.usedFallbackUserMe || false,
      elapsedMs,
      timestamp: new Date().toISOString(),
    }, requestId));
  } catch (error) {
    console.error('[social/exchange] 처리 실패', {
      requestId,
      message: truncateText(error?.message, 300),
      stack: truncateText(error?.stack, 400),
    });
    if (error instanceof SyntaxError) {
      return writeError(
        res,
        'INVALID_JSON',
        400,
        '요청 본문의 JSON 형식이 잘못되었습니다.',
        appendRequestMeta({ requestId }, requestId),
      );
    }
    if (error.message === 'REQUEST_BODY_TOO_LARGE') {
      return writeError(
        res,
        'REQUEST_BODY_TOO_LARGE',
        413,
        `요청 본문 크기가 제한(${MAX_BODY_BYTES} bytes)을 초과했습니다.`,
        appendRequestMeta({ requestId }, requestId),
      );
    }
    return writeError(
      res,
      'INTERNAL_SERVER_ERROR',
      500,
      '서버 내부 처리 오류가 발생했습니다.',
      appendRequestMeta({ requestId }, requestId),
    );
  }
}

exports[FUNCTION_NAME] = functions
  .region(REGION)
  .runWith({
    serviceAccount: FUNCTION_SERVICE_ACCOUNT,
  })
  .https.onRequest(async (req, res) => {
    setCorsHeaders(req, res);
    const requestId = parseRequestId(req);
    res.set('x-request-id', requestId);

    if (req.method === 'OPTIONS') {
      return res.status(204).end();
    }

    if (req.method !== 'POST' && req.path !== EXCHANGE_PATH) {
      return writeError(
        res,
        'METHOD_NOT_ALLOWED',
        405,
        `허용되지 않은 메서드입니다. ${req.method}`,
        appendRequestMeta({ path: req.path }, requestId),
      );
    }

    return handleExchange(req, res, requestId);
  });

