'use strict';

// Runs INSIDE Incyclist. This is not an IPC endpoint in the standalone app.
function createShiftRouter(dependencies) {
    const now = dependencies.now || Date.now;
    const seen = new Set();
    let tail = Promise.resolve();
    let queued = 0;
    let closed = false;

    function reject(reason) { return { status: 'rejected', reason }; }
    function handle(event) {
        if (!event || typeof event.id !== 'string' || event.id.length > 80 ||
            typeof event.session !== 'string' || !Number.isFinite(event.emittedAtMs) ||
            (event.direction !== 1 && event.direction !== -1)) {
            return Promise.resolve(reject('invalid-event'));
        }
        if (closed) return Promise.resolve(reject('closed'));
        if (seen.has(event.id)) return Promise.resolve(reject('duplicate'));
        seen.add(event.id);
        if (seen.size > 256) seen.delete(seen.values().next().value);
        if (queued >= 8) return Promise.resolve(reject('queue-full'));
        // Capture primitives; do not retain a caller-mutable native event object.
        const input = { id: event.id, session: event.session,
            direction: event.direction, emittedAtMs: event.emittedAtMs };
        queued += 1;
        const work = tail.then(async () => {
            if (closed || !dependencies.active()) return reject('inactive-ride');
            if (input.session !== dependencies.session()) return reject('stale-session');
            const age = now() - input.emittedAtMs;
            if (age > 1500 || age < -250) return reject('expired-event');
            if (dependencies.targetCount() !== 1) return reject('requires-one-started-control-adapter');
            if (!dependencies.virtualShiftingEnabled()) return reject('virtual-shifting-disabled-or-erg');
            if (dependencies.busy()) return reject('trainer-update-busy');
            try {
                // Existing Incyclist path owns both route simulation and gear deltas.
                await dependencies.sendUpdate({ gearDelta: input.direction });
                return { status: 'submitted', gearDisplay: String(dependencies.gearDisplay() ?? ''),
                    evidence: 'incyclist-software-path-only' };
            } catch (error) {
                return reject('send-update-error: ' + String(error));
            }
        });
        tail = work.then(() => undefined, () => undefined);
        return work.finally(() => { queued -= 1; });
    }
    return { handle, close() { closed = true; } };
}
module.exports = { createShiftRouter };
