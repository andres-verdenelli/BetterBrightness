# BetterBrightness Roadmap

This document separates the current behavior from possible future work.

## Current behavior (implemented)

| Area | Status | What the app does today |
| --- | --- | --- |
| WiZ discovery | Implemented, manual | The **Discover Lights** button sends `getSystemConfig` to UDP broadcast `255.255.255.255:38899`. |
| Discovery at app launch | Implemented, once | Each app launch starts one discovery run; after it finishes, manual discovery remains available from Settings. |
| Discovery retries | Implemented, configurable | It defaults to 3 broadcasts and a 500 ms response window per attempt. Settings validates 1–10 attempts and 100–5,000 ms. |
| Stable light identity | Implemented | It normalizes the MAC address and uses it as the stable identity. A new reply updates the saved IP if DHCP changed it. |
| Discovery merge | Implemented | Known MACs retain their name, enabled state, and brightness mapping. New lamps are added disabled, with the default 40–80% monitor range and 1–100% light range. |
| Duplicates | Implemented | Replies are deduplicated by MAC address; repeated replies do not create multiple lamps. |
| Per-light control | Implemented | Each saved lamp has a name, current IP, MAC (when discovered), enabled state, and monitor/light min/max values. Only enabled lamps receive `setPilot`. |
| Pause/resume | Implemented | Pause keeps listening to BetterDisplay but suppresses `setPilot`. Resume sends the latest observed brightness to enabled lamps. |
| App in background | Partially implemented | It is a menu-bar app and can run without a terminal, but it does not yet start automatically at login or write persistent logs. |

## Important review findings

### Discovery is not a background loop

There is no repeated discovery loop in the current code. The app runs discovery
once when it opens, and it can then be run again manually with **Discover
Lights**. The discovery service permits only one active run, so a manual scan
cannot overlap the launch scan. Therefore the discovery code, by itself, cannot
continuously flood the network.

With the default settings, one manual run produces three small UDP broadcast
packets, each followed by a 500 ms reply window. That is very low traffic. We
still need a real-LAN test to confirm that the router and WiZ lamps receive
broadcasts reliably in the current network.

### The more likely source of UDP volume is brightness sync

Every valid BetterDisplay brightness notification sends one unicast `setPilot`
packet to every enabled lamp. There is currently no dead zone, rate limit,
coalescing, or "do not resend the same dimming value" check. Rapid brightness
changes can therefore cause many packets. This is not broadcast traffic, but
it is the first place to improve if the concern is UDP volume.

### UDP send logging is not delivery confirmation

The app logs a successful `NWConnection.send`, but UDP has no acknowledgement
in this implementation. That only confirms that macOS accepted the datagram;
it does not prove the lamp received or applied `setPilot`. A future diagnostic
mode should optionally verify state with a WiZ response, without adding that
extra traffic to normal sync.

## Network validation checklist

When investigating discovery or command delivery on a local network:

1. Open the app and let its initial discovery finish; record the attempt
   timestamps, discovered devices, and the summary shown by the app. Then run
   one manual scan and compare the result.
2. Confirm each configured lamp is enabled and that its current IP was updated
   from its MAC address if DHCP changed it.
3. Change monitor brightness slowly, then quickly; compare the WiZ lamps with
   the app log to distinguish discovery failure from `setPilot` volume.
4. If discovery finds no lamps, test whether global broadcast
   `255.255.255.255` is forwarded on this Wi-Fi network. The likely follow-up
   is to target the active interface's subnet broadcast address instead.
5. Do not add output suppression unless measurements show a real problem. The
   current product decision is to favor immediate, responsive light changes.

### Remaining questions before changing discovery

- When a lamp does not react, do you want a diagnostic check that asks WiZ for
  state, knowing it adds one extra UDP exchange per lamp?
- Is the problem seen while dragging brightness continuously, after a single
  brightness change, or only after the Mac wakes/reconnects to Wi-Fi?
- Is it acceptable to ignore brightness changes of 1–2 percentage points and
  delay rapid changes briefly (for example, 100–200 ms)?

## Planned improvements

### Reliability and observability

- [ ] Log configured MACs that did not answer discovery, while continuing with
  the lamps that did answer.
- [ ] Add an opt-in diagnostic mode that records discovery attempts, sender
  IP/MAC, malformed replies, and command-send errors in a persistent log.
- [x] Make discovery attempts and response windows configurable, while keeping
  the baseline at 3 attempts and 500 ms and enforcing safe limits.
- [ ] Add an optional, measured command retry policy only if real tests show
  that it helps. Do not treat successful UDP submission as lamp acknowledgement.
- [ ] If global broadcast is unreliable, select the active LAN interface and
  use its subnet broadcast address.

### Reducing brightness-sync traffic

- [ ] Deferred by product decision: keep the current brightness response fully
  immediate; do not add a dead zone, deduplication, or debounce unless a
  real-LAN measurement demonstrates a problem.
- [ ] Do not send `setPilot` when the calculated dimming value for a lamp did
  not change.
- [ ] Add a configurable 1–2% dead zone and/or a short debounce for rapidly
  changing monitor brightness.
- [ ] Consider gradual transitions only after testing whether WiZ's own
  transition behavior is sufficient.

### App lifecycle

- [ ] Start automatically at login, with an explicit on/off control.
- [ ] Store accessible, rotating diagnostic logs.
- [ ] Provide a visible connection/discovery state, rather than only a send
  attempt status.

### Brightness features

- [ ] Non-linear brightness curve: gentler at low values, stronger near high
  values.
- [ ] Night mode with a separate schedule and maximum dimming (for example,
  40% after 22:00).
- [ ] Profiles (work, movie, gaming) with lamps, ranges, and curve per profile.
- [ ] Per-profile color temperature and color behavior.

### BetterDisplay and configuration handling

- [ ] Warn when a brightness event lacks `displayID`, instead of silently
  ignoring it.
- [ ] Decide whether external configuration-file reload is still needed. The
  app now persists Settings in `UserDefaults`, and live Settings changes are
  immediately available to the controller.

## WiZ protocol examples (reference only)

```json
{"method":"getSystemConfig","params":{}}
{"method":"getPilot","params":{}}
{"id":1,"method":"setState","params":{"state":false}}
{"id":1,"method":"setState","params":{"state":true}}
{"id":1,"method":"setPilot","params":{"r":255,"g":0,"b":0,"dimming":68}}
{"id":1,"method":"setPilot","params":{"temp":3000,"dimming":68}}
{"id":1,"method":"setPilot","params":{"sceneId":6,"speed":125,"dimming":68}}
```
