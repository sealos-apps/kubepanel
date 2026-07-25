/** @type {import('next').NextConfig} */
const path = require('path');

const nextConfig = {
  output: 'standalone',
  reactStrictMode: false,
  compress: true,
  transpilePackages: ['@labring/sealos-desktop-sdk', 'monaco-editor'],
  experimental: {
    outputFileTracingRoot: path.join(__dirname)
  }
};

module.exports = nextConfig;
