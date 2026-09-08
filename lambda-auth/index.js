'use strict';

/**
 * Lambda@Edge viewer-request auth check for private.netjimb.com.
 *
 * Lambda@Edge functions can't use environment variables, so the Cognito
 * config is read from SSM Parameter Store on cold start and cached for the
 * life of the execution environment (SSM values don't change at runtime).
 *
 * cognito-at-edge (https://github.com/awslabs/cognito-at-edge) does the
 * actual work: redirecting unauthenticated viewers to the Cognito Hosted UI,
 * exchanging the auth code for tokens on the /parseauth callback, verifying
 * the session cookie on every other request, and handling refresh/sign-out.
 */

const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');
const { Authenticator } = require('cognito-at-edge');

const PARAM_PREFIX = '/private-netjimb-com';
const ssm = new SSMClient({ region: 'us-east-1' });

let authenticatorPromise;

async function getParam(name) {
  const result = await ssm.send(new GetParameterCommand({ Name: `${PARAM_PREFIX}/${name}` }));
  return result.Parameter.Value;
}

async function buildAuthenticator() {
  const [region, userPoolId, userPoolAppId, userPoolDomain] = await Promise.all([
    getParam('region'),
    getParam('user-pool-id'),
    getParam('user-pool-client-id'),
    getParam('user-pool-domain'),
  ]);

  return new Authenticator({
    region,
    userPoolId,
    userPoolAppId,
    userPoolDomain,
    parseAuthPath: '/parseauth',
    cookieExpirationDays: 7,
    httpOnly: true,
    sameSite: 'Lax',
    logLevel: 'silent',
  });
}

exports.handler = async (request) => {
  if (!authenticatorPromise) {
    authenticatorPromise = buildAuthenticator();
  }
  const authenticator = await authenticatorPromise;
  return authenticator.handle(request);
};
