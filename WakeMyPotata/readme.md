WakeMyPotata Components
===================

- [wmp-run](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp-run) : The Core Intelligence.

  Handles both battery-present and battery-absent scenarios, only triggers shutdown when necessary, and schedules rtcwake for AC restoration.
- [wmp](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp) : The Control Script.

  Adds a battery command for user status, more robust CLI.
- [wmp.service](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp.service) : The Systemd Service Unit File.

  No major changes, but fully compatible with revised logic.
- [wmp.timer](https://github.com/dpurnam/scripts/blob/main/WakeMyPotata/src/wmp.timer) : The Systemd Service Timer File.

  No major changes, but fully compatible with revised logic.

Scenarios Supported
===================
Scenario 1:
- Battery exists
- rtcwake/shutdown is only triggered if BOTH AC power is lost AND battery ≤ 10%
- If AC returns before battery hits 10%, no shutdown

Scenario 2:
- No battery present
- On AC loss, just trigger rtcwake in 'no' mode (wake up only, no shutdown)
- If AC returns, no shutdown
