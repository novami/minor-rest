/** Lowercase without diacritics, for accent- and case-insensitive matching. */
export function fold(s: string): string {
  return s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
}
