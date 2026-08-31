export class CustomHomepageNativeBridge {
  private generation: number;
  private requestHandler: (generation: number, action: string, value: string) => string;

  constructor(
    generation: number,
    requestHandler: (generation: number, action: string, value: string) => string
  ) {
    this.generation = Math.max(0, Math.floor(generation));
    this.requestHandler = requestHandler;
  }

  request(action: string, value: string): string {
    return this.requestHandler(this.generation, action, value);
  }
}
