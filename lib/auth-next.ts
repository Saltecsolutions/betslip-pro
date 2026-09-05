/** Only application-owned routes may be used after authentication. */
export function safeNext(value: string | null | undefined): string {
  if (!value || /[\\\r\n]/.test(value) || !value.startsWith('/') || value.startsWith('//')) return '/dashboard';
  const [path, query] = value.split('?');
  if (!/^\/(?:dashboard|account\/privacy|predictions(?:\/[0-9a-f-]{36})?|tipsters(?:\/[0-9a-f-]{36})?|tipster(?:\/profile|\/predictions\/new)?|purchases(?:\/[0-9a-f-]{36}\/payment)?|notifications|protection|admin(?:\/payments|\/trust|\/compliance|\/partnerships|\/alerts)?|advertise\/partnerships|advertiser)$/.test(path)) return '/dashboard';
  if (query && !(/^[^#]*$/.test(query) && (query === 'buy=1' || query === 'following=1'))) return path;
  return value;
}
