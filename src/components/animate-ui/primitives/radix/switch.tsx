import * as React from "react";
import { cn } from "@/components/ui/utils";

type SwitchProps = Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, "onChange" | "value"> & {
  checked?: boolean;
  defaultChecked?: boolean;
  onCheckedChange?: (checked: boolean) => void;
  value?: string;
};

function Switch({ checked, defaultChecked = false, onCheckedChange, className, children, disabled, ...props }: SwitchProps) {
  const controlled = checked !== undefined;
  const [internalChecked, setInternalChecked] = React.useState(defaultChecked);
  const resolvedChecked = controlled ? Boolean(checked) : internalChecked;

  const toggle = () => {
    if (disabled) return;
    const nextChecked = !resolvedChecked;
    if (!controlled) {
      setInternalChecked(nextChecked);
    }
    onCheckedChange?.(nextChecked);
  };

  return (
    <button
      type="button"
      role="switch"
      aria-checked={resolvedChecked}
      data-slot="switch"
      data-state={resolvedChecked ? "checked" : "unchecked"}
      disabled={disabled}
      className={cn(
        "relative inline-flex h-6 w-10 shrink-0 items-center justify-start rounded-full border border-transparent p-0.5 outline-none transition-colors data-[state=checked]:justify-end data-[state=checked]:bg-primary data-[state=unchecked]:bg-input focus-visible:ring-2 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:opacity-50",
        className,
      )}
      {...props}
      onClick={(event) => {
        props.onClick?.(event);
        if (!event.defaultPrevented) {
          toggle();
        }
      }}
    >
      {children ?? <SwitchThumb />}
    </button>
  );
}

type SwitchThumbProps = React.HTMLAttributes<HTMLSpanElement> & {
  pressedAnimation?: unknown;
};

function SwitchThumb({ className, pressedAnimation: _pressedAnimation, ...props }: SwitchThumbProps) {
  return (
    <span
      data-slot="switch-thumb"
      className={cn("block h-full aspect-square rounded-full bg-white/95 shadow-[0_1px_2px_rgba(15,23,42,0.14)] dark:bg-white/90 dark:shadow-[0_1px_2px_rgba(0,0,0,0.28)]", className)}
      {...props}
    />
  );
}

type SwitchIconPosition = "left" | "right" | "thumb";

type SwitchIconProps = React.ComponentPropsWithoutRef<"div"> & {
  position: SwitchIconPosition;
};

function SwitchIcon({ position: _position, ...props }: SwitchIconProps) {
  return <div {...props} />;
}

function useSwitch() {
  return {
    isChecked: false,
    setIsChecked: () => {},
    isPressed: false,
    setIsPressed: () => {},
  };
}

export {
  Switch,
  SwitchThumb,
  SwitchIcon,
  useSwitch,
  type SwitchProps,
  type SwitchThumbProps,
  type SwitchIconProps,
  type SwitchIconPosition,
};
