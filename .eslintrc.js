module.exports = {
  env: {
    es2020: true,
    node: true,
    browser: false,
  },
  ignorePatterns: ['invalid-json/'],
  extends: ['prettier'],
  globals: {
    Atomics: 'readonly',
    SharedArrayBuffer: 'readonly',
  },
  plugins: ['prettier'],
  rules: {
    'prettier/prettier': 'error',
  },
  overrides: [
    {
      files: [
        'test/integration/*.tap.js',
        'test/integration/*/*.tap.js',
        'test/integration/core/exec-me.js',
      ],
      rules: {
        'no-console': ['off'],
      },
    },
  ],
};
