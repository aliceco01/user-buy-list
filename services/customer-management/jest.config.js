module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/'],
  testMatch: ['**/?(*.)+(spec|test).[jt]s?(x)'],
  moduleFileExtensions: ['ts', 'js', 'json', 'node'],
  coverageDirectory: '<rootDir>/coverage',
  collectCoverage: true,
  collectCoverageFrom: ['**/*.{ts,js}', '!**/node_modules/**'],
  setupFilesAfterEnv: ['<rootDir>/setupTests.js']
};