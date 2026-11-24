const ANSI_PATTERN = /\x1b(?:\[[0-9;]*[A-Za-z]|\][^\x07\x1b]*(?:\x07|\x1b[\\]))/g;
const CONTROL_CHARS = /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/g;

/** Normaliza texto derivado de la página antes de que alcance diffs o reporters. */
export function sanitizePageDerivedText(text: string, maxLength = 2000): string {
  return text
    .replace(ANSI_PATTERN, '')
    .replace(CONTROL_CHARS, '')
    .replace(/\r\n?|\n/g, '\\n')
    .slice(0, maxLength);
}
