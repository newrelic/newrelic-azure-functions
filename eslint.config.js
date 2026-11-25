const eslintPluginPrettierRecommended = require('eslint-plugin-prettier/recommended');

// Flat config (ESLint v9+). Mirrors the previous .eslintrc.js: the only enforced
// rule is prettier/prettier, with eslint-config-prettier turning off any conflicting
// stylistic rules. eslint-plugin-prettier/recommended wires up all three.
module.exports = [
  {
    ignores: ['invalid-json/', 'coverage/'],
  },
  eslintPluginPrettierRecommended,
  {
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: 'commonjs',
      globals: {
        Atomics: 'readonly',
        SharedArrayBuffer: 'readonly',
      },
    },
  },
  {
    files: [
      'test/integration/*.tap.js',
      'test/integration/*/*.tap.js',
      'test/integration/core/exec-me.js',
    ],
    rules: {
      'no-console': 'off',
    },
  },
];
