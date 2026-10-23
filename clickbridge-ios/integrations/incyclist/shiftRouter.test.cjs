const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createShiftRouter } = require('./shiftRouter.js');

function fixture(overrides = {}) {
    const calls = [];
    const dependencies = { active: () => true, session: () => 'ride-1', targetCount: () => 1,
        virtualShiftingEnabled: () => true, busy: () => false, gearDisplay: () => '13',
        now: () => 1000, sendUpdate: async request => { calls.push(request); }, ...overrides };
    return { calls, dependencies, router: createShiftRouter(dependencies) };
}
const event = (id = '1', direction = 1) => ({ id, direction, session: 'ride-1', emittedAtMs: 1000 });

test('routes both directions through existing Incyclist path, no slope override', async () => {
    const { calls, router } = fixture();
    assert.equal((await router.handle(event())).status, 'submitted');
    assert.equal((await router.handle(event('2', -1))).evidence, 'incyclist-software-path-only');
    assert.deepEqual(calls, [{ gearDelta: 1 }, { gearDelta: -1 }]);
});
test('suppresses duplicate native events', async () => {
    const { calls, router } = fixture();
    await router.handle(event());
    assert.equal((await router.handle(event())).reason, 'duplicate');
    assert.equal(calls.length, 1);
});
test('rejects invalid, expired and future events', async () => {
    const { calls, router } = fixture();
    assert.equal((await router.handle({ ...event(), direction: 4 })).reason, 'invalid-event');
    assert.equal((await router.handle({ ...event('old'), emittedAtMs: -1000 })).reason, 'expired-event');
    assert.equal((await router.handle({ ...event('future'), emittedAtMs: 5000 })).reason, 'expired-event');
    assert.equal(calls.length, 0);
});
test('rejects stale ride session and events after cleanup', async () => {
    const { calls, router } = fixture();
    assert.equal((await router.handle({ ...event(), session: 'old-ride' })).reason, 'stale-session');
    router.close();
    assert.equal((await router.handle(event('2'))).reason, 'closed');
    assert.equal(calls.length, 0);
});
test('gates inactive rides, ERG, disabled shifting, missing and multiple trainers', async () => {
    for (const overrides of [{ active: () => false }, { virtualShiftingEnabled: () => false },
        { targetCount: () => 0 }, { targetCount: () => 2 }, { busy: () => true }]) {
        const { calls, router } = fixture(overrides);
        assert.equal((await router.handle(event())).status, 'rejected');
        assert.equal(calls.length, 0);
    }
});
test('serializes requests and recovers after transport error', async () => {
    let inFlight = 0, maxInFlight = 0, number = 0;
    const { router } = fixture({ sendUpdate: async () => {
        inFlight++; maxInFlight = Math.max(maxInFlight, inFlight);
        await new Promise(resolve => setTimeout(resolve, 2));
        inFlight--; if (number++ === 0) throw Error('test failure');
    } });
    const results = await Promise.all([router.handle(event('1')), router.handle(event('2'))]);
    assert.equal(maxInFlight, 1); assert.equal(results[0].status, 'rejected');
    assert.equal(results[1].status, 'submitted');
});
test('rechecks state at execution time and bounds queue', async () => {
    let resolve;
    const { router, calls, dependencies } = fixture({ sendUpdate: () => new Promise(r => { resolve = r; }) });
    const first = router.handle(event());
    await new Promise(r => setImmediate(r));
    const rest = Array.from({ length: 8 }, (_, i) => router.handle(event('queued-' + i)));
    dependencies.active = () => false;
    resolve(); await first;
    const results = await Promise.all(rest);
    assert.equal(results.filter(r => r.reason === 'queue-full').length, 1);
    assert.equal(results.filter(r => r.reason === 'inactive-ride').length, 7);
    assert.equal(calls.length, 0);
});
