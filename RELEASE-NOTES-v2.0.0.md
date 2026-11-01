# Meteobridge AQI 2.0.0 Release Notes

## Summary

Version 2.0.0 is a stability-focused redesign. It reads the PurpleAir sensor
directly from its local `/json` endpoint rather than requesting Station data
back through Meteobridge.

The AQI calculation, EPA 2024 breakpoints, NowCast history, output assignments,
status codes, and optional EPA correction remain available.

## Why this release was necessary

The 1.x plugin called Meteobridge `template.cgi` once per minute while running
as a child of the Meteobridge logger. In the tested deployment, this re-entered
Meteobridge's template/network evaluation path and produced a repeating stack:

```text
get_set
send_wnet_nosensor
test_inetupload
get_set
...
```

The logger eventually received signal 11. Its restart disconnected every
station, including the Meteostick. The serial device did not always reconnect
cleanly, which made the failure appear to be a USB or Meteostick problem.

Version 2.0.0 completely removes the internal callback. It does not query
`template.cgi`, localhost live-data ports, or Meteobridge databases.

## New input path

```text
http://PURPLEAIR-IP/json
```

For outdoor sensors, `PM25_SOURCE="atm"` averages:

```text
pm2_5_atm
pm2_5_atm_b
```

CF=1 fields can be selected when the EPA U.S.-wide PurpleAir correction is
intentionally enabled.

## Upgrade procedure

1. Disable or stop the existing AQI plugin station.
2. Back up `meteobridge-aqi.conf` and the state directory.
3. Replace both `meteobridge-aqi.plugin` and `meteobridge-aqi.conf`.
4. Set `PURPLEAIR_URL` to the sensor's reserved LAN address.
5. Remove obsolete 1.x source-station and Meteobridge HTTP settings.
6. Reload the plugin station.
7. Confirm status output Data #5 changes from 1 to 0.

Existing NowCast history can be retained when the physical PurpleAir sensor is
unchanged. Renaming the old state directory provides the cleanest validation.

## Compatibility

Version 2.0.0 requires a newer Meteobridge platform with a local scripts
directory and persistent writable storage, including PRO, PRO2, NANO SD,
Raspberry Pi, and VM platforms.

It is not packaged as a single-file URL plugin for the original flashed router
platforms or NANO without SD storage.

## Operational differences

- PurpleAir is queried once every 120 seconds.
- Channels A and B are averaged when both are valid.
- One valid channel is accepted as a fallback.
- Unchanged PurpleAir uptime is rejected after the configured age limit.
- A lower uptime is treated as a sensor reboot.
- Direct values may differ slightly from Meteobridge's PurpleAir station due to
  channel selection, averaging, and rounding.

## Validation status

The release passes 28 automated tests and completed the previous 24-hour crash
window without a logger signal 11 failure or Meteostick interruption. A 72-hour
test and one-week observation remain recommended before declaring any
installation fully proven.
