const mime = [
  'application/json',
  'application/xml',
  'application/x-www-form-urlencoded',
  'multipart/form-data',
  'text/plain',
  'text/html',
  'application/octet-stream',
]

/** Common request header names and typical values (for the Headers suggestions). */
export const headerValues: Record<string, string[]> = {
  Accept: ['*/*', ...mime],
  'Accept-Charset': ['utf-8'],
  'Accept-Encoding': ['gzip, deflate, br', 'gzip', 'identity'],
  'Accept-Language': ['cs-CZ,cs;q=0.9,en;q=0.8', 'en-US,en;q=0.9'],
  Authorization: ['Bearer {{token}}', 'Basic '],
  'Cache-Control': ['no-cache', 'no-store', 'max-age=0'],
  Connection: ['keep-alive', 'close'],
  'Content-Encoding': ['gzip', 'deflate', 'br'],
  'Content-Type': [...mime, 'application/json; charset=utf-8'],
  Cookie: [],
  DNT: ['1'],
  'If-Match': [],
  'If-Modified-Since': [],
  'If-None-Match': [],
  Origin: [],
  Pragma: ['no-cache'],
  Range: ['bytes=0-'],
  Referer: [],
  'User-Agent': ['MinorREST'],
  'X-API-Key': ['{{apiKey}}'],
  'X-Correlation-ID': ['{{$uuid}}'],
  'X-Request-ID': ['{{$uuid}}'],
  'X-Forwarded-For': [],
  'X-Requested-With': ['XMLHttpRequest'],
}

export const headerNames = Object.keys(headerValues)

export function valuesFor(name: string): string[] {
  const k = headerNames.find((n) => n.toLowerCase() === name.trim().toLowerCase())
  return k ? headerValues[k] : []
}
