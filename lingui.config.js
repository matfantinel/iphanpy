import { ALL_LOCALES } from './src/locales';

const config = {
  locales: ALL_LOCALES,
  sourceLocale: 'en',
  pseudoLocale: {
    locale: 'pseudo-LOCALE',
  },
  fallbackLocales: {
    default: 'en',
  },
  catalogs: [
    {
      path: '<rootDir>/src/locales/{locale}',
      include: ['src'],
      exclude: ['src/iphanpy-overrides'],
    },
    {
      path: '<rootDir>/src/iphanpy-overrides/locales/{locale}',
      include: ['src/iphanpy-overrides'],
    },
  ],
  // compileNamespace: 'es',
  orderBy: 'origin',
  macro: {
    jsxPlaceholderAttribute: '_t',
  },
};

export default config;
