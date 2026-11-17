export const SITE_NAME = "Content Scheduler";
export const COMPANY_NAME = "Content Scheduler";
/** Rellénalo con los datos reales de tu empresa antes de publicar los términos. */
export const COMPANY_REGISTRATION_NUMBER = "";
export const COMPANY_REGISTERED_ADDRESS = "";
export const DEFAULT_SITE_URL = "https://contentscheduler.vercel.app";
export const HOSTED_APP_URL = DEFAULT_SITE_URL;
export const GITHUB_URL = "https://github.com/k2nchin/Content-Scheduler/tree/main/clipper-web";
/** The hosted MCP server's Streamable HTTP endpoint (legacy SSE clients use `/sse`). */
export const HOSTED_MCP_URL = "";

/** MCP endpoint shown in setup snippets; self-hosters set NEXT_PUBLIC_MCP_URL. */
export function getMcpUrl() {
  const value = process.env.NEXT_PUBLIC_MCP_URL?.trim();
  if (!value) return HOSTED_MCP_URL;
  try {
    return new URL(value).toString().replace(/\/$/, "");
  } catch {
    return HOSTED_MCP_URL;
  }
}
/** Vacío hasta que la app esté en la App Store: los enlaces a la tienda se ocultan solos. */
export const APP_STORE_ID = "";
export const APP_STORE_URL = APP_STORE_ID ? `https://apps.apple.com/us/app/content-scheduler/id${APP_STORE_ID}` : "";
export const PRODUCT_HUNT_URL = "";
/** Product Hunt's launch badge; it shows the live upvote count once the launch is up. */
export const PRODUCT_HUNT_BADGE_URL = "";

/** Opens the App Store's offer-code redemption for a creator's custom code (the "Creator offer"). */
export function appStoreRedeemUrl(code: string) {
  return `https://apps.apple.com/redeem?ctx=offercodes&id=${APP_STORE_ID}&code=${encodeURIComponent(code.toUpperCase())}`;
}

export function getSiteUrl() {
  try {
    return new URL(process.env.NEXT_PUBLIC_APP_URL || DEFAULT_SITE_URL).origin;
  } catch {
    return DEFAULT_SITE_URL;
  }
}
