import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { checkDrift } from '../check-drift.mjs';
import { validate } from '../validate-ai-context.mjs';
import { compareSchemaCompatibility, FRAMEWORK_VERSION, SCHEMA_VERSION } from './version.mjs';

export const STAMP_FILE = '.ai-context.json';
export const COPILOT_INSTRUCTIONS = '.github/copilot-instructions.md';
export const FRAMEWORK_BLOCK_BEGIN = '<!-- BEGIN AI CONTEXT FRAMEWORK MANAGED BLOCK -->';
export const FRAMEWORK_BLOCK_END = '<!-- END AI CONTEXT FRAMEWORK MANAGED BLOCK -->';

const PACKAGE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

export const MANAGED_FILE_MANIFEST = Object.freeze([
  'scripts/check-drift.mjs',
  'scripts/check-links.mjs',
  'scripts/check-staleness.mjs',
  'scripts/validate-ai-context.mjs',
  'scripts/validate-registry.mjs',
  'scripts/lib/cli-operations.mjs',
  'scripts/lib/frontmatter.mjs',
  'scripts/lib/version.mjs',
  '.github/workflows/ai-context-conformance.yml',
  '.github/PULL_REQUEST_TEMPLATE.md'
]);

const INIT_SEEDS = Object.freeze([
  { source: 'templates/context.md.template', target: '.ai/context.md' },
  { source: 'templates/setup-prompt.md.template', target: '.github/prompts/ai-context-setup.prompt.md' }
]);

export function createStamp() {
  return `${JSON.stringify({ frameworkVersion: FRAMEWORK_VERSION, schemaVersion: SCHEMA_VERSION }, null, 2)}\n`;
}

export async function initCommand({ cwd }) {
  const root = path.resolve(cwd);
  const report = emptyReport('init', root);

  await ensureDirectory(root, '.ai/adr', report);

  for (const seed of INIT_SEEDS) {
    await copyIfAbsent(root, seed.source, seed.target, report);
  }

  await mergeOrSeedCopilot(root, { dryRun: false, init: true, report });

  for (const target of MANAGED_FILE_MANIFEST) {
    await writeManagedFile(root, target, { dryRun: false, report });
  }

  await ensureGitignore(root, { dryRun: false, report });
  await writeStamp(root, { dryRun: false, report });

  return report;
}

export async function updateCommand({ cwd, dryRun = false }) {
  const root = path.resolve(cwd);
  const report = emptyReport('update', root, dryRun);
  const installedStamp = await readConsumerStamp(root);

  if (installedStamp.status === 'missing') {
    report.warnings.push(`${STAMP_FILE} missing; adopting this repo as a managed install.`);
  } else if (installedStamp.status === 'invalid') {
    report.manualActions.push(`${STAMP_FILE} is invalid JSON: ${installedStamp.message}`);
  } else {
    addSchemaWarning(installedStamp.data, report);
  }

  for (const target of MANAGED_FILE_MANIFEST) {
    await writeManagedFile(root, target, { dryRun, report });
  }

  await mergeOrSeedCopilot(root, { dryRun, init: false, report });

  if (installedStamp.status !== 'invalid') {
    await writeStamp(root, { dryRun, report });
  }

  report.preserved.push('.ai/**');
  return report;
}

export async function checkCommand({ cwd }) {
  const root = path.resolve(cwd);
  const [validationFindings, driftReport] = await Promise.all([validate(root), checkDrift(root)]);
  return { command: 'check', root, validationFindings, driftReport };
}

export function printInitReport(report) {
  printHeader('init', report);
  printList('created', report.created);
  printList('updated', report.updated);
  printList('skipped', report.skipped);
}

export function printUpdateReport(report) {
  printHeader('update', report);
  printList('updated', report.updated);
  printList('unchanged', report.unchanged);
  printList('preserved', report.preserved);
  printList('manual-actions', report.manualActions);
  printList('warnings', [...report.warnings, ...report.schemaWarnings]);
}

export function printCheckReport(report) {
  console.log(`AI Context Framework check`);
  console.log(`root: ${report.root}`);
  printList(
    'validation',
    report.validationFindings.length === 0
      ? ['passed: 0 ERROR, 0 WARNING']
      : report.validationFindings.map((finding) => `${finding.severity}: ${finding.file}: ${finding.message}`)
  );
  printList(
    'drift',
    report.driftReport.findings.length === 0
      ? [`current: framework ${report.driftReport.frameworkVersion}, schema ${report.driftReport.schemaVersion}`]
      : report.driftReport.findings.map((finding) => `${finding.severity}: ${finding.message}`)
  );
}

function emptyReport(command, root, dryRun = false) {
  return {
    command,
    root,
    dryRun,
    created: [],
    skipped: [],
    updated: [],
    unchanged: [],
    preserved: [],
    manualActions: [],
    warnings: [],
    schemaWarnings: []
  };
}

async function copyIfAbsent(root, source, target, report) {
  const targetPath = path.join(root, fromPosix(target));
  if (await exists(targetPath)) {
    report.skipped.push(target);
    return;
  }

  const content = await readPackageText(source);
  await writeText(targetPath, content);
  report.created.push(target);
}

async function writeManagedFile(root, target, { dryRun, report }) {
  const sourceContent = await readPackageText(target);
  const targetPath = path.join(root, fromPosix(target));
  const current = await readOptionalText(targetPath);

  if (report.command === 'init' && current !== null) {
    report.skipped.push(target);
    return;
  }

  if (current === sourceContent) {
    report.unchanged.push(target);
    return;
  }

  if (!dryRun) {
    await writeText(targetPath, sourceContent);
  }

  if (current === null && report.command === 'init') {
    report.created.push(target);
  } else {
    report.updated.push(target);
  }
}

async function mergeOrSeedCopilot(root, { dryRun, init, report }) {
  const target = COPILOT_INSTRUCTIONS;
  const targetPath = path.join(root, fromPosix(target));
  const template = await readPackageText('templates/copilot-instructions.md.template');
  const block = `${FRAMEWORK_BLOCK_BEGIN}\n${template.trimEnd()}\n${FRAMEWORK_BLOCK_END}\n`;
  const current = await readOptionalText(targetPath);

  if (init) {
    if (current !== null) {
      report.skipped.push(target);
      return;
    }
    await writeText(targetPath, `${block}`);
    report.created.push(target);
    return;
  }

  const next = mergeFrameworkBlock(current, block);
  if (current === next) {
    report.unchanged.push(target);
    report.preserved.push(target);
    return;
  }

  if (!dryRun) {
    await writeText(targetPath, next);
  }
  report.updated.push(target);
  if (current !== null) {
    report.preserved.push(`${target} existing content`);
  }
}

function mergeFrameworkBlock(current, block) {
  if (current === null) {
    return block;
  }

  const begin = current.indexOf(FRAMEWORK_BLOCK_BEGIN);
  const end = current.indexOf(FRAMEWORK_BLOCK_END);
  if (begin !== -1 && end !== -1 && end > begin) {
    const afterEnd = end + FRAMEWORK_BLOCK_END.length;
    return `${current.slice(0, begin)}${block.trimEnd()}${current.slice(afterEnd)}`.replace(/\s*$/, '\n');
  }

  return `${current.trimEnd()}\n\n${block}`;
}

async function ensureDirectory(root, relative, report) {
  const dirPath = path.join(root, fromPosix(relative));
  if (await exists(dirPath)) {
    report.skipped.push(relative);
    return;
  }

  await mkdir(dirPath, { recursive: true });
  report.created.push(relative);
}

async function ensureGitignore(root, { dryRun, report }) {
  const target = '.gitignore';
  const filePath = path.join(root, target);
  const current = await readOptionalText(filePath);
  const entry = '.ai_local/';

  if (current?.split(/\r?\n/).some((line) => line.trim() === entry)) {
    if (report.command === 'init') {
      report.skipped.push(target);
    } else {
      report.unchanged.push(target);
    }
    return;
  }

  const next = current === null || current.length === 0 ? `${entry}\n` : `${current.replace(/\s*$/, '\n')}${entry}\n`;
  if (!dryRun) {
    await writeText(filePath, next);
  }

  if (report.command === 'init' && current === null) {
    report.created.push(target);
  } else {
    report.updated.push(target);
  }
}

async function writeStamp(root, { dryRun, report }) {
  const targetPath = path.join(root, STAMP_FILE);
  const current = await readOptionalText(targetPath);
  const next = createStamp();

  if (report.command === 'init' && current !== null) {
    report.skipped.push(STAMP_FILE);
    return;
  }

  if (current === next) {
    report.unchanged.push(STAMP_FILE);
    return;
  }

  if (!dryRun) {
    await writeText(targetPath, next);
  }

  if (report.command === 'init' && current === null) {
    report.created.push(STAMP_FILE);
  } else {
    report.updated.push(STAMP_FILE);
  }
}

async function readConsumerStamp(root) {
  try {
    return { status: 'ok', data: JSON.parse(await readFile(path.join(root, STAMP_FILE), 'utf8')) };
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return { status: 'missing' };
    }
    return { status: 'invalid', message: error.message };
  }
}

function addSchemaWarning(stamp, report) {
  if (!stamp?.schemaVersion) {
    report.schemaWarnings.push(`schema version missing from ${STAMP_FILE}; writing schema ${SCHEMA_VERSION}.`);
    return;
  }

  try {
    if (compareSchemaCompatibility(stamp.schemaVersion, SCHEMA_VERSION) < 0) {
      report.schemaWarnings.push(
        `schema ${stamp.schemaVersion} is behind ${SCHEMA_VERSION}; review migration notes after update.`
      );
    }
  } catch {
    report.schemaWarnings.push(`schema version ${stamp.schemaVersion} is invalid; writing schema ${SCHEMA_VERSION}.`);
  }
}

async function readPackageText(relative) {
  return await readFile(path.join(PACKAGE_ROOT, fromPosix(relative)), 'utf8');
}

async function readOptionalText(filePath) {
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

async function writeText(filePath, content) {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, content, 'utf8');
}

async function exists(filePath) {
  try {
    await stat(filePath);
    return true;
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return false;
    }
    throw error;
  }
}

function printHeader(command, report) {
  console.log(`AI Context Framework ${command}${report.dryRun ? ' (dry-run)' : ''}`);
  console.log(`root: ${report.root}`);
  console.log(`framework: ${FRAMEWORK_VERSION}`);
  console.log(`schema: ${SCHEMA_VERSION}`);
}

function printList(label, values) {
  const sorted = [...new Set(values)].sort();
  console.log(`${label}: ${sorted.length}`);
  for (const value of sorted) {
    console.log(`  - ${value}`);
  }
}

function fromPosix(relative) {
  return relative.split('/').join(path.sep);
}
