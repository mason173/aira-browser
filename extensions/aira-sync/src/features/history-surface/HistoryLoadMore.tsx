import { useEffect, useRef } from 'react';

/** A visible fallback also makes older entries reachable without a scroll event. */
export function HistoryLoadMore({ hasMore, loading, loadMore, language }: {
  hasMore: boolean; loading: boolean; loadMore: () => void; language: string;
}) {
  const button = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!hasMore || loading || !button.current || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(entries => {
      if (entries.some(entry => entry.isIntersecting)) loadMore();
    }, { rootMargin: '240px' });
    observer.observe(button.current);
    return () => observer.disconnect();
  }, [hasMore, loading, loadMore]);
  if (!hasMore) return null;
  const chinese = language.toLowerCase().startsWith('zh');
  return <button ref={button} type="button" disabled={loading} onClick={loadMore}
    style={{ display: 'block', margin: '12px auto', padding: '8px 16px', color: 'inherit', background: 'transparent', border: '1px solid currentColor', borderRadius: 4 }}>
    {loading ? (chinese ? '正在加载…' : 'Loading…') : (chinese ? '加载更多' : 'Load more')}
  </button>;
}
