import { useCallback, useEffect, useRef, useState } from "react";
import { cn } from "@/components/ui/utils";

export interface ScrubberProps {
  label?: string;
  value?: number;
  defaultValue?: number;
  onValueChange?: (value: number) => void;
  onValueCommit?: (value: number) => void;
  onDragStart?: () => void;
  onDragEnd?: () => void;
  min?: number;
  max?: number;
  step?: number;
  decimals?: number;
  ticks?: number;
  className?: string;
  disabled?: boolean;
  showLabel?: boolean;
  showValue?: boolean;
  valueText?: string;
  trackHeight?: number;
}

const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), max);
const roundToStep = (value: number, step: number, min: number) => Math.round((value - min) / step) * step + min;

export default function Scrubber({
  label = "Value",
  value: controlledValue,
  defaultValue = 0,
  onValueChange,
  onValueCommit,
  onDragStart,
  onDragEnd,
  min = 0,
  max = 1,
  step = 0.01,
  decimals = 2,
  ticks = 9,
  className,
  disabled = false,
  showLabel = true,
  showValue = true,
  valueText,
  trackHeight = 52,
}: ScrubberProps) {
  const trackRef = useRef<HTMLDivElement>(null);
  const wasDraggingRef = useRef(false);
  const [internalValue, setInternalValue] = useState(defaultValue);
  const [isDragging, setIsDragging] = useState(false);
  const [isHovering, setIsHovering] = useState(false);
  const isControlled = controlledValue !== undefined;
  const value = isControlled ? controlledValue : internalValue;
  const range = max - min;
  const percentage = range > 0 ? ((value - min) / range) * 100 : 0;
  const isActive = !disabled && (isDragging || isHovering);

  const setValue = useCallback((newValue: number) => {
    if (disabled) return;
    const clamped = clamp(roundToStep(newValue, step, min), min, max);
    if (!isControlled) {
      setInternalValue(clamped);
    }
    onValueChange?.(clamped);
  }, [disabled, isControlled, max, min, onValueChange, step]);

  const commitValue = useCallback((newValue: number) => {
    if (disabled) return;
    const clamped = clamp(roundToStep(newValue, step, min), min, max);
    onValueCommit?.(clamped);
  }, [disabled, max, min, onValueCommit, step]);

  const getValueFromPointer = useCallback((clientX: number) => {
    const track = trackRef.current;
    if (!track) return value;
    const rect = track.getBoundingClientRect();
    const ratio = clamp((clientX - rect.left) / rect.width, 0, 1);
    return min + ratio * range;
  }, [min, range, value]);

  useEffect(() => {
    if (isDragging && !wasDraggingRef.current) {
      onDragStart?.();
    }
    if (!isDragging && wasDraggingRef.current) {
      commitValue(value);
      onDragEnd?.();
    }
    wasDraggingRef.current = isDragging;
  }, [commitValue, isDragging, onDragEnd, onDragStart, value]);

  const handleKeyDown = useCallback((event: React.KeyboardEvent) => {
    if (disabled) return;
    let nextValue: number | undefined;
    switch (event.key) {
      case "ArrowRight":
      case "ArrowUp":
        nextValue = value + step;
        break;
      case "ArrowLeft":
      case "ArrowDown":
        nextValue = value - step;
        break;
      case "Home":
        nextValue = min;
        break;
      case "End":
        nextValue = max;
        break;
      default:
        return;
    }
    event.preventDefault();
    setValue(nextValue);
    commitValue(nextValue);
  }, [commitValue, disabled, max, min, setValue, step, value]);

  const displayValueText = valueText ?? (decimals > 0 ? value.toFixed(decimals) : String(Math.round(value)));

  return (
    <div className={cn("relative w-full select-none", className)}>
      <div
        aria-disabled={disabled}
        aria-label={label}
        aria-valuemax={max}
        aria-valuemin={min}
        aria-valuenow={Number(value.toFixed(decimals))}
        data-slot="scrubber-track"
        className={cn(
          "relative overflow-hidden rounded-[999px] bg-muted outline-offset-2",
          disabled ? "cursor-not-allowed opacity-60" : "cursor-pointer",
        )}
        onKeyDown={handleKeyDown}
        onMouseEnter={() => setIsHovering(true)}
        onMouseLeave={() => setIsHovering(false)}
        onPointerDown={(event) => {
          if (disabled) return;
          event.preventDefault();
          trackRef.current?.setPointerCapture(event.pointerId);
          setIsDragging(true);
          setValue(getValueFromPointer(event.clientX));
        }}
        onPointerMove={(event) => {
          if (!isDragging || disabled) return;
          setValue(getValueFromPointer(event.clientX));
        }}
        onPointerUp={() => setIsDragging(false)}
        onPointerCancel={() => setIsDragging(false)}
        onLostPointerCapture={() => setIsDragging(false)}
        ref={trackRef}
        role="slider"
        style={{ height: trackHeight, touchAction: "none" }}
        tabIndex={disabled ? -1 : 0}
      >
        <div
          data-slot="scrubber-fill"
          className="pointer-events-none absolute inset-y-0 left-0 bg-primary"
          style={{
            borderRadius: 999,
            width: `${percentage}%`,
            transition: isDragging ? "none" : "width 150ms cubic-bezier(0.23, 1, 0.32, 1)",
          }}
        />
        {ticks > 0 ? (
          <div className="pointer-events-none absolute inset-0">
            {Array.from({ length: ticks }, (_, index) => {
              const position = ((index + 1) / (ticks + 1)) * 100;
              return (
                <div
                  data-slot="scrubber-tick"
                  className="absolute top-1/2 h-2 w-px -translate-x-1/2 -translate-y-1/2 rounded-full bg-white/70"
                  key={position}
                  style={{ left: `${position}%` }}
                />
              );
            })}
          </div>
        ) : null}
        <div
          className="pointer-events-none absolute top-1/2 z-[3] h-[22px] w-[4px] rounded-full bg-primary shadow-[0_0_0_1px_hsl(var(--background))]"
          style={{
            left: `${percentage}%`,
            opacity: isActive ? 0.95 : 0.45,
            transform: `translateX(-50%) translateY(-50%) scale(${isActive ? 1 : 0.7})`,
            transition: isDragging ? "none" : "left 150ms cubic-bezier(0.23, 1, 0.32, 1), opacity 150ms ease, transform 150ms ease",
          }}
        />
        {showLabel ? (
          <div data-slot="scrubber-label" className="pointer-events-none absolute top-1/2 left-4 z-[4] -translate-y-1/2 whitespace-nowrap text-sm text-white">
            {label}
          </div>
        ) : null}
        {showValue ? (
          <div
            data-slot="scrubber-value"
            className="pointer-events-none absolute top-1/2 right-3 z-[4] -translate-y-1/2 text-sm font-medium text-white"
            style={{ fontFamily: "ui-monospace, monospace", fontVariantNumeric: "tabular-nums" }}
          >
            {displayValueText}
          </div>
        ) : null}
      </div>
    </div>
  );
}
