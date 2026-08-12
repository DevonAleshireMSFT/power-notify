import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const SCHEMA_VERSION = '1.0.0';

const packageJsonPath = fileURLToPath(new URL('../../package.json', import.meta.url));
const SEMVER_PATTERN = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/;

// package.json is the release artifact source of truth; reading it here lets tooling
// and future consumer stamps share FRAMEWORK_VERSION without duplicating the value.
export const FRAMEWORK_VERSION = readPackageVersion(packageJsonPath);

export function compareSemver(left, right) {
  const leftParsed = parseSemver(left);
  const rightParsed = parseSemver(right);

  for (const field of ['major', 'minor', 'patch']) {
    if (leftParsed[field] !== rightParsed[field]) {
      return Math.sign(leftParsed[field] - rightParsed[field]);
    }
  }

  if (leftParsed.prerelease === rightParsed.prerelease) {
    return 0;
  }

  if (!leftParsed.prerelease) {
    return 1;
  }

  if (!rightParsed.prerelease) {
    return -1;
  }

  return Math.sign(leftParsed.prerelease.localeCompare(rightParsed.prerelease, 'en', { numeric: true }));
}

export function compareSchemaCompatibility(left, right) {
  const leftParsed = parseSemver(left);
  const rightParsed = parseSemver(right);

  if (leftParsed.major !== rightParsed.major) {
    return Math.sign(leftParsed.major - rightParsed.major);
  }

  if (leftParsed.minor !== rightParsed.minor) {
    return Math.sign(leftParsed.minor - rightParsed.minor);
  }

  // Schema compatibility is major.minor-based: patch releases are backward-compatible
  // clarifications. A prerelease schema for the same major.minor is still older than
  // the released schema, so it must not silently pass as equivalent to the release.
  if (leftParsed.prerelease && !rightParsed.prerelease) {
    return -1;
  }

  if (!leftParsed.prerelease && rightParsed.prerelease) {
    return 1;
  }

  return 0;
}

export function isSemver(value) {
  return typeof value === 'string' && SEMVER_PATTERN.test(value);
}

function parseSemver(value) {
  const match = typeof value === 'string' ? value.match(SEMVER_PATTERN) : null;
  if (!match) {
    throw new Error(`Invalid semver: ${value}`);
  }

  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    prerelease: match[4] ?? ''
  };
}

function readPackageVersion(filePath) {
  const packageJson = JSON.parse(readFileSync(filePath, 'utf8'));
  if (!isSemver(packageJson.version)) {
    throw new Error('package.json version must be a valid semver string.');
  }

  return packageJson.version;
}
