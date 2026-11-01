# Changelog

All notable project changes are documented here.

## 2.0.0 - 2026-11-01

### Changed

- Replaced Meteobridge `template.cgi` input with direct PurpleAir `/json`
  polling.
- Added channel A and B averaging for ATM and CF=1 PM2.5 fields.
- Changed the default polling interval from 60 to 120 seconds to match the
  PurpleAir two-minute average.
- Made `PURPLEAIR_URL` and `PM25_SOURCE` the primary input settings.
- Updated installation, configuration, troubleshooting, and migration
  documentation for the new architecture.

### Fixed

- Removed the circular logger-to-plugin-to-template-engine path identified as
  the trigger for Meteobridge logger signal 11 failures in the tested VM.
- Prevented those logger failures from indirectly disconnecting the Meteostick
  and all other stations.
- Added frozen-response detection using PurpleAir uptime.
- Added automatic acceptance of a lower uptime after a PurpleAir reboot.
- Added one-channel fallback when only particle counter A or B is valid.

### Validation

- Expanded the test suite to 28 tests.
- Tested exact PurpleAir JSON field ordering.
- Tested A/B averaging, single-channel fallback, frozen data, sensor reboot,
  configuration discovery, AQI breakpoints, correction, NowCast, and plugin
  lifecycle behavior.
- Completed the previous 24-hour failure window without a logger segmentation
  fault or Meteostick interruption.

### Breaking changes

- Version 1.x configuration files cannot be reused unchanged.
- `SOURCE_STATION`, `PM25_SENSOR`, `RH_SENSOR`, `MB_URL`, `MB_USER`, and
  `MB_PASSWORD` are obsolete.
- The PurpleAir sensor must be reachable directly from Meteobridge over the
  local network.

## 1.x - Legacy

Version 1.x read PM2.5 from an existing Meteobridge station through
`template.cgi`. That design is retired because it re-entered the Meteobridge
template engine from inside its logger-managed plugin process.
