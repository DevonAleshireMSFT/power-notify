import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseFrontmatter } from './lib/frontmatter.mjs';

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const CADENCE_MAX_AGE_DAYS = new Map([
  ['every-sprint', 14],
  ['monthly', 30],
  ['quarterly', 90],
  ['biannual', 180],
  ['annual', 365]
]);

/**
 * Evaluate whether an AI context file is past its review cadence.
 *
 * @param {{lastUpdated: string | Date, cadence: string, now?: string | Date}} input
 * @returns {{status: 'ok' | 'overdue' | 'unknown', ageDays: number | null, maxAgeDays: number | null, overdueByDays: number}}
 */
export function evaluateStaleness({ lastUpdated, cadence, now = new Date() }) {
  const updatedAt = parseDate(lastUpdated);
  const nowDate = parseDate(now);
  const maxAgeDays = CADENCE_MAX_AGE_DAYS.get(cadence) ?? null;
  const ageDays = updatedAt && nowDate ? Math.max(0, Math.floor((nowDate - updatedAt) / MS_PER_DAY)) : null;

  if (!updatedAt || !nowDate || maxAgeDays === null) {
    return { status: 'unknown', ageDays, maxAgeDays, overdueByDays: 0 };
  }

  const overdueByDays = Math.max(0, ageDays - maxAgeDays);
  return {
    status: overdueByDays > 0 ? 'overdue' : 'ok',
    ageDays,
    maxAgeDays,
    overdueByDays
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const result = await checkContext(options.root, new Date());

  if (options.json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    printReport(result);
  }

  if (options.ci && result.status === 'overdue') {
    process.exitCode = 1;
  }
}

async function checkContext(root, now) {
  const resolvedRoot = path.resolve(root);
  const contextPath = path.join(resolvedRoot, '.ai', 'context.md');

  try {
    const text = await readFile(contextPath, 'utf8');
    const parsed = parseFrontmatter(text);
    if (!parsed.data) {
      return unknownResult(resolvedRoot, 'Missing leading front-matter in .ai/context.md.');
    }

    const lastUpdated = parsed.data['last-updated'];
    const cadence = parsed.data['review-cadence'];
    const evaluation = evaluateStaleness({ lastUpdated, cadence, now });
    const result = {
      ...evaluation,
      root: resolvedRoot,
      contextPath,
      lastUpdated: lastUpdated ?? null,
      cadence: cadence ?? null,
      checkedAt: now.toISOString(),
      summary: ''
    };

    result.summary = summarize(result);
    if (result.status === 'unknown') {
      result.warning = unknownReason(lastUpdated, cadence);
    }

    return result;
  } catch (error) {
    if (error?.code === 'ENOENT') {
      return unknownResult(resolvedRoot, 'Missing .ai/context.md file.');
    }

    throw error;
  }
}

function unknownResult(root, warning) {
  const result = {
    status: 'unknown',
    ageDays: null,
    maxAgeDays: null,
    overdueByDays: 0,
    root,
    contextPath: path.join(root, '.ai', 'context.md'),
    lastUpdated: null,
    cadence: null,
    checkedAt: new Date().toISOString(),
    warning,
    summary: `Unknown: ${warning}`
  };
  return result;
}

function parseArgs(args) {
  const options = { root: process.cwd(), ci: false, json: false };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--root') {
      const value = args[index + 1];
      if (!value) {
        throw new Error('--root requires a directory');
      }
      options.root = value;
      index += 1;
    } else if (arg === '--ci') {
      options.ci = true;
    } else if (arg === '--json') {
      options.json = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function parseDate(value) {
  if (value instanceof Date) {
    return Number.isNaN(value.valueOf()) ? null : value;
  }

  if (typeof value !== 'string' || value.trim() === '') {
    return null;
  }

  const trimmed = value.trim();
  const date = /^\d{4}-\d{2}-\d{2}$/.test(trimmed)
    ? new Date(`${trimmed}T00:00:00.000Z`)
    : new Date(trimmed);

  return Number.isNaN(date.valueOf()) ? null : date;
}

function summarize(result) {
  if (result.status === 'ok') {
    return `Fresh: .ai/context.md is ${result.ageDays} day(s) old; max age for ${result.cadence} is ${result.maxAgeDays} day(s).`;
  }

  if (result.status === 'overdue') {
    return `Overdue: .ai/context.md is ${result.ageDays} day(s) old; max age for ${result.cadence} is ${result.maxAgeDays} day(s), overdue by ${result.overdueByDays} day(s).`;
  }

  return `Unknown: ${unknownReason(result.lastUpdated, result.cadence)}`;
}

function unknownReason(lastUpdated, cadence) {
  if (!lastUpdated) {
    return 'last-updated is missing.';
  }

  if (!parseDate(lastUpdated)) {
    return `last-updated is not a valid YYYY-MM-DD or ISO-8601 value: ${lastUpdated}`;
  }

  if (!cadence) {
    return 'review-cadence is missing.';
  }

  return `Unknown review-cadence: ${cadence}`;
}

function printReport(result) {
  if (result.status === 'ok') {
    console.log('✅ fresh');
  } else if (result.status === 'overdue') {
    console.log('⚠️ overdue');
  } else {
    console.log('❓ unknown');
    console.log(`Warning: ${result.warning ?? unknownReason(result.lastUpdated, result.cadence)}`);
  }

  console.log(result.summary);
}

const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';
const modulePath = fileURLToPath(import.meta.url);
if (invokedPath === modulePath) {
  main().catch((error) => {
    console.error(`✗ ${error.message}`);
    process.exitCode = 1;
  });
}
