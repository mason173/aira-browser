export interface BrowserConfirmationRequest {
  title: string;
  message: string;
  cancelLabel: string;
  confirmLabel: string;
  confirmTone?: 'warning' | 'alert';
  onCancel?: () => void;
  onConfirm: () => void;
}

export interface BrowserConfirmationSink {
  confirm(request: BrowserConfirmationRequest): void;
}
