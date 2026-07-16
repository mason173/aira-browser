import { Switch, SwitchThumb } from '@/components/animate-ui/primitives/radix/switch';

type SyncToggleFieldProps = {
  label: string;
  description?: string;
  checked: boolean;
  onCheckedChange: (checked: boolean) => void;
  disabled?: boolean;
};

export function SyncToggleField({
  label,
  description,
  checked,
  onCheckedChange,
  disabled = false,
}: SyncToggleFieldProps) {
  return (
    <div className={`flex items-center justify-between gap-3 py-1 ${disabled ? 'opacity-55' : ''}`}>
      <div className="flex flex-col items-start">
        <span className="text-sm font-medium leading-none">{label}</span>
        {description ? (
          <span className="mt-1 text-xs text-muted-foreground">{description}</span>
        ) : null}
      </div>
      <Switch
        checked={checked}
        onCheckedChange={(value) => {
          if (!disabled) onCheckedChange(value);
        }}
        disabled={disabled}
        className="relative flex h-6 w-10 items-center justify-start rounded-full p-0.5 transition-colors data-[state=checked]:justify-end"
      >
        <SwitchThumb className="h-full aspect-square rounded-full" pressedAnimation={{ width: 22 }} />
      </Switch>
    </div>
  );
}
