import React, { useEffect, useState } from 'react';
import { NativeModules, NativeEventEmitter, Platform, Pressable, Text, StyleSheet } from 'react-native';
import { useDeviceRide } from 'incyclist-services';
import { createShiftRouter, ShiftMessage } from './shiftRouter';

const native = NativeModules.ClickBridgeModule;

/** Mount only in a real ride, inside the modified Incyclist application. */
export function ClickBridgeControls({ simulate = false }: { simulate?: boolean }) {
    const [status, setStatus] = useState('ClickBridge');
    useEffect(() => {
        if (Platform.OS !== 'ios' || !native || simulate) return;
        let active = true;
        let session: string | null = null;
        const service = useDeviceRide();
        const router = createShiftRouter({
            active: () => active,
            session: () => session,
            targetCount: () => service.getAdapters({}).filter(({ adapter }) =>
                adapter?.isControllable() && adapter.isStarted() && !adapter.isStopped() && !adapter.isPaused()).length,
            virtualShiftingEnabled: () => {
                const mode = service.getCyclingMode();
                return !!mode?.isSIM() && ['Mixed', 'Incyclist', 'SmartTrainer', 'Enabled'].includes(String(mode.getSetting('virtshift')));
            },
            busy: () => service.isUpdateBusy(),
            sendUpdate: request => service.sendUpdate(request),
            gearDisplay: () => service.getData()?.gearStr,
        });
        const emitter = new NativeEventEmitter(native);
        const subscription = emitter.addListener('ClickBridgeShift', (event: ShiftMessage) => {
            void router.handle(event).then(result => {
                if (!active) return;
                setStatus(result.status === 'submitted' ? 'Schaltauftrag abgegeben' : 'ClickBridge · ' + result.reason);
                native.report(event.id, JSON.stringify(result));
            }).catch(error => { if (active) setStatus(String(error)); });
        });
        void native.arm(true).then((id: string) => {
            if (active) session = id;
            else void native.arm(false);
        }).catch((error: unknown) => { if (active) setStatus(String(error)); });
        return () => {
            active = false; session = null; router.close(); subscription.remove();
            void native.arm(false);
        };
    }, [simulate]);
    if (Platform.OS !== 'ios' || !native || simulate) return null;
    return <Pressable accessibilityRole="button" accessibilityLabel="ClickBridge Controller einrichten"
        onPress={() => native.presentSetup()} style={styles.button}>
        <Text style={styles.text} numberOfLines={1}>{status}</Text>
    </Pressable>;
}
const styles = StyleSheet.create({
    button: { position: 'absolute', left: 16, bottom: 72, zIndex: 100, maxWidth: 280,
        padding: 10, borderRadius: 10, backgroundColor: '#1A222AEF', borderWidth: 1, borderColor: '#FB923C' },
    text: { color: '#FB923C', fontSize: 12 },
});
