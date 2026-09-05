export function safeNext(value: string | null | undefined): string {
  if (!value || !/^\/(predictions\/[0-9a-f-]{36}|dashboard|tipster|advertiser)(\?[^#]*)?$/.test(value) || /[\\\r\n]/.test(value)) return '/dashboard';
  return value;
}
