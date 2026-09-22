// lamp_store.h - keeps the lamp state across a restart.
//
// Without it, the stack light would stay dark after a power cut, restart or
// flash until the next hook happens to send the target state - and if Claude
// is waiting for input, none fires. With the store, it shows what it showed
// last right after startup; the next hook corrects it if something has
// changed in the meantime.

#pragma once

namespace LampStore {

// Reads the last stored state from NVS and applies it.
// Must run after Lamps::begin() and before Lamps::startEffectTask(), so the
// lamps come up directly in the restored state.
void load();

// Call from loop(). Writes with a delay and only on a real change.
void tick();

}   // namespace LampStore
