import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { compareSemver, FRAMEWORK_VERSION, isSemver, SCHEMA_VERSION } from './lib/version.mjs';

const STAMP_FILE = '.ai-context.json';

export async function checkDrift(root = process.cwd()) {
  const resolvedRoot = path.resolve(root);
  const stampPath = path.join(resolvedRoot, STAMP_FILE);
  const stamp = await readStamp(stampPath);

  if (stamp.status === 'missing') {
    return {
      frameworkVersion: FRAMEWORK_VERSION,
      schemaVersion: SCHEMA_VERSION,
      stampFile: STAMP_FILE,
      findings: [
        {
          severity: 'INFO',
          message: `${STAMP_FILE} not found; treating this as an unmanaged / pre-CLI install.`
        }
      ]
    };
  }

  if (stamp.status === 'invalid') {
    return {
      frameworkVersion: FRAMEWORK_VERSION,
      schemaVersion: SCHEMA_VERSION,
      stampFile: STAMP_FILE,
      findings: [{ severity: 'WARNING', message: `${STAMP_FILE} could not be read: ${stamp.message}` }]
    };
  }

  const findings = [];
  addVersionFinding(findings, 'framework', stamp.data.frameworkVersion, FRAMEWORK_VERSION);
  addVersionFinding(findings, 'schema', stamp.data.schemaVersion, SCHEMA_VERSION);

  return {
    frameworkVersion: FRAMEWORK_VERSION,
    schemaVersion: SCHEMA_VERSION,
    stampFile: STAMP_FILE,
    findings
  };
}

function addVersionFinding(findings, label, installed, latest) {
  if (!isSemver(installed)) {
    findings.push({
      severity: 'WARNING',
      message: `Installed ${label} version is missing or invalid in ${STAMP_FILE}; expected semver like ${latest}.`
    });
    return;
  }

  const comparison = compareSemver(installed, latest);
  if (comparison < 0) {
    const hint =
      label === 'schema'
        ? 'Review the schema migration notes and run ai-context update.'
        : 'Run ai-context update to refresh framework-managed tooling.';
    findings.push({
      severity: 'WARNING',
      message: `Installed ${label} version ${installed} is behind latest ${latest}. ${hint}`
    });
  } else if (comparison > 0) {
    findings.push({
      severity: 'INFO',
      message: `Installed ${label} version ${installed} is newer than this framework package (${latest}); local tooling may be older than the consumer repo.`
    });
  }
}

async function readStamp(stampPath) {
  try {
    return { status: 'ok', data: JSON.parse(await readFile(stampPath, 'utf8')) };
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return { status: 'missing' };
    }

    return { status: 'invalid', message: error.message };
  }
}

export function printReport(report) {
  if (report.findings.length === 0) {
    console.log(`✅ AI Context Framework tooling is current (framework ${report.frameworkVersion}, schema ${report.schemaVersion}).`);
    return;
  }

  console.log(`AI Context Framework — drift check v${report.frameworkVersion} (schema ${report.schemaVersion})`);
  for (const finding of report.findings) {
    const icon = finding.severity === 'WARNING' ? '⚠️' : 'ℹ️';
    console.log(`${icon} ${finding.severity}: ${finding.message}`);
  }
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
    const report = await checkDrift(root);
    printReport(report);

    const hasDrift = report.findings.some((finding) => finding.severity === 'WARNING');
    process.exitCode = strict && hasDrift ? 1 : 0;
  } catch (error) {
    console.error(`❌ ${error.message}`);
    process.exitCode = 1;
  }
}

const currentFile = fileURLToPath(import.meta.url);
if (process.argv[1] && path.resolve(process.argv[1]) === currentFile) {
  await main();
}
