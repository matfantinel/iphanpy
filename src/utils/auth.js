import { generateCodeChallenge, verifier } from './oauth-pkce';
import { getRedirectURI } from '../iphanpy-overrides/utils/auth-overrides';

const {
  PHANPY_CLIENT_NAME: CLIENT_NAME,
  PHANPY_WEBSITE: WEBSITE,
} = import.meta.env;

const DEV = false;

const SCOPES = 'read write follow push';
const REDIRECT_URI = getRedirectURI();

export async function registerApplication({ instanceURL }) {
  const registrationParams = new URLSearchParams({
    client_name: CLIENT_NAME,
    redirect_uris: REDIRECT_URI,
    scopes: SCOPES,
    website: WEBSITE || REDIRECT_URI,
  });
  const registrationResponse = await fetch(
    `https://${instanceURL}/api/v1/apps`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: registrationParams.toString(),
    },
  );
  const registrationJSON = await registrationResponse.json();
  if (DEV) console.log({ registrationJSON });
  return registrationJSON;
}

export async function getPKCEAuthorizationURL({
  instanceURL,
  client_id,
  forceLogin = false,
}) {
  const codeVerifier = verifier();
  const codeChallenge = await generateCodeChallenge(codeVerifier);
  const params = new URLSearchParams({
    client_id,
    code_challenge_method: 'S256',
    code_challenge: codeChallenge,
    redirect_uri: REDIRECT_URI,
    response_type: 'code',
    scope: SCOPES,
  });
  if (forceLogin) params.append('force_login', true);
  const authorizationURL = `https://${instanceURL}/oauth/authorize?${params.toString()}`;
  return [authorizationURL, codeVerifier];
}

export async function getAuthorizationURL({
  instanceURL,
  client_id,
  forceLogin = false,
}) {
  const authorizationParams = new URLSearchParams({
    client_id,
    scope: SCOPES,
    redirect_uri: REDIRECT_URI,
    // redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
    response_type: 'code',
  });
  if (forceLogin) authorizationParams.append('force_login', true);
  const authorizationURL = `https://${instanceURL}/oauth/authorize?${authorizationParams.toString()}`;
  return authorizationURL;
}

export async function getAccessToken({
  instanceURL,
  client_id,
  client_secret,
  code,
  code_verifier,
}) {
  const params = new URLSearchParams({
    client_id,
    redirect_uri: REDIRECT_URI,
    grant_type: 'authorization_code',
    code,
    // scope: SCOPES, // Not needed
    // client_secret,
    // code_verifier,
  });
  if (client_secret) {
    params.append('client_secret', client_secret);
  }
  if (code_verifier) {
    params.append('code_verifier', code_verifier);
  }
  const tokenResponse = await fetch(`https://${instanceURL}/oauth/token`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: params.toString(),
  });
  const tokenJSON = await tokenResponse.json();
  if (DEV) console.log({ tokenJSON });
  return tokenJSON;
}

export async function revokeAccessToken({
  instanceURL,
  client_id,
  client_secret,
  token,
}) {
  try {
    const params = new URLSearchParams({
      client_id,
      client_secret,
      token,
    });

    const revokeResponse = await fetch(`https://${instanceURL}/oauth/revoke`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params.toString(),
      keepalive: true,
    });

    return revokeResponse.ok;
  } catch (error) {
    console.error('Error revoking token', error);
    return false;
  }
}
