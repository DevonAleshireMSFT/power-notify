/**
 * Parse the leading flat YAML front-matter block from Markdown text.
 *
 * This intentionally supports only the framework contract shape:
 *   key: value
 * plus blank lines and comments. It is not a general-purpose YAML parser.
 *
 * @param {string} text Markdown file content.
 * @returns {{data: Record<string, string>, body: string} | {data: null}}
 */
export function parseFrontmatter(text) {
  const normalized = text.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  const lines = normalized.split('\n');

  if (lines[0]?.trim() !== '---') {
    return { data: null };
  }

  const closingIndex = lines.findIndex((line, index) => index > 0 && line.trim() === '---');
  if (closingIndex === -1) {
    return { data: null };
  }

  const data = {};
  for (const rawLine of lines.slice(1, closingIndex)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }

    const separatorIndex = line.indexOf(':');
    if (separatorIndex <= 0) {
      continue;
    }

    const key = line.slice(0, separatorIndex).trim();
    const value = line.slice(separatorIndex + 1).trim();
    if (key) {
      data[key] = value;
    }
  }

  return {
    data,
    body: lines.slice(closingIndex + 1).join('\n')
  };
}
