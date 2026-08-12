import { readdir, readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseFrontmatter } from './lib/frontmatter.mjs';
import { compareSchemaCompatibility, FRAMEWORK_VERSION, isSemver, SCHEMA_VERSION } from './lib/version.mjs';

const CONTEXT_REQUIRED_FIELDS = [
  'project',
  'platform',
  'context-version',
  'last-updated',
  'owner',
  'review-cadence'
];

const ADR_REQUIRED_FIELDS = [
  'adr',
  'title',
  'status',
  'date',
  'deciders',
  'reviewers',
  'applies-to',
  'supersedes',
  'superseded-by'
];

const REVIEW_CADENCES = new Set(['every-sprint', 'monthly', 'quarterly', 'biannual', 'annual']);
const ADR_STATUSES = new Set(['proposed', 'accepted', 'superseded', 'deprecated']);
const SEMVER_PATTERN = /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/;
const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const ISO_DATETIME_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const ADR_FILENAME_PATTERN = /^\d{4}-.*\.md$/;
const PLACEHOLDER_PATTERN = /^\s*(?:\[.*\]|YYYY-MM-DD|NNNN)\s*$/;
const NULLABLE_FILENAME_PATTERN = /^(?:null|\d{4}-.+\.md)$/;

/**
 * Validate a repository's .ai/ content against the framework template contract.
 *
 * @param {string} root Repository root directory.
 * @returns {Promise<Array<{severity: 'ERROR' | 'WARNING', file: string, message: string}>>}
 */
export async function validate(root = process.cwd()) {
  const resolvedRoot = path.resolve(root);
  const findings = [];
  const contextPath = path.join(resolvedRoot, '.ai', 'context.md');

  await validateContext(contextPath, findings);
  await validateAdrs(path.join(resolvedRoot, '.ai', 'adr'), findings);

  return findings;
}

async function validateContext(filePath, findings) {
  const relativeFile = '.ai/context.md';
  const text = await readText(filePath);
  if (text === null) {
    addError(findings, relativeFile, 'Missing required .ai/context.md file.');
    return;
  }

  const parsed = parseFrontmatter(text);
  if (!parsed.data) {
    addError(findings, relativeFile, 'Missing leading --- front-matter block.');
    return;
  }

  requireFields(parsed.data, CONTEXT_REQUIRED_FIELDS, relativeFile, findings);
  requireNonPlaceholder(parsed.data, 'project', relativeFile, findings);
  requireNonPlaceholder(parsed.data, 'platform', relativeFile, findings);
  requireNonPlaceholder(parsed.data, 'owner', relativeFile, findings);

  if (hasValue(parsed.data, 'context-version') && !SEMVER_PATTERN.test(parsed.data['context-version'])) {
    addError(findings, relativeFile, 'context-version must be semver, for example 1.0.0.');
  }

  validateSchemaVersion(parsed.data, relativeFile, findings);

  if (hasValue(parsed.data, 'last-updated') && !isValidIsoDateOrDateTime(parsed.data['last-updated'])) {
    addError(findings, relativeFile, 'last-updated must be YYYY-MM-DD or a full ISO-8601 datetime.');
  }

  if (hasValue(parsed.data, 'review-cadence') && !REVIEW_CADENCES.has(parsed.data['review-cadence'])) {
    addError(
      findings,
      relativeFile,
      `review-cadence must be one of: ${Array.from(REVIEW_CADENCES).join(', ')}.`
    );
  }
}

function validateSchemaVersion(data, relativeFile, findings) {
  if (!hasValue(data, 'schema-version')) {
    return;
  }

  const declared = data['schema-version'];
  if (!isSemver(declared)) {
    addWarning(findings, relativeFile, 'schema-version should be semver, for example 1.0.0.');
    return;
  }

  const comparison = compareSchemaCompatibility(declared, SCHEMA_VERSION);
  if (comparison < 0) {
    addWarning(
      findings,
      relativeFile,
      `schema-version ${declared} is older than validator schema ${SCHEMA_VERSION}; run ai-context update and review migration notes.`
    );
  } else if (comparison > 0) {
    addWarning(
      findings,
      relativeFile,
      `schema-version ${declared} is newer than validator schema ${SCHEMA_VERSION}; tooling may be behind.`
    );
  }
}

async function validateAdrs(adrDir, findings) {
  const entries = await readdirSafe(adrDir);
  if (!entries) {
    addWarning(findings, '.ai/adr', 'ADR directory is missing; no ADR files were validated.');
    return;
  }

  for (const entry of entries) {
    if (!entry.isFile() || path.extname(entry.name) !== '.md') {
      continue;
    }

    if (entry.name === 'index.md' || !ADR_FILENAME_PATTERN.test(entry.name)) {
      continue;
    }

    await validateAdr(path.join(adrDir, entry.name), path.posix.join('.ai/adr', entry.name), findings);
  }
}

async function validateAdr(filePath, relativeFile, findings) {
  const text = await readText(filePath);
  if (text === null) {
    addError(findings, relativeFile, 'ADR file could not be read.');
    return;
  }

  const parsed = parseFrontmatter(text);
  if (!parsed.data) {
    addError(findings, relativeFile, 'Missing leading --- front-matter block.');
    return;
  }

  requireFields(parsed.data, ADR_REQUIRED_FIELDS, relativeFile, findings);
  for (const field of ['title', 'deciders', 'reviewers', 'applies-to']) {
    requireNonPlaceholder(parsed.data, field, relativeFile, findings);
  }

  const filenameAdr = path.basename(filePath).slice(0, 4);
  if (hasValue(parsed.data, 'adr')) {
    if (!/^\d{4}$/.test(parsed.data.adr)) {
      addError(findings, relativeFile, 'adr must be a four-digit number.');
    } else if (parsed.data.adr !== filenameAdr) {
      addError(findings, relativeFile, `adr (${parsed.data.adr}) must match filename prefix (${filenameAdr}).`);
    }
  }

  if (hasValue(parsed.data, 'status') && !ADR_STATUSES.has(parsed.data.status)) {
    addError(findings, relativeFile, `status must be one of: ${Array.from(ADR_STATUSES).join(', ')}.`);
  }

  if (hasValue(parsed.data, 'date') && !isValidIsoDate(parsed.data.date)) {
    addError(findings, relativeFile, 'date must be an ISO date in YYYY-MM-DD format.');
  }

  for (const field of ['supersedes', 'superseded-by']) {
    if (hasValue(parsed.data, field) && !NULLABLE_FILENAME_PATTERN.test(parsed.data[field])) {
      addError(findings, relativeFile, `${field} must be an ADR filename or the literal null.`);
    }
  }
}

function requireFields(data, fields, file, findings) {
  for (const field of fields) {
    if (!hasValue(data, field)) {
      addError(findings, file, `Missing required front-matter field: ${field}.`);
    }
  }
}

function requireNonPlaceholder(data, field, file, findings) {
  if (!hasValue(data, field)) {
    return;
  }

  if (PLACEHOLDER_PATTERN.test(data[field])) {
    addError(findings, file, `${field} must be replaced with a real value.`);
  }
}

function hasValue(data, field) {
  return Object.hasOwn(data, field) && data[field].trim() !== '';
}

function isValidIsoDate(value) {
  if (!ISO_DATE_PATTERN.test(value)) {
    return false;
  }

  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === value;
}

function isValidIsoDateOrDateTime(value) {
  if (isValidIsoDate(value)) {
    return true;
  }

  if (!ISO_DATETIME_PATTERN.test(value)) {
    return false;
  }

  return !Number.isNaN(Date.parse(value));
}

async function readText(filePath) {
  try {
    const fileStat = await stat(filePath);
    if (!fileStat.isFile()) {
      return null;
    }

    return await readFile(filePath, 'utf8');
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return null;
    }

    throw error;
  }
}

async function readdirSafe(dirPath) {
  try {
    return await readdir(dirPath, { withFileTypes: true });
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return null;
    }

    throw error;
  }
}

function addError(findings, file, message) {
  findings.push({ severity: 'ERROR', file, message });
}

function addWarning(findings, file, message) {
  findings.push({ severity: 'WARNING', file, message });
}

function printReport(findings) {
  if (findings.length === 0) {
    console.log('✅ .ai/ template conformance passed.');
    console.log('Summary: 0 ERROR, 0 WARNING');
    return;
  }

  const byFile = new Map();
  for (const finding of findings) {
    const fileFindings = byFile.get(finding.file) ?? [];
    fileFindings.push(finding);
    byFile.set(finding.file, fileFindings);
  }

  const hasErrors = findings.some((finding) => finding.severity === 'ERROR');
  console.log(`${hasErrors ? '❌' : '⚠️'} .ai/ template conformance findings:`);
  for (const [file, fileFindings] of byFile) {
    console.log(`\n${file}`);
    for (const finding of fileFindings) {
      const icon = finding.severity === 'ERROR' ? '❌' : '⚠️';
      console.log(`  ${icon} ${finding.severity}: ${finding.message}`);
    }
  }

  const errorCount = findings.filter((finding) => finding.severity === 'ERROR').length;
  const warningCount = findings.filter((finding) => finding.severity === 'WARNING').length;
  console.log(`\nSummary: ${errorCount} ERROR, ${warningCount} WARNING`);
}

function parseArgs(argv) {
  const result = { root: process.cwd(), strict: false };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--strict') {
      result.strict = true;
    } else if (arg === '--root') {
      const root = argv[index + 1];
      if (!root) {
        throw new Error('--root requires a directory argument.');
      }

      result.root = root;
      index += 1;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return result;
}

async function main() {
  try {
    const { root, strict } = parseArgs(process.argv.slice(2));
    const findings = await validate(root);
    console.log(`AI Context Framework — validator v${FRAMEWORK_VERSION} (schema ${SCHEMA_VERSION})`);
    printReport(findings);

    const hasErrors = findings.some((finding) => finding.severity === 'ERROR');
    const hasWarnings = findings.some((finding) => finding.severity === 'WARNING');
    process.exitCode = hasErrors || (strict && hasWarnings) ? 1 : 0;
  } catch (error) {
    console.error(`❌ ${error.message}`);
    process.exitCode = 1;
  }
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === currentFile) {
  await main();
}
