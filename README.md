# Meteobridge AQI Plugin

Version 2.0.0

- [Version 2.0.0 release notes](RELEASE-NOTES-v2.0.0.md)
- [Changelog](CHANGELOG.md)

## 1. Purpose

Meteobridge AQI is a User-Defined Station plugin that reads a PurpleAir sensor
directly over the local network and publishes U.S. EPA air-quality values as
Meteobridge sensors.

It provides instantaneous AQI-equivalent, EPA NowCast AQI, current and NowCast
PM2.5, EPA category, health status, and optional EPA U.S.-wide PurpleAir
correction.

Version 2.0.0 does not read another Meteobridge station and never calls
Meteobridge `template.cgi`. This avoids re-entering the Meteobridge template
engine from inside its logger-managed plugin process.

### Why the plugin reads PurpleAir directly

Version 1.x retrieved another Meteobridge station's values by calling
`template.cgi` from inside the logger-managed plugin:

```text
Meteobridge logger
  -> AQI plugin
      -> template.cgi
          -> Meteobridge logger/template evaluation
```

In the tested Meteobridge VM deployment, this circular access triggered a
repeating `get_set`, `send_wnet_nosensor`, and `test_inetupload` call chain. The
logger eventually terminated with signal 11, disconnected every station, and
sometimes failed to restore the Meteostick serial session.

Version 2.0.0 removes that re-entry:

```text
PurpleAir /json -> AQI plugin -> Meteobridge logger
```

The PurpleAir request is local, is made once every two minutes, and is only a
few kilobytes. The new path completed the previous 24-hour failure window
without a logger segmentation fault or Meteostick interruption. Longer-term
observation is still recommended on each installation.

No installer, cron job, service, Python runtime, or modification outside the
Meteobridge scripts directory is required.

## 2. Requirements and platforms

- Meteobridge firmware with User-Defined Plugin station support
- A PurpleAir sensor reachable from Meteobridge over the LAN
- A reserved or static address for the PurpleAir sensor
- Access to the Meteobridge `scripts` directory
- `curl` or `wget`, normally included with Meteobridge
- Writable local storage for NowCast history, status, and logs

The plugin uses POSIX shell and `awk`.

Supported platforms with local scripts and persistent storage are Meteobridge
PRO, PRO2, NANO SD, Raspberry Pi, and VM. This package is not intended for the
original flashed router platforms or NANO without SD storage. It is a two-file
local plugin, not a single-file URL plugin.

## 3. Package contents

| File | Purpose | Required |
| --- | --- | --- |
| `meteobridge-aqi.plugin` | Executable User-Defined Station plugin | Yes |
| `meteobridge-aqi.conf` | Configuration | Yes |
| `aqi-status.template` | Optional display template | No |
| `README.md` | Complete documentation | No |
| `RELEASE-NOTES-v2.0.0.md` | Release and migration notes | No |
| `CHANGELOG.md` | Version history | No |
| `LICENSE` | MIT license | No |
| `tests/run-tests.sh` | Linux validation suite | No |

## 4. Installation

### 4.1 Reserve and test the PurpleAir address

Create a DHCP reservation so the sensor address does not change. This
installation uses `192.168.100.1`.

The included address is specific to the original installation. Anyone using
this project from GitHub must replace it with the reserved LAN address of their
own PurpleAir sensor.

Test it from Meteobridge:

```sh
wget -qO- http://192.168.100.1/json
```

The JSON must contain `pm2_5_atm`, `pm2_5_atm_b`, `current_humidity`, and
`uptime`.

### 4.2 Copy the files

Copy these files into `/temp/data/scripts`:

```text
meteobridge-aqi.plugin
meteobridge-aqi.conf
```

The plugin also recognizes `/tmp/data/scripts`, `/tmp/mnt/data/scripts`,
`/data/scripts`, and `/scripts` for platform variants.

Keep both filenames unchanged. If permissions are exposed:

```sh
chmod 755 /temp/data/scripts/meteobridge-aqi.plugin
chmod 644 /temp/data/scripts/meteobridge-aqi.conf
```

### 4.3 Configure the source

The included configuration contains:

```sh
PURPLEAIR_URL="http://10.24.170.191/json"
PM25_SOURCE="atm"
UPDATE_SECONDS=120
```

Change only `PURPLEAIR_URL` if the reservation changes. Keep `/json`; it
provides the sensor's two-minute average.

### 4.4 Add the station

1. Open Meteobridge Weather Station configuration.
2. Add an additional station.
3. Select User-Defined Plugin.
4. Select `meteobridge-aqi.plugin`.
5. Save and press Reload Plugin, or restart the station process if requested.

The plugin first emits status 1. The first valid PurpleAir response changes it
to 0 and publishes PM2.5/AQI values.

## 5. PurpleAir input

### 5.1 Channel averaging

For outdoor ATM data, the plugin reads channel A `pm2_5_atm` and channel B
`pm2_5_atm_b`. It averages them when both are valid. The verified sample gives:

```text
Channel A: 2.97 ug/m3
Channel B: 3.36 ug/m3
Average:   3.165 ug/m3
```

If one channel is unavailable, the plugin uses the other and records the
fallback in `status.txt`. If both are invalid, it emits status 1 instead of a
false zero.

### 5.2 ATM versus CF=1

The default `PM25_SOURCE="atm"` is appropriate for this outdoor installation.
Setting `PM25_SOURCE="cf1"` reads `pm2_5_cf_1` and `pm2_5_cf_1_b` instead.

Use CF=1 only when intentionally applying the plugin's EPA correction. Do not
apply that correction to ATM data.

### 5.3 Frozen-response protection

The plugin tracks PurpleAir `uptime`. If it does not advance for longer than
`MAX_SENSOR_AGE`, the data is considered frozen and status 1 is emitted. A
lower uptime is accepted as a sensor reboot. The default maximum is 300 seconds.

## 6. Configuration reference

### 6.1 Connection

| Setting | Default | Description |
| --- | --- | --- |
| `PURPLEAIR_URL` | `http://10.24.170.191/json` | Complete local JSON URL |
| `PM25_SOURCE` | `atm` | `atm` or `cf1`; A and B are averaged |
| `MAX_SENSOR_AGE` | `300` | Accepted unchanged uptime in seconds |
| `HTTP_TIMEOUT` | `10` | HTTP request timeout in seconds |

There are no Meteobridge credentials, source station numbers, sensor names, or
`template.cgi` settings in version 2.0.0.

### 6.2 AQI calculation

| Setting | Default | Description |
| --- | --- | --- |
| `AQI_STANDARD` | `EPA_2024` | Only supported breakpoint set |
| `AQI_MODE` | `both` | `instant`, `nowcast`, or `both` |
| `AQI_CAP` | `500` | Maximum AQI; `999` permits extended values |
| `CATEGORY_SOURCE` | `nowcast` | `instant` or `nowcast` |

Instant AQI is calculated from the latest PM2.5 sample but is not the official
EPA 24-hour AQI. NowCast uses weighted hourly concentrations and is preferred
once enough history is available.

### 6.3 Optional correction

| Setting | Default | Description |
| --- | --- | --- |
| `PURPLEAIR_CORRECTION` | `none` | `none` or `epa_us` |
| `CORRECTION_MISSING_RH` | `reject` | `reject` or `uncorrected` |

For ATM input:

```sh
PM25_SOURCE="atm"
PURPLEAIR_CORRECTION="none"
```

For EPA correction of raw CF=1 values:

```sh
PM25_SOURCE="cf1"
PURPLEAIR_CORRECTION="epa_us"
```

The correction uses PurpleAir `current_humidity`. Through 343 ug/m3:

```text
corrected PM2.5 = 0.524 x CF1 - 0.0862 x RH + 5.75
```

Above 343 ug/m3:

```text
corrected PM2.5 = 0.46 x CF1 + 0.000393 x CF1^2 + 2.9738
```

### 6.4 NowCast

| Setting | Default | Description |
| --- | --- | --- |
| `NOWCAST_ENABLED` | `yes` | Enable history and NowCast |
| `NOWCAST_HOURS` | `12` | Hourly averages, 3 through 24 |
| `NOWCAST_MIN_RECENT` | `2` | Usable hours among newest three |
| `NOWCAST_REQUIRE_CURRENT` | `no` | Require current clock hour |
| `MIN_HOURLY_COVERAGE` | `75` | Required sample coverage percentage |

NowCast normally appears after one to two hours. Before then, its outputs are
absent rather than reported as zero.

### 6.5 Outputs

| Setting | Default | Meaning |
| --- | --- | --- |
| `OUTPUT_INSTANT_AQI` | `data0` | Instantaneous AQI-equivalent |
| `OUTPUT_NOWCAST_AQI` | `data1` | EPA NowCast AQI |
| `OUTPUT_CATEGORY` | `data2` | EPA category code |
| `OUTPUT_PM25` | `data3` | Current PM2.5 |
| `OUTPUT_NOWCAST_PM25` | `data4` | NowCast PM2.5 |
| `OUTPUT_STATUS` | `data5` | Plugin status |

### 6.6 Operation and storage

| Setting | Default | Description |
| --- | --- | --- |
| `UPDATE_SECONDS` | `120` | Time between PurpleAir requests |
| `LOG_LEVEL` | `info` | `error`, `warn`, `info`, or `debug` |
| `STATE_DIR` | blank | Optional explicit state directory |
| `LOG_MAX_KB` | `256` | Log rotation threshold in KB |

Blank `STATE_DIR` creates `meteobridge-aqi-state` beside the configuration:

| File | Purpose |
| --- | --- |
| `pm25-history.tsv` | NowCast samples |
| `source-stamp.txt` | Last PurpleAir uptime/change time |
| `status.txt` | Human-readable status |
| `last-output.txt` | Most recent plugin records |
| `meteobridge-aqi.log` | Rotating operational log |

## 7. Results

For plugin Station 4, the outputs are:

| Display | Physical sensor | Meaning |
| --- | --- | --- |
| Data | `data4!0num` | Instantaneous AQI-equivalent |
| Data #1 | `data4!1num` | EPA NowCast AQI |
| Data #2 | `data4!2num` | EPA category code |
| Data #3 | `data4!3num` | Current PM2.5 in ug/m3 |
| Data #4 | `data4!4num` | NowCast PM2.5 in ug/m3 |
| Data #5 | `data4!5num` | Plugin status |

The verified sample should initially produce approximately:

| Display | Value | Interpretation |
| --- | ---: | --- |
| Data #5 | `0.00` | Healthy |
| Data | `17.00` | Instantaneous AQI-equivalent 17 |
| Data #3 | `3.17` | A/B averaged PM2.5 |

### 7.1 Category codes

| Code | Category |
| ---: | --- |
| 0 | Good |
| 1 | Moderate |
| 2 | Unhealthy for Sensitive Groups |
| 3 | Unhealthy |
| 4 | Very Unhealthy |
| 5 | Hazardous |

### 7.2 Status codes

| Code | Meaning | Action |
| ---: | --- | --- |
| 0 | Healthy | None |
| 1 | PurpleAir missing, invalid, frozen, or unreachable | Check address, VLAN access, power, and JSON |
| 2 | Humidity unavailable for EPA correction | Restore humidity, disable correction, or allow fallback |
| 3 | Configuration/state error | Check settings, paths, and permissions |

The plugin retries indefinitely. A valid response automatically restores 0.

## 8. EPA 2024 breakpoints

PM2.5 is truncated to one decimal before interpolation and AQI is rounded.

| PM2.5, ug/m3 | AQI | Category |
| ---: | ---: | --- |
| 0.0 to 9.0 | 0 to 50 | Good |
| 9.1 to 35.4 | 51 to 100 | Moderate |
| 35.5 to 55.4 | 101 to 150 | Unhealthy for Sensitive Groups |
| 55.5 to 125.4 | 151 to 200 | Unhealthy |
| 125.5 to 225.4 | 201 to 300 | Very Unhealthy |
| 225.5 to 325.4 | 301 to 500 | Hazardous |

## 9. Diagnostics

Run from `/temp/data/scripts`:

```sh
./meteobridge-aqi.plugin --version
./meteobridge-aqi.plugin --show-source
./meteobridge-aqi.plugin --once
./meteobridge-aqi.plugin --status
./meteobridge-aqi.plugin --sample 48.7 42
```

`--show-source` should display:

```text
PurpleAir URL: http://10.24.170.191/json
PM2.5 source: atm (channel A/B average)
```

## 10. Troubleshooting

### 10.1 Status remains 1

Run `wget -qO- http://10.24.170.191/json`, then verify:

1. The reservation is still `10.24.170.191`.
2. Meteobridge can reach TCP port 80 across the VLANs.
3. JSON contains both ATM PM2.5 fields and `uptime`.
4. `uptime` increases between requests.
5. `status.txt` and `meteobridge-aqi.log` show no new error.

### 10.2 Status 2 or 3

Status 2 applies only to EPA correction and missing humidity. Status 3 means
the configuration is missing/invalid or the state directory is unusable. The
plugin searches beside itself and in the scripts directories from section 4.2.

### 10.3 NowCast is absent

Wait one to two hours. If it remains absent, inspect history for gaps and check
`MIN_HOURLY_COVERAGE`.

### 10.4 Logger stability

Version 2.0.0 contains no request to `127.0.0.1`, `template.cgi`, Meteobridge
live-data ports, or Meteobridge databases. Its only input request is the
configured PurpleAir URL. If logger crashes continue, disable the plugin and
investigate another logger service.

## 11. Upgrading from version 1.x

Version 2.0.0 changes the input architecture. Do not reuse the complete 1.x
configuration unchanged.

1. Stop the old AQI plugin station.
2. Replace the plugin file.
3. Replace or update the configuration.
4. Remove `SOURCE_STATION`, `PM25_SENSOR`, `RH_SENSOR`, `MB_URL`, `MB_USER`, and
   `MB_PASSWORD`.
5. Set `PURPLEAIR_URL` to the local `/json` endpoint.
6. Reload the plugin station and confirm Data #5 becomes 0.

Existing NowCast history can be retained because the physical sensor is the
same. Clear it for a clean old-input versus direct-input comparison.

## 12. Limitations

- This is not a regulatory monitor.
- Instant AQI is not official EPA 24-hour AQI.
- Local JSON does not include PurpleAir server-side channel flags.
- Agreement with AirNow is not guaranteed.
- Missed samples are not backfilled.
- Do not replace emergency or medical instructions with plugin output.

Run the Linux validation suite with `./tests/run-tests.sh`.

## 13. References

- [PurpleAir local JSON documentation](https://community.purpleair.com/t/sensor-json-documentation/6917)
- [PurpleAir data access methods](https://community.purpleair.com/t/how-to-obtain-sensor-data/9727)
- [EPA AQI breakpoints](https://aqs.epa.gov/aqsweb/documents/codetables/aqi_breakpoints.html)
- [EPA AQI technical assistance](https://www.airnow.gov/publications/air-quality-index/technical-assistance-document-for-reporting-the-daily-aqi/)

## 14. License

MIT. See `LICENSE`.
