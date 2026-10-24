export interface ShiftMessage { id: string; session: string; direction: 1 | -1; emittedAtMs: number }
export interface ShiftResult { status: 'submitted' | 'rejected'; reason?: string; gearDisplay?: string; evidence?: string }
export interface ShiftDependencies {
    active(): boolean; session(): string | null; targetCount(): number;
    virtualShiftingEnabled(): boolean; busy(): boolean; gearDisplay(): unknown;
    sendUpdate(request: { gearDelta: number }): Promise<void>;
    now?(): number;
}
export function createShiftRouter(dependencies: ShiftDependencies): {
    handle(event: ShiftMessage): Promise<ShiftResult>;
    close(): void;
};
