/** Supports Chromium callbacks and Firefox's Promise-returning implementation. */
export function callBrowserHistoryApi<T>(
  invoke: (callback: (value: T) => void) => unknown,
): Promise<T> {
  return new Promise((resolve, reject) => {
    let settled = false;
    const finish = (value: T) => {
      if (settled) return;
      settled = true;
      const error = globalThis.chrome?.runtime?.lastError;
      if (error) reject(new Error(error.message || 'Unable to read native browser history.'));
      else resolve(value);
    };
    const fail = (error: unknown) => {
      if (settled) return;
      settled = true;
      reject(error);
    };
    try {
      const result = invoke(finish);
      if (result && typeof (result as Promise<T>).then === 'function') {
        void (result as Promise<T>).then(finish, fail);
      }
    } catch (error) {
      fail(error);
    }
  });
}
