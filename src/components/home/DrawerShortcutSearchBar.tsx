import { useEffect, useMemo, useRef, useState, type RefObject } from 'react';
import { RiDashboardFill } from '@/icons/ri-compat';
import { useFrostedSurfaceTheme } from '@/components/frosted/useFrostedSurfaceTheme';
import {
  FloatingSearchDock,
  resolveFloatingSearchMotionPhase,
} from '@/components/home/FloatingSearchDock';
import { SearchField } from '@/components/search/SearchField';
import { useStableElementState } from '@/hooks/useStableElementState';

type DrawerShortcutSearchBarProps = {
  inputRef: RefObject<HTMLInputElement | null>;
  value: string;
  onValueChange: (value: string) => void;
  className?: string;
  height: number;
  horizontalPadding?: number;
  maxWidthPx?: number;
  reduceMotionVisuals?: boolean;
  interactionDisabled?: boolean;
  withDock?: boolean;
};

export function DrawerShortcutSearchBar({
  inputRef,
  value,
  onValueChange,
  className,
  height,
  horizontalPadding = 24,
  maxWidthPx,
  reduceMotionVisuals = false,
  interactionDisabled = false,
  withDock = true,
}: DrawerShortcutSearchBarProps) {
  const [isFocused, setIsFocused] = useState(false);
  const deferredSyncTimerRef = useRef<number | null>(null);
  const [surfaceNode, attachSurfaceRef] = useStableElementState<HTMLDivElement>();
  const { theme } = useFrostedSurfaceTheme({
    surfaceNode,
    surfaceTone: 'default',
  });
  const hasValue = value.trim().length > 0;
  const motionPhase = resolveFloatingSearchMotionPhase({
    isFocused,
    hasValue,
  });

  useEffect(() => {
    const syncFromInput = () => {
      if (deferredSyncTimerRef.current !== null) {
        window.clearTimeout(deferredSyncTimerRef.current);
        deferredSyncTimerRef.current = null;
      }

      const input = inputRef.current;
      const nextFocused = Boolean(input && document.activeElement === input);
      setIsFocused((current) => (current === nextFocused ? current : nextFocused));
    };

    const scheduleSyncFromInput = () => {
      if (deferredSyncTimerRef.current !== null) {
        window.clearTimeout(deferredSyncTimerRef.current);
      }
      deferredSyncTimerRef.current = window.setTimeout(syncFromInput, 0);
    };

    syncFromInput();
    document.addEventListener('focusin', syncFromInput, true);
    document.addEventListener('focusout', scheduleSyncFromInput, true);

    return () => {
      if (deferredSyncTimerRef.current !== null) {
        window.clearTimeout(deferredSyncTimerRef.current);
        deferredSyncTimerRef.current = null;
      }
      document.removeEventListener('focusin', syncFromInput, true);
      document.removeEventListener('focusout', scheduleSyncFromInput, true);
    };
  }, [inputRef]);

  const leadingAccessory = useMemo(() => (
    <span className="relative flex size-5 shrink-0 items-center justify-center">
      <RiDashboardFill className="size-[18px]" />
    </span>
  ), []);

  const content = (
    <div
      ref={attachSurfaceRef}
      className="relative content-stretch flex w-full items-start"
      data-search-ui="true"
      aria-disabled={interactionDisabled}
    >
      <div className="relative flex-1 min-w-0">
        <SearchField
          value={value}
          onValueChange={(nextValue) => {
            onValueChange(nextValue);
          }}
          inputRef={inputRef}
          onFocusContainer={() => inputRef.current?.focus()}
          onOpenHistory={() => {}}
          onClear={() => {
            onValueChange('');
          }}
          placeholder="搜索快捷方式"
          disablePlaceholderAnimation={true}
          lightweightPlaceholderAnimation={true}
          theme={theme}
          height={height}
          horizontalPadding={horizontalPadding}
          surfaceTone="default"
          interactionDisabled={interactionDisabled}
          searchEngine="system"
          onEngineSelect={() => {}}
          dropdownOpen={false}
          onEngineOpenChange={() => {}}
          showEngineSwitcher={false}
          leadingAccessory={leadingAccessory}
          panelExpanded={false}
        />
      </div>
    </div>
  );

  if (!withDock) {
    return <div className={className}>{content}</div>;
  }

  return (
    <FloatingSearchDock
      className={className}
      phase={motionPhase}
      reduceMotionVisuals={reduceMotionVisuals}
      maxWidthPx={maxWidthPx}
    >
      {content}
    </FloatingSearchDock>
  );
}
