import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const REGISTERED_REPOSITORIES_HEADER =
  'Repository | Adoption Date | Tier-2 Owner | Mode | Status | Squad Boundary Enforcement | Notes';
const REQUIRED_CELL_COUNT = 7;
const FALLBACK_MODES = new Set(['standalone', 'squad-companion']);
const FALLBACK_STATUSES = new Set(['Active', 'Bootstrapped', 'Stale', 'Archived']);
const ISO_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Validate registry.md's Registered Repositories table.
 *
 * @param {string} root Repository root directory.
 * @returns {Promise<Array<{severity: 'ERROR' | 'WARNING', file: string, message: string}>>}
 */
export async function validateRegistry(root = process.cwd()) {
  const resolvedRoot = path.resolve(root);
  const findings = [];
  const registryPath = path.join(resolvedRoot, 'registry.md');
  const text = await readText(registryPath);

  if (text === null) {
    addError(findings, 'registry.md', 'Missing required registry.md file.');
    return findings;
  }

  const lines = text.split(/\r?\n/);
  const modes = parseEnumTable(lines, 'Adoption Modes', 'Mode', FALLBACK_MODES);
  const statuses = parseEnumTable(lines, 'Adoption Statuses', 'Status', FALLBACK_STATUSES);
  const registeredTable = findRegisteredRepositoriesTable(lines);

  if (!registeredTable) {
    addError(findings, 'registry.md', 'Missing Registered Repositories table with the expected schema header.');
    return findings;
  }

  for (const row of registeredTable.rows) {
    validateRegisteredRepositoryRow(row, modes, statuses, findings);
  }

  return findings;
}

function findRegisteredRepositoriesTable(lines) {
  const headerIndex = lines.findIndex((line) => normalizeTableLine(line).startsWith(REGISTERED_REPOSITORIES_HEADER));
  if (headerIndex === -1) {
    return null;
  }

  const rows = [];
  for (let index = headerIndex + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (!isTableRow(line)) {
      break;
    }

    if (isSeparatorRow(line)) {
      continue;
    }

    // Markdown tables are positional here: keep empty cells so a short/long row is reported accurately.
    rows.push({ lineNumber: index + 1, cells: splitTableRow(line), raw: line });
  }

  return { headerLine: headerIndex + 1, rows };
}

function validateRegisteredRepositoryRow(row, modes, statuses, findings) {
  const file = `registry.md:${row.lineNumber}`;
  if (row.cells.length !== REQUIRED_CELL_COUNT) {
    addError(findings, file, `Registered repository row must have exactly 7 cells; found ${row.cells.length}.`);
    return;
  }

  const [repository, adoptionDate, owner, mode, status, boundaryEnforcement] = row.cells;
  const cleanMode = cleanEnumValue(mode);
  const cleanStatus = cleanEnumValue(status);

  if (repository.trim() === '') {
    addError(findings, file, 'Repository must be non-empty.');
  }

  if (adoptionDate.trim() === 'YYYY-MM-DD') {
    addWarning(findings, file, 'Adoption Date uses YYYY-MM-DD placeholder; replace it when this row is finalized.');
  } else if (!isValidIsoDate(adoptionDate.trim())) {
    addError(findings, file, 'Adoption Date must be an ISO date in YYYY-MM-DD format.');
  }

  if (owner.trim() === '') {
    addError(findings, file, 'Tier-2 Owner must be non-empty.');
  }

  if (!modes.has(cleanMode)) {
    addError(findings, file, `Mode must be one of: ${Array.from(modes).join(', ')}.`);
  }

  if (!statuses.has(cleanStatus)) {
    addError(findings, file, `Status must be one of: ${Array.from(statuses).join(', ')}.`);
  }

  if (boundaryEnforcement.trim() === '') {
    addError(findings, file, 'Squad Boundary Enforcement must be non-empty.');
  }
}

function parseEnumTable(lines, sectionTitle, expectedHeader, fallbackValues) {
  const sectionIndex = lines.findIndex((line) => line.trim() === `## ${sectionTitle}`);
  if (sectionIndex === -1) {
    return fallbackValues;
  }

  const headerIndex = findNextTableRow(lines, sectionIndex + 1);
  if (headerIndex === -1) {
    return fallbackValues;
  }

  const headerCells = splitTableRow(lines[headerIndex]);
  if (cleanEnumValue(headerCells[0] ?? '') !== expectedHeader) {
    return fallbackValues;
  }

  const values = new Set();
  for (let index = headerIndex + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (!isTableRow(line)) {
      break;
    }

    if (isSeparatorRow(line)) {
      continue;
    }

    const [enumCell] = splitTableRow(line);
    const value = cleanEnumValue(enumCell ?? '');
    if (value !== '') {
      values.add(value);
    }
  }

  // The validator derives accepted Mode/Status values from registry.md so governance docs stay authoritative.
  // If those tables cannot be parsed, fall back to the current published schema instead of failing closed.
  return values.size > 0 ? values : fallbackValues;
}

function findNextTableRow(lines, startIndex) {
  for (let index = startIndex; index < lines.length; index += 1) {
    if (isTableRow(lines[index])) {
      return index;
    }
  }

  return -1;
}

function splitTableRow(line) {
  const trimmed = line.trim();
  const withoutLeading = trimmed.startsWith('|') ? trimmed.slice(1) : trimmed;
  const withoutOuterPipes = withoutLeading.endsWith('|') ? withoutLeading.slice(0, -1) : withoutLeading;
  return withoutOuterPipes.split('|').map((cell) => cell.trim());
}

function normalizeTableLine(line) {
  return splitTableRow(line).join(' | ');
}

function isTableRow(line) {
  return line.trim().startsWith('|') && line.includes('|');
}

function isSeparatorRow(line) {
  return splitTableRow(line).every((cell) => /^:?-{3,}:?$/.test(cell.trim()));
}

function cleanEnumValue(value) {
  return value.trim().replace(/^`+|`+$/g, '').trim();
}

function isValidIsoDate(value) {
  if (!ISO_DATE_PATTERN.test(value)) {
    return false;
  }

  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.valueOf()) && date.toISOString().slice(0, 10) === value;
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

function addError(findings, file, message) {
  findings.push({ severity: 'ERROR', file, message });
}

function addWarning(findings, file, message) {
  findings.push({ severity: 'WARNING', file, message });
}

function printReport(findings) {
  if (findings.length === 0) {
    console.log('✅ registry.md validation passed.');
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
  console.log(`${hasErrors ? '❌' : '⚠️'} registry.md validation findings:`);
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
    const findings = await validateRegistry(root);
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
