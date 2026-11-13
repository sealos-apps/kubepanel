const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { afterEach, beforeEach, test } = require('node:test');
const ts = require('typescript');
const { Config, KubeConfig } = require('@kubernetes/client-node');

// Run the backend TypeScript directly without adding a test runtime dependency.
require.extensions['.ts'] = (module, filename) => {
  const { outputText } = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, esModuleInterop: true }
  });
  module._compile(outputText, filename);
};
const { loadKubeConfig, getAxiosRequestConfig } = require('../src/services/backend/kubeconfig.ts');
delete require.extensions['.ts'];

const trustedCluster = {
  name: 'trusted',
  server: 'https://trusted.invalid:6443/',
  caData: Buffer.from('trusted-ca').toString('base64'),
  tlsServerName: 'trusted.invalid',
  skipTLSVerify: false
};
const trustedConfigError = /Invalid trusted Kubernetes cluster configuration/;

const environmentKeys = [
  'KUBECONFIG',
  'HOME',
  'KUBERNETES_SERVICE_HOST',
  'KUBERNETES_SERVICE_PORT'
];
let directory;
let previousEnvironment;

beforeEach(() => {
  directory = fs.mkdtempSync(path.join(os.tmpdir(), 'kubepanel-test-'));
  previousEnvironment = Object.fromEntries(environmentKeys.map((key) => [key, process.env[key]]));
  process.env.HOME = directory;
  process.env.KUBECONFIG = path.join(directory, 'config');
  delete process.env.KUBERNETES_SERVICE_HOST;
  delete process.env.KUBERNETES_SERVICE_PORT;
});

afterEach(() => {
  for (const key of environmentKeys) {
    if (previousEnvironment[key] === undefined) delete process.env[key];
    else process.env[key] = previousEnvironment[key];
  }
  fs.rmSync(directory, { recursive: true, force: true });
});

function fixture(server = 'https://caller.invalid', user = { token: 'caller-token' }) {
  return loadKubeConfig(
    JSON.stringify({
      'current-context': 'active',
      contexts: [{ name: 'active', context: { cluster: 'c', user: 'u', namespace: 'default' } }],
      clusters: [
        {
          name: 'c',
          cluster: {
            server,
            'insecure-skip-tls-verify': true,
            'certificate-authority-data': Buffer.from('caller-ca').toString('base64'),
            'tls-server-name': 'caller.invalid'
          }
        }
      ],
      users: [{ name: 'u', user }]
    })
  );
}

function useTrustedCluster(t, cluster = trustedCluster) {
  return t.mock.method(KubeConfig.prototype, 'loadFromDefault', function () {
    this.loadFromClusterAndUser(cluster, { name: 'server-admin', token: 'must-not-use' });
  });
}

function writeTrustedConfig(filename, cluster = trustedCluster) {
  const defaults = new KubeConfig();
  defaults.loadFromClusterAndUser(cluster, { name: 'server-admin', token: 'must-not-use' });
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, defaults.exportConfig());
}

function useInClusterFiles(t) {
  for (const [key, filename] of Object.entries({
    SERVICEACCOUNT_CA_PATH: 'ca.crt',
    SERVICEACCOUNT_TOKEN_PATH: 'token',
    SERVICEACCOUNT_NAMESPACE_PATH: 'namespace'
  })) {
    const previous = Config[key];
    Config[key] = path.join(directory, filename);
    t.after(() => {
      Config[key] = previous;
    });
  }
  fs.writeFileSync(Config.SERVICEACCOUNT_CA_PATH, 'trusted-file-ca');
  fs.writeFileSync(Config.SERVICEACCOUNT_TOKEN_PATH, 'service-account-token-must-not-use');
  fs.writeFileSync(Config.SERVICEACCOUNT_NAMESPACE_PATH, 'default');
  process.env.KUBERNETES_SERVICE_HOST = '10.96.0.1';
  process.env.KUBERNETES_SERVICE_PORT = '443';
}

test('KUBECONFIG selects the server endpoint while retaining the caller identity', () => {
  writeTrustedConfig(process.env.KUBECONFIG);
  const config = getAxiosRequestConfig(fixture());
  assert.equal(config.baseURL, 'https://trusted.invalid:6443');
  assert.equal(config.headers.Authorization, 'Bearer caller-token');
  assert.deepEqual(config.httpsAgent.options.ca, Buffer.from('trusted-ca'));
  config.httpsAgent.destroy();
});

test('home kubeconfig is used before in-cluster configuration', (t) => {
  delete process.env.KUBECONFIG;
  useInClusterFiles(t);
  writeTrustedConfig(path.join(directory, '.kube', 'config'));
  const config = getAxiosRequestConfig(fixture());
  assert.equal(config.baseURL, 'https://trusted.invalid:6443');
  assert.equal(config.headers.Authorization, 'Bearer caller-token');
  config.httpsAgent.destroy();
});

test('in-cluster configuration supplies the endpoint and CA but not ServiceAccount credentials', (t) => {
  delete process.env.KUBECONFIG;
  useInClusterFiles(t);
  const config = getAxiosRequestConfig(fixture());
  assert.equal(config.baseURL, 'https://10.96.0.1:443');
  assert.deepEqual(config.httpsAgent.options.ca, Buffer.from('trusted-file-ca'));
  assert.equal(config.headers.Authorization, 'Bearer caller-token');
  assert.equal(config.httpsAgent.options.rejectUnauthorized, true);
  config.httpsAgent.destroy();
});

test('no configured source fails before the implicit localhost default can be loaded', (t) => {
  delete process.env.KUBECONFIG;
  const defaults = t.mock.method(KubeConfig.prototype, 'loadFromDefault', () => {
    throw new Error('must not load implicit defaults');
  });
  assert.throws(() => getAxiosRequestConfig(fixture()), trustedConfigError);
  assert.equal(defaults.mock.callCount(), 0);
});

for (const missing of ['KUBERNETES_SERVICE_HOST', 'KUBERNETES_SERVICE_PORT', 'token', 'ca']) {
  test(`in-cluster configuration missing ${missing} is rejected`, (t) => {
    delete process.env.KUBECONFIG;
    useInClusterFiles(t);
    if (missing === 'token') fs.unlinkSync(Config.SERVICEACCOUNT_TOKEN_PATH);
    else if (missing === 'ca') fs.unlinkSync(Config.SERVICEACCOUNT_CA_PATH);
    else delete process.env[missing];
    assert.throws(() => getAxiosRequestConfig(fixture()), trustedConfigError);
  });
}

test('an explicitly configured missing file does not fall back to in-cluster configuration', (t) => {
  useInClusterFiles(t);
  assert.throws(() => getAxiosRequestConfig(fixture()), trustedConfigError);
});

test('a broken home config does not fall back to in-cluster configuration', (t) => {
  delete process.env.KUBECONFIG;
  useInClusterFiles(t);
  const filename = path.join(directory, '.kube', 'config');
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, 'clusters: [');
  assert.throws(() => getAxiosRequestConfig(fixture()), trustedConfigError);
});

for (const server of [
  'https://admin:server-password@trusted.invalid',
  'https://admin@trusted.invalid',
  'https://:server-password@trusted.invalid',
  'file:///server/config',
  'not-a-url'
]) {
  test(`invalid or credential-bearing trusted server is rejected: ${server}`, () => {
    writeTrustedConfig(process.env.KUBECONFIG, { ...trustedCluster, server });
    assert.throws(() => getAxiosRequestConfig(fixture()), trustedConfigError);
  });
}

test('malformed server YAML does not expose its credential snippet', () => {
  fs.writeFileSync(
    process.env.KUBECONFIG,
    'users:\n- name: admin\n  user:\n    token: DUMMY_SERVER_SECRET: broken\n'
  );
  assert.throws(() => getAxiosRequestConfig(fixture()), (error) => {
    assert.match(error.message, trustedConfigError);
    assert.ok(!error.message.includes('DUMMY_SERVER_SECRET'));
    return true;
  });
});

test('server CA read errors do not expose filesystem paths or underlying error text', (t) => {
  useTrustedCluster(t, { ...trustedCluster, caFile: '/trusted/private/ca.crt' });
  const input = fixture();
  t.mock.method(fs, 'readFileSync', () => {
    throw new Error('EACCES: server-private-detail /trusted/private/ca.crt');
  });
  assert.throws(() => getAxiosRequestConfig(input), (error) => {
    assert.match(error.message, trustedConfigError);
    assert.ok(!error.message.includes('server-private-detail'));
    assert.ok(!error.message.includes('/trusted/private/ca.crt'));
    return true;
  });
});

test('caller endpoints cannot override the trusted API server or TLS settings', (t) => {
  const defaults = useTrustedCluster(t);
  for (const server of ['https://caller.invalid', 'http://127.0.0.1:8080', 'http://169.254.169.254']) {
    const config = getAxiosRequestConfig(fixture(server));
    assert.equal(config.baseURL, 'https://trusted.invalid:6443');
    assert.equal(config.maxRedirects, 0);
    assert.equal(config.httpsAgent.options.rejectUnauthorized, true);
    assert.equal(config.httpsAgent.options.servername, 'trusted.invalid');
    assert.deepEqual(config.httpsAgent.options.ca, Buffer.from('trusted-ca'));
    assert.equal(config.headers.Authorization, 'Bearer caller-token');
    config.httpsAgent.destroy();
  }
  assert.equal(defaults.mock.callCount(), 3);
});

test('CA file paths come only from the server configuration', (t) => {
  useTrustedCluster(t, { ...trustedCluster, caFile: '/trusted/kubernetes-ca.crt' });
  const input = fixture();
  Object.assign(input.clusters[0], { caFile: '/caller/must-not-read' });
  const reads = t.mock.method(fs, 'readFileSync', (path) => {
    assert.equal(path, '/trusted/kubernetes-ca.crt');
    return Buffer.from('trusted-file-ca');
  });
  const config = getAxiosRequestConfig(input);
  assert.deepEqual(config.httpsAgent.options.ca, Buffer.from('trusted-file-ca'));
  assert.equal(reads.mock.callCount(), 1);
  config.httpsAgent.destroy();
});

test('client certificates remain caller credentials without inheriting server credentials', (t) => {
  useTrustedCluster(t);
  const config = getAxiosRequestConfig(
    fixture('https://caller.invalid', {
      'client-certificate-data': Buffer.from('caller-cert').toString('base64'),
      'client-key-data': Buffer.from('caller-key').toString('base64')
    })
  );
  assert.deepEqual(config.httpsAgent.options.cert, Buffer.from('caller-cert'));
  assert.deepEqual(config.httpsAgent.options.key, Buffer.from('caller-key'));
  assert.equal(config.headers.Authorization, '');
  assert.equal(config.auth, undefined);
  config.httpsAgent.destroy();
});

test('missing trusted cluster fails instead of using the caller endpoint', (t) => {
  t.mock.method(KubeConfig.prototype, 'loadFromDefault', () => {});
  assert.throws(() => getAxiosRequestConfig(fixture()), trustedConfigError);
});

test('server configuration errors are sanitized without falling back to caller settings', (t) => {
  t.mock.method(KubeConfig.prototype, 'loadFromDefault', () => {
    throw new Error('trusted config unavailable');
  });
  assert.throws(() => getAxiosRequestConfig(fixture()), trustedConfigError);
});
