import { type CSSProperties } from 'react';
import { useTheme } from 'next-themes';

export type FrostedBackdropPreset = 'default' | 'immersive-drawer';
export type FrostedSurfaceTone = 'default' | 'drawer';

export type FrostedBackdropProps = {
  surfaceNode: HTMLElement | null;
  preset?: FrostedBackdropPreset;
  tone?: FrostedSurfaceTone;
  radiusClassName?: string;
  lightModeOverlayOpacity?: number;
  darkModeOverlayOpacity?: number;
  modeOverlayTransitionMs?: number;
  showBorder?: boolean;
  fallbackSurfaceColor?: string;
  opacity?: number;
  transition?: string;
};

const DEFAULT_FALLBACK_SURFACE_COLOR = 'var(--frosted-ui-background, var(--background))';
const DRAWER_SURFACE_OVERLAY_STYLE: CSSProperties = {
  backgroundColor: 'var(--background)',
};

function buildSurfaceBorderStyle(): CSSProperties {
  return {
    border: '1px solid var(--border)',
  };
}

export function FrostedBackdrop({
  surfaceNode,
  preset = 'default',
  tone = 'default',
  radiusClassName = 'rounded-[999px]',
  lightModeOverlayOpacity = 0.9,
  darkModeOverlayOpacity = 0.65,
  modeOverlayTransitionMs = 220,
  showBorder = true,
  fallbackSurfaceColor = DEFAULT_FALLBACK_SURFACE_COLOR,
  opacity,
  transition,
}: FrostedBackdropProps) {
  const { resolvedTheme } = useTheme();
  const isDarkTheme = resolvedTheme === 'dark';
  void surfaceNode;

  if (preset === 'immersive-drawer') {
    return (
      <div
        data-slot="material-surface-backdrop"
        className="pointer-events-none absolute inset-0 z-0 overflow-hidden"
        style={{
          opacity,
          transition,
        }}
        aria-hidden="true"
      >
        <div
          className="absolute inset-0"
          style={{
            backgroundColor: isDarkTheme
              ? '#141820'
              : '#eef2f7',
          }}
        />
      </div>
    );
  }

  const drawerToneActive = tone === 'drawer';
  const modeOverlayStyle: CSSProperties = {
    backgroundColor: isDarkTheme
      ? `rgba(0, 0, 0, ${darkModeOverlayOpacity})`
      : `rgba(255, 255, 255, ${lightModeOverlayOpacity})`,
    transition: `background-color ${modeOverlayTransitionMs}ms cubic-bezier(0.22, 1, 0.36, 1)`,
  };

  if (drawerToneActive) {
    return (
      <div
        data-slot="material-surface-backdrop"
        className={`pointer-events-none absolute inset-0 z-0 overflow-hidden ${radiusClassName}`}
        aria-hidden="true"
      >
        <div className="absolute inset-0" style={DRAWER_SURFACE_OVERLAY_STYLE} />
        <div className="absolute inset-0" style={modeOverlayStyle} />
        {showBorder ? (
          <div
            className={`absolute inset-0 ${radiusClassName}`}
            style={buildSurfaceBorderStyle()}
          />
        ) : null}
      </div>
    );
  }

  return (
    <div
      data-slot="material-surface-backdrop"
      className={`pointer-events-none absolute inset-0 z-0 overflow-hidden ${radiusClassName}`}
      aria-hidden="true"
    >
      <div
        className="absolute inset-0"
        style={{
          backgroundColor: fallbackSurfaceColor,
        }}
      />
      <div className="absolute inset-0" style={modeOverlayStyle} />
      {showBorder ? (
        <div
          className={`absolute inset-0 ${radiusClassName}`}
          style={buildSurfaceBorderStyle()}
        />
      ) : null}
    </div>
  );
}
