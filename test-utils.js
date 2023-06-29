export function base64encode(str) {
  return Buffer.from(str, 'utf8').toString('base64');
}
