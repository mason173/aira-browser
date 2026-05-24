import * as React from "react";
import { cn } from "@/components/ui/utils";

type CheckboxValue = boolean | "indeterminate";

type CheckboxContextType = {
  checked: CheckboxValue;
};

const CheckboxContext = React.createContext<CheckboxContextType | null>(null);

function useCheckbox() {
  const context = React.useContext(CheckboxContext);
  return {
    isChecked: context?.checked ?? false,
    setIsChecked: () => {},
  };
}

type CheckboxProps = Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, "onChange" | "value"> & {
  checked?: CheckboxValue;
  defaultChecked?: CheckboxValue;
  onCheckedChange?: (checked: CheckboxValue) => void;
  required?: boolean;
  name?: string;
  value?: string;
};

function Checkbox({
  checked,
  defaultChecked = false,
  onCheckedChange,
  disabled,
  required,
  name,
  value = "on",
  className,
  children,
  ...props
}: CheckboxProps) {
  const controlled = checked !== undefined;
  const [internalChecked, setInternalChecked] = React.useState<CheckboxValue>(defaultChecked);
  const resolvedChecked = controlled ? checked : internalChecked;
  const checkedForForm = resolvedChecked === true;

  const toggle = () => {
    if (disabled) return;
    const nextChecked = resolvedChecked === true ? false : true;
    if (!controlled) {
      setInternalChecked(nextChecked);
    }
    onCheckedChange?.(nextChecked);
  };

  return (
    <CheckboxContext.Provider value={{ checked: resolvedChecked ?? false }}>
      <button
        type="button"
        role="checkbox"
        aria-checked={resolvedChecked === "indeterminate" ? "mixed" : Boolean(resolvedChecked)}
        data-slot="checkbox"
        data-state={resolvedChecked === "indeterminate" ? "indeterminate" : checkedForForm ? "checked" : "unchecked"}
        disabled={disabled}
        className={className}
        onClick={(event) => {
          props.onClick?.(event);
          if (!event.defaultPrevented) {
            toggle();
          }
        }}
        {...props}
      >
        {children}
      </button>
      {name ? (
        <input
          type="checkbox"
          tabIndex={-1}
          aria-hidden="true"
          className="hidden"
          name={name}
          value={value}
          checked={checkedForForm}
          required={required}
          readOnly
        />
      ) : null}
    </CheckboxContext.Provider>
  );
}

type CheckboxIndicatorProps = React.SVGProps<SVGSVGElement>;

function CheckboxIndicator({ className, ...props }: CheckboxIndicatorProps) {
  const { isChecked } = useCheckbox();
  if (!isChecked) return null;

  return (
    <svg
      data-slot="checkbox-indicator"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      strokeWidth="3.5"
      stroke="currentColor"
      className={cn(className)}
      {...props}
    >
      {isChecked === "indeterminate" ? (
        <line x1="5" y1="12" x2="19" y2="12" strokeLinecap="round" />
      ) : (
        <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 12.75l6 6 9-13.5" />
      )}
    </svg>
  );
}

export {
  Checkbox,
  CheckboxIndicator,
  useCheckbox,
  type CheckboxProps,
  type CheckboxIndicatorProps,
  type CheckboxContextType,
};
