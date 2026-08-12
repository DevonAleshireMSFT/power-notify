import fs from 'node:fs';
import path from 'node:path';

const DEFAULT_FILES = ['registry.md', 'CONTRIBUTING.md', 'README.md'];
const EXTERNAL_TARGET = /^(?:https?:|mailto:)/i;
// GitHub Pages builds this repository from ./docs (see .github/workflows/pages.yml).
// Repositories without docs/_config.yml skip publish-root-specific checks.
const DEFAULT_PUBLISH_ROOT = 'docs';

function posixPath(filePath) {
  return filePath.split(path.sep).join('/');
}

function fileLabel(root, filePath) {
  return posixPath(path.relative(root, filePath)) || path.basename(filePath);
}

function readMarkdownFiles(root) {
  const files = [];
  const orgDir = path.join(root, 'org');
  const publishRoot = findPublishRoot(root);

  if (fs.existsSync(orgDir) && fs.statSync(orgDir).isDirectory()) {
    for (const entry of fs.readdirSync(orgDir, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith('.md')) {
        files.push(path.join(orgDir, entry.name));
      }
    }
  }

  for (const file of DEFAULT_FILES) {
    const resolved = path.join(root, file);
    if (fs.existsSync(resolved) && fs.statSync(resolved).isFile()) {
      files.push(resolved);
    }
  }

  if (publishRoot) {
    files.push(...readMarkdownFilesRecursive(publishRoot));
  }

  return files.sort((a, b) => fileLabel(root, a).localeCompare(fileLabel(root, b)));
}

function readMarkdownFilesRecursive(directory) {
  const files = [];

  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const resolved = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...readMarkdownFilesRecursive(resolved));
    } else if (entry.isFile() && entry.name.endsWith('.md')) {
      files.push(resolved);
    }
  }

  return files;
}

function findPublishRoot(root) {
  const publishRoot = path.join(root, DEFAULT_PUBLISH_ROOT);
  const jekyllConfig = path.join(publishRoot, '_config.yml');
  return fs.existsSync(jekyllConfig) && fs.statSync(jekyllConfig).isFile() ? publishRoot : null;
}

function stripFencedCode(markdown) {
  const lines = markdown.split(/\r?\n/);
  let inFence = false;

  return lines.map((line) => {
    if (/^\s*(```|~~~)/.test(line)) {
      inFence = !inFence;
      return '';
    }

    return inFence ? '' : line;
  }).join('\n');
}

function splitTarget(rawTarget) {
  const hashIndex = rawTarget.indexOf('#');

  if (hashIndex === -1) {
    return { pathname: rawTarget, fragment: '' };
  }

  return {
    pathname: rawTarget.slice(0, hashIndex),
    fragment: rawTarget.slice(hashIndex + 1),
  };
}

function decodePathname(pathname) {
  try {
    return decodeURIComponent(pathname);
  } catch {
    return pathname;
  }
}

export function githubSlug(heading) {
  // GitHub heading IDs: lowercase, strip punctuation (including em/en dashes),
  // preserve spaces and hyphens, then replace each space with one hyphen.
  // Do not collapse consecutive hyphens; duplicate headings get -n suffixes.
  return heading
    .trim()
    .toLowerCase()
    .replace(/<[^>]*>/g, '')
    .replace(/[`*_~]/g, '')
    .replace(/[^\p{L}\p{N} -]/gu, '')
    .trim()
    .replace(/ /g, '-');
}

function collectAnchors(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const anchors = new Set();
  const seen = new Map();

  for (const line of stripFencedCode(content).split('\n')) {
    const explicitAnchor = /^\s*\{:[^}]*#([\w-]+)[^}]*\}\s*$/.exec(line);
    if (explicitAnchor) {
      anchors.add(explicitAnchor[1].toLowerCase());
      continue;
    }

    const match = /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line);
    if (!match) {
      continue;
    }

    const base = githubSlug(match[2]);
    if (!base) {
      continue;
    }

    const count = seen.get(base) ?? 0;
    seen.set(base, count + 1);
    anchors.add(count === 0 ? base : `${base}-${count}`);
  }

  return anchors;
}

function parseLinks(markdown) {
  const content = stripFencedCode(markdown);
  const links = [];
  const definitions = new Map();
  const lines = content.split('\n');

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const lineNumber = index + 1;
    const definition = /^\s{0,3}\[([^\]]+)\]:\s*(\S*)/.exec(line);

    if (definition) {
      const id = definition[1].trim().toLowerCase();
      const target = definition[2].trim();
      definitions.set(id, { target, line: lineNumber });
      links.push({ kind: 'reference-definition', target, line: lineNumber, text: definition[1] });
    }

    const inlinePattern = /(?<!!)\[[^\]\n]*\]\(([^)\s]*)(?:\s+"[^"]*")?\)/g;
    for (const match of line.matchAll(inlinePattern)) {
      links.push({ kind: 'inline', target: match[1].trim(), line: lineNumber, text: match[0] });
    }
  }

  for (let index = 0; index < lines.length; index += 1) {
    const lineNumber = index + 1;
    const fullPattern = /(?<!!)\[([^\]\n]+)\]\[([^\]\n]*)\]/g;
    for (const match of lines[index].matchAll(fullPattern)) {
      const id = (match[2] || match[1]).trim().toLowerCase();
      if (!definitions.has(id)) {
        links.push({ kind: 'reference-use', target: '', line: lineNumber, text: match[0], missingReference: id });
      }
    }
  }

  return links;
}

function ensureFileResult(results, root, filePath) {
  const label = fileLabel(root, filePath);
  let result = results.get(label);

  if (!result) {
    result = { file: label, errors: [], warnings: [], checked: 0 };
    results.set(label, result);
  }

  return result;
}

function resolveTargetFile(sourceFile, target) {
  const { pathname, fragment } = splitTarget(target);
  const targetPath = pathname === ''
    ? sourceFile
    : path.resolve(path.dirname(sourceFile), decodePathname(pathname));

  return { targetPath, fragment };
}

function isInsidePath(parentPath, childPath) {
  const relative = path.relative(parentPath, childPath);
  return relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative));
}

function resolveExistingTargetPath(targetPath, allowPermalink = false) {
  if (fs.existsSync(targetPath)) {
    return targetPath;
  }

  if (!allowPermalink) {
    return targetPath;
  }

  const markdownPath = `${targetPath}.md`;
  if (fs.existsSync(markdownPath)) {
    return markdownPath;
  }

  const indexPath = path.join(targetPath, 'index.md');
  if (fs.existsSync(indexPath)) {
    return indexPath;
  }

  return targetPath;
}

function validateTarget({ root, publishRoot, sourceFile, target, line, text, result, anchorCache }) {
  result.checked += 1;

  if (!target) {
    result.errors.push({ line, target, message: 'Empty link target', text });
    return;
  }

  if (EXTERNAL_TARGET.test(target)) {
    return;
  }

  const { targetPath, fragment } = resolveTargetFile(sourceFile, target);
  const sourceInPublishRoot = publishRoot && isInsidePath(publishRoot, sourceFile);

  if (
    sourceInPublishRoot
    && !isInsidePath(publishRoot, targetPath)
  ) {
    result.errors.push({
      line,
      target,
      message: `Link escapes the GitHub Pages publish root (${posixPath(path.relative(root, publishRoot))}/) and will 404 on the published site; use an absolute https://github.com/<owner>/<repo>/blob/<branch>/<path> URL instead.`,
      text,
    });
    return;
  }

  const resolvedTargetPath = resolveExistingTargetPath(targetPath, sourceInPublishRoot);

  if (!fs.existsSync(resolvedTargetPath)) {
    result.errors.push({
      line,
      target,
      message: `Target file does not exist: ${fileLabel(root, resolvedTargetPath)}`,
      text,
    });
    return;
  }

  const targetStat = fs.statSync(resolvedTargetPath);
  if (targetStat.isDirectory()) {
    return;
  }

  if (!targetStat.isFile()) {
    result.errors.push({
      line,
      target,
      message: `Target file does not exist: ${fileLabel(root, resolvedTargetPath)}`,
      text,
    });
    return;
  }

  if (fragment) {
    const normalizedFragment = decodePathname(fragment).trim().toLowerCase();
    if (!normalizedFragment) {
      result.warnings.push({ line, target, message: 'Empty anchor fragment', text });
      return;
    }

    const cacheKey = resolvedTargetPath;
    if (!anchorCache.has(cacheKey)) {
      anchorCache.set(cacheKey, collectAnchors(resolvedTargetPath));
    }

    if (!anchorCache.get(cacheKey).has(normalizedFragment)) {
      result.warnings.push({ line, target, message: `Anchor not found: #${fragment}`, text });
    }
  }
}

export function checkLinks(root = process.cwd()) {
  const resolvedRoot = path.resolve(root);
  const publishRoot = findPublishRoot(resolvedRoot);
  const files = readMarkdownFiles(resolvedRoot);
  const results = new Map();
  const anchorCache = new Map();

  for (const sourceFile of files) {
    const result = ensureFileResult(results, resolvedRoot, sourceFile);
    const content = fs.readFileSync(sourceFile, 'utf8');
    const links = parseLinks(content);

    for (const link of links) {
      if (link.missingReference) {
        result.checked += 1;
        result.errors.push({
          line: link.line,
          target: link.missingReference,
          message: `Reference link is not defined: [${link.missingReference}]`,
          text: link.text,
        });
        continue;
      }

      validateTarget({
        root: resolvedRoot,
        publishRoot,
        sourceFile,
        target: link.target,
        line: link.line,
        text: link.text,
        result,
        anchorCache,
      });
    }
  }

  const fileResults = [...results.values()];
  const summary = fileResults.reduce((acc, result) => {
    acc.files += 1;
    acc.links += result.checked;
    acc.errors += result.errors.length;
    acc.warnings += result.warnings.length;
    return acc;
  }, { files: 0, links: 0, errors: 0, warnings: 0 });

  return { root: resolvedRoot, files: fileResults, summary };
}

function formatIssue(icon, issue) {
  return `  ${icon} L${issue.line}: ${issue.message}${issue.target ? ` (${issue.target})` : ''}`;
}

export function formatReport(report) {
  const lines = [];

  for (const file of report.files) {
    const icon = file.errors.length > 0 ? '❌' : file.warnings.length > 0 ? '⚠️' : '✅';
    lines.push(`${icon} ${file.file} (${file.checked} links checked)`);

    for (const warning of file.warnings) {
      lines.push(formatIssue('⚠️', warning));
    }

    for (const error of file.errors) {
      lines.push(formatIssue('❌', error));
    }
  }

  lines.push(`Summary: ${report.summary.files} files, ${report.summary.links} links, ${report.summary.warnings} warnings, ${report.summary.errors} errors`);
  return lines.join('\n');
}

function parseArgs(argv) {
  const options = { root: process.cwd(), strict: false };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];

    if (arg === '--strict') {
      options.strict = true;
    } else if (arg === '--root') {
      const value = argv[index + 1];
      if (!value) {
        throw new Error('--root requires a directory');
      }
      options.root = value;
      index += 1;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

function fileUrlToPath(fileUrl) {
  const pathname = decodeURIComponent(new URL(fileUrl).pathname);
  return process.platform === 'win32' && /^\/[A-Za-z]:/.test(pathname) ? pathname.slice(1) : pathname;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileUrlToPath(import.meta.url));

if (isMain) {
  try {
    const options = parseArgs(process.argv.slice(2));
    const report = checkLinks(options.root);
    console.log(formatReport(report));

    const shouldFail = report.summary.errors > 0 || (options.strict && report.summary.warnings > 0);
    process.exitCode = shouldFail ? 1 : 0;
  } catch (error) {
    console.error(`❌ ${error.message}`);
    process.exitCode = 1;
  }
}
