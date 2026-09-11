import { COLDLION_BASE_URL, MAX_ATTEMPTS, REQUEST_PAUSE_MS, REQUEST_TIMEOUT_MS, delay, fetchPage } from "./http.mjs";

export const MASTER_PAGE_SIZE = 2000;

export function masterUrl(endpoint, params = {}) {
  const url = new URL(`${COLDLION_BASE_URL}${endpoint}`);
  for (const [key, value] of Object.entries(params)) {
    if (value !== null && value !== undefined && value !== "") url.searchParams.set(key, String(value));
  }
  return url;
}

export async function fetchPagedMaster(endpoint, params, apiKey, options = {}) {
  const size = options.size ?? MASTER_PAGE_SIZE;
  const rows = [];
  let expectedTotal = null;
  for (let page = 0; ; page += 1) {
    if (options.requestGate) await options.requestGate();
    const { payload } = await fetchPage(masterUrl(endpoint, { ...params, page, size }), apiKey, options);
    if (!payload || Array.isArray(payload) || !Array.isArray(payload.content)) throw new Error(`${endpoint} did not return a paged envelope`);
    if (payload.number !== page || payload.numberOfElements !== payload.content.length) throw new Error(`${endpoint} returned inconsistent page ${page}`);
    if (payload.size > size) throw new Error(`${endpoint} returned an impossible page size`);
    if (expectedTotal === null) expectedTotal = payload.totalElements;
    if (payload.totalElements !== expectedTotal) throw new Error(`${endpoint} totalElements changed during the snapshot`);
    rows.push(...payload.content);
    if (payload.last === true) break;
    if (page + 1 >= Math.max(1, payload.totalPages) || page > 10_000) throw new Error(`${endpoint} paging did not terminate`);
  }
  if (rows.length !== expectedTotal) throw new Error(`${endpoint} snapshot is incomplete: ${rows.length} of ${expectedTotal}`);
  return rows;
}

export async function fetchArrayMaster(endpoint, params, apiKey, { fetchImpl = fetch, requestGate, timeoutMs = REQUEST_TIMEOUT_MS, pauseMs = REQUEST_PAUSE_MS } = {}) {
  let lastError;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    if (requestGate) await requestGate();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetchImpl(masterUrl(endpoint, params), { headers: { "X-API-Key": apiKey }, signal: controller.signal });
      const payload = JSON.parse(await response.text());
      if (!response.ok) {
        const error = new Error(`${endpoint} returned wire HTTP ${response.status}`);
        error.permanent = response.status >= 400 && response.status < 500 && ![408,429].includes(response.status);
        throw error;
      }
      if (!Array.isArray(payload)) throw new Error(`${endpoint} did not return the required plain array`);
      return payload;
    } catch (error) {
      lastError = error;
      if (error.permanent || attempt === MAX_ATTEMPTS) throw error;
      await delay(pauseMs);
    } finally { clearTimeout(timer); }
  }
  throw lastError;
}

export async function fetchMasterSpec(spec, params, apiKey, options = {}) {
  return spec.paged
    ? fetchPagedMaster(spec.endpoint, params, apiKey, options)
    : fetchArrayMaster(spec.endpoint, params, apiKey, options);
}
