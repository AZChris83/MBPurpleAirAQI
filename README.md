# Meteobridge AQI Plugin

Version 1.0.3

## 1. Purpose

Meteobridge AQI is a User-Defined Plugin that reads PM2.5 from an existing
Meteobridge station and publishes current U.S. EPA air-quality values as new
Meteobridge sensors.

The plugin provides:

- Instantaneous PM2.5 AQI-equivalent
- EPA particulate NowCast AQI
- Corrected or uncorrected PM2.5 concentration
- NowCast PM2.5 concentration
- Numeric EPA air-quality category
- Plugin health and error status
- Optional EPA U.S.-wide PurpleAir correction

PurpleAir is the primary use case, but any station that supplies a numeric
PM2.5 sensor to Meteobridge can be used.

This is a normal Meteobridge plugin. No installer, service, cron job, package
manager, or `/root/datafeed` modification is required.

## 2. Requirements

- Meteobridge firmware with User-Defined Plugin station support
- An existing Meteobridge station that reports PM2.5
- Access to the Meteobridge `scripts` directory
- The local Meteobridge `template.cgi` endpoint
- `curl` or `wget`, normally already included with Meteobridge
- A writable location for history, status, and log files

The plugin uses POSIX shell and `awk`. Python is not required.

### 2.1 Supported Meteobridge platforms

This release requires a Meteobridge platform with a local `scripts` directory.
It uses two local files and retains NowCast history, status, and logs in writable
local storage.

Supported platforms are:

- Meteobridge PRO, including the original red and black models
- Meteobridge PRO2
- Meteobridge NANO SD
- Meteobridge Raspberry Pi
- Meteobridge VM

This package does not support:

- Original TP-Link, D-Link, or other router hardware flashed with Meteobridge
- Meteobridge NANO without the SD storage option

Some of those platforms can download a User-Defined Plugin from a URL, but this
package is intentionally not a single-file URL plugin. It requires the separate
`meteobridge-aqi.conf` file and writable storage for its operating state. No
URL-only edition is provided.

If the Meteobridge interface does not provide a local `scripts` directory, this
AQI plugin should be considered unsupported on that platform.

## 3. Package contents

| File | Purpose | Required on Meteobridge |
| --- | --- | --- |
| `meteobridge-aqi.plugin` | Executable User-Defined Plugin | Yes |
| `meteobridge-aqi.conf` | Plugin configuration | Yes |
| `aqi-status.template` | Optional human-readable display template | No |
| `README.md` | Complete documentation | No |
| `LICENSE` | MIT license | No |
| `tests/run-tests.sh` | Calculation and protocol tests for Linux | No |

## 4. Installation

### 4.1 Extract the package

Extract the ZIP archive on a computer. The two files that must be copied to
Meteobridge are:

```text
meteobridge-aqi.plugin
meteobridge-aqi.conf
```

### 4.2 Copy the files

Copy both files into the Meteobridge `scripts` directory. Depending on the
platform, this may be the `scripts` folder on the exposed Meteobridge data
share, `/data/scripts`, or another path shown by that Meteobridge system.

Do not enter an Internet URL for this release. The `.plugin` and `.conf` files
must both be stored locally on the Meteobridge platform.

Keep the `.plugin` and `.conf` files together and do not rename either file.

If shell access and Unix permissions are exposed, make the plugin executable:

```sh
chmod 755 /data/scripts/meteobridge-aqi.plugin
```

The configuration file does not need executable permission.

### 4.3 Add the User-Defined Plugin station

1. Open the Meteobridge web interface.
2. Open the **Weather Station** configuration page.
3. Add an additional station.
4. Select **User-Defined Plugin** as its station type.
5. Select `meteobridge-aqi.plugin` from the plugin list.
6. Save the configuration.
7. Restart the station process if Meteobridge requests it.

Meteobridge starts the script and keeps it running. The plugin emits a status
record immediately, then queries the configured source every 60 seconds by
default.

If the file is not shown in the plugin list, confirm that:

- Its filename ends with `.plugin`.
- It has Unix line endings.
- It is in the correct `scripts` directory.
- It is readable and executable by Meteobridge.

## 5. Configure the source sensor

Edit `meteobridge-aqi.conf` before or after copying it to Meteobridge.

### 5.1 Meteobridge sensor names

Meteobridge uses station-qualified sensor names such as `air1!1pm`:

- `air` identifies an air-quality sensor family.
- The first `1` identifies Meteobridge Station 1.
- `!1pm` identifies PM channel 1.

For the mapping observed on Meteobridge:

| Physical sensor | Generic sensor | Meaning |
| --- | --- | --- |
| `air1!0pm` | `air0pm` | PM10 or default particulate channel |
| `air1!1pm` | `air1pm` | PM2.5 |
| `air1!2pm` | `air2pm` | PM1 |

The AQI plugin must use the PM2.5 channel, not PM10. For a PurpleAir source on
Station 1, use:

```sh
SOURCE_STATION=1
PM25_SENSOR="air1pm"
RH_SENSOR="th0hum"
```

The plugin converts those generic names to:

```text
PM2.5:    air1!1pm
Humidity: th1!0hum
```

The humidity name must be verified under Meteobridge Live Data because station
drivers can map it differently.

### 5.2 Fully qualified names

A full physical sensor name can be used to bypass automatic qualification:

```sh
PM25_SENSOR="air1!1pm"
RH_SENSOR="th1!0hum"
```

When a sensor contains `!`, `SOURCE_STATION` is not inserted into that sensor
name.

### 5.3 Source station versus plugin station

`SOURCE_STATION` is the station supplying PM2.5. It is not the station where
the AQI plugin is installed.

For example:

```text
Station 1: PurpleAir source
Station 4: Meteobridge AQI plugin
```

The correct setting remains:

```sh
SOURCE_STATION=1
```

Setting it to 4 would make the plugin query itself instead of PurpleAir.

### 5.4 Stale-data protection

```sh
MAX_SENSOR_AGE=300
```

This rejects PM2.5 data older than 300 seconds. Rejected or missing data is not
reported as zero, because zero is a valid clean-air measurement.

## 6. Complete configuration reference

### 6.1 Input and local connection

| Setting | Default | Description |
| --- | --- | --- |
| `SOURCE_STATION` | `1` | Meteobridge station number containing the source sensor |
| `PM25_SENSOR` | `air1pm` | Generic or fully qualified PM2.5 sensor |
| `RH_SENSOR` | `th0hum` | Generic or fully qualified relative-humidity sensor |
| `MAX_SENSOR_AGE` | `300` | Maximum accepted sensor age in seconds |
| `MB_URL` | `http://127.0.0.1` | Local Meteobridge web endpoint |
| `MB_USER` | blank | Optional HTTP username |
| `MB_PASSWORD` | blank | Optional HTTP password |
| `HTTP_TIMEOUT` | `10` | Maximum HTTP query time in seconds |

Local access normally does not require credentials. If credentials are
required, remember that the password is stored as plain text in the
configuration file and protect its permissions accordingly.

### 6.2 AQI calculation

| Setting | Default | Description |
| --- | --- | --- |
| `AQI_STANDARD` | `EPA_2024` | AQI breakpoint set; this is the only supported value |
| `AQI_MODE` | `both` | `instant`, `nowcast`, or `both` |
| `AQI_CAP` | `500` | Maximum published AQI; `999` permits extended Hazardous values |
| `CATEGORY_SOURCE` | `nowcast` | Use `instant` or `nowcast` AQI for the category output |

Instant AQI is an immediate AQI-equivalent calculated directly from the latest
PM2.5 value. It is useful for rapid changes but is not the official EPA
24-hour AQI.

NowCast is the preferred current-health indicator because it uses weighted
hourly concentrations and responds more quickly during changing conditions
than a plain long-term average.

### 6.3 Optional PurpleAir correction

| Setting | Default | Description |
| --- | --- | --- |
| `PURPLEAIR_CORRECTION` | `none` | `none` or `epa_us` |
| `CORRECTION_MISSING_RH` | `reject` | `reject` or `uncorrected` |

Leave correction disabled unless the selected field is raw PurpleAir PM2.5
CF=1 data:

```sh
PURPLEAIR_CORRECTION="none"
```

To apply the EPA U.S.-wide PurpleAir correction:

```sh
PURPLEAIR_CORRECTION="epa_us"
```

For concentrations through 343 micrograms per cubic meter:

```text
corrected PM2.5 = 0.524 × CF1 - 0.0862 × RH + 5.75
```

Above 343 micrograms per cubic meter:

```text
corrected PM2.5 = 0.46 × CF1 + 0.000393 × CF1² + 2.9738
```

Do not enable this merely because the device is a PurpleAir. If PurpleAir or
Meteobridge already corrected the selected value, enabling it here applies a
second correction and produces an incorrect result.

With `CORRECTION_MISSING_RH="reject"`, missing or stale humidity prevents the
sample from being processed. With `uncorrected`, the raw PM2.5 value is used
when humidity is unavailable.

### 6.4 NowCast settings

| Setting | Default | Description |
| --- | --- | --- |
| `NOWCAST_ENABLED` | `yes` | Enables NowCast history and calculation |
| `NOWCAST_HOURS` | `12` | Maximum number of hourly averages, 3 through 24 |
| `NOWCAST_MIN_RECENT` | `2` | Required usable hours among the newest three hours |
| `NOWCAST_REQUIRE_CURRENT` | `no` | Whether the current clock hour must be usable |
| `MIN_HOURLY_COVERAGE` | `75` | Percentage of expected samples needed for an hour |

The first NowCast is not immediate. With the defaults, the plugin needs at
least two usable hours among the latest three and adequate sample coverage.
Depending on the time the plugin starts, the first NowCast normally appears
after approximately one to two hours.

Until then, NowCast outputs are intentionally absent. They are not reported as
zero.

### 6.5 Output sensor assignments

| Setting | Default | Meaning |
| --- | --- | --- |
| `OUTPUT_INSTANT_AQI` | `data0` | Instantaneous AQI-equivalent |
| `OUTPUT_NOWCAST_AQI` | `data1` | EPA particulate NowCast AQI |
| `OUTPUT_CATEGORY` | `data2` | EPA category code |
| `OUTPUT_PM25` | `data3` | Current PM2.5 after optional correction |
| `OUTPUT_NOWCAST_PM25` | `data4` | NowCast PM2.5 concentration |
| `OUTPUT_STATUS` | `data5` | Plugin status code |

Output assignments must be unique and must use `data0` through `data99`.

### 6.6 Operation and storage

| Setting | Default | Description |
| --- | --- | --- |
| `UPDATE_SECONDS` | `60` | Time between source queries |
| `LOG_LEVEL` | `info` | `error`, `warn`, `info`, or `debug` |
| `STATE_DIR` | blank | Optional explicit state directory |
| `LOG_MAX_KB` | `256` | Log rotation threshold in kilobytes |

When `STATE_DIR` is blank, state is stored in a
`meteobridge-aqi-state` directory beside the configuration file. The directory
contains:

| File | Purpose |
| --- | --- |
| `pm25-history.tsv` | Timestamped samples used for NowCast |
| `status.txt` | Last human-readable plugin status |
| `last-output.txt` | Most recent emitted plugin records |
| `meteobridge-aqi.log` | Operational log |

The log rotates to `meteobridge-aqi.log.1` when it exceeds `LOG_MAX_KB`.

## 7. Output sensors and results

The output sensors belong to the User-Defined Plugin station. If the plugin is
Station 4, the default physical sensor names are:

| Meteobridge display | Physical sensor | Meaning |
| --- | --- | --- |
| Data | `data4!0num` | Instantaneous AQI-equivalent |
| Data #1 | `data4!1num` | EPA NowCast AQI |
| Data #2 | `data4!2num` | EPA category code |
| Data #3 | `data4!3num` | Current PM2.5 in micrograms per cubic meter |
| Data #4 | `data4!4num` | NowCast PM2.5 in micrograms per cubic meter |
| Data #5 | `data4!5num` | Plugin status code |

For a different plugin station, replace the station number before `!`. For
example, Station 2 uses `data2!0num` through `data2!5num`.

### 7.1 Example results

The following Station 4 results indicate normal operation:

| Display | Value | Interpretation |
| --- | ---: | --- |
| Data #5 | `0.00` | Plugin is healthy |
| Data | `17.00` | Instantaneous AQI-equivalent is 17 |
| Data #3 | `3.00` | Current PM2.5 is 3.0 micrograms per cubic meter |

An AQI of 17 is in the Good category.

If Data #1, Data #2, and Data #4 are initially absent, this is normally because
NowCast does not yet have enough history. Data #2 also waits when
`CATEGORY_SOURCE="nowcast"`. To publish the category immediately from instant
AQI, use:

```sh
CATEGORY_SOURCE="instant"
```

### 7.2 Category codes

| Code | EPA category | Typical color |
| ---: | --- | --- |
| 0 | Good | Green |
| 1 | Moderate | Yellow |
| 2 | Unhealthy for Sensitive Groups | Orange |
| 3 | Unhealthy | Red |
| 4 | Very Unhealthy | Purple |
| 5 | Hazardous | Maroon |

### 7.3 Status codes

| Code | Meaning | Recommended action |
| ---: | --- | --- |
| 0 | Healthy | No action required |
| 1 | PM2.5 source missing, invalid, stale, or unreachable | Verify source station, PM2.5 name, age, and local endpoint |
| 2 | Humidity unavailable while EPA correction requires it | Verify `RH_SENSOR`, disable correction, or allow uncorrected fallback |
| 3 | Configuration missing, invalid, or state directory unusable | Check filenames, paths, settings, and permissions |

The startup heartbeat initially reports status 1 until the first source query
is validated. It should normally change to 0 within one update interval.

## 8. EPA 2024 PM2.5 breakpoints

PM2.5 is truncated to one decimal place before interpolation. AQI is rounded to
the nearest whole number.

| PM2.5, micrograms per cubic meter | AQI | Category |
| ---: | ---: | --- |
| 0.0 to 9.0 | 0 to 50 | Good |
| 9.1 to 35.4 | 51 to 100 | Moderate |
| 35.5 to 55.4 | 101 to 150 | Unhealthy for Sensitive Groups |
| 55.5 to 125.4 | 151 to 200 | Unhealthy |
| 125.5 to 225.4 | 201 to 300 | Very Unhealthy |
| 225.5 to 325.4 | 301 to 500 | Hazardous |

AQI is capped at 500 by default. Setting `AQI_CAP=999` permits extended
Hazardous values using the same slope as the AQI 301 through 500 segment.

## 9. Optional display template

`aqi-status.template` provides a human-readable Meteobridge template example.
It assumes the AQI plugin is Station 2. If the plugin is Station 4, replace
every `data2!` prefix with `data4!` before using it.

The template shows current PM2.5, instant AQI, NowCast values, plugin status,
and the named EPA category.

## 10. Command-line diagnostics

These commands are optional and require shell access. Run them from the
directory containing the plugin and configuration.

Show the plugin version:

```sh
./meteobridge-aqi.plugin --version
```

Show the resolved source sensor names:

```sh
./meteobridge-aqi.plugin --show-source
```

For the standard Station 1 PurpleAir configuration, the result should include:

```text
PM2.5 sensor: air1!1pm
RH sensor: th1!0hum
```

Fetch and process one live update:

```sh
./meteobridge-aqi.plugin --once
```

Display the last human-readable status:

```sh
./meteobridge-aqi.plugin --status
```

Test a supplied PM2.5 value of 48.7 and humidity of 42 percent:

```sh
./meteobridge-aqi.plugin --sample 48.7 42
```

Clear retained NowCast history:

```sh
./meteobridge-aqi.plugin --reset-history
```

## 11. Troubleshooting

### 11.1 Status remains 1

Check these items in order:

1. Verify the source PM2.5 value under Meteobridge Live Data.
2. Confirm that the source is PM2.5, normally `air1!1pm`, not PM10 at
   `air1!0pm`.
3. Verify that `SOURCE_STATION` identifies the PurpleAir station rather than
   the AQI plugin station.
4. Run `--show-source` and compare the result with Live Data.
5. Confirm that the source age is below `MAX_SENSOR_AGE`.
6. Confirm that `http://127.0.0.1/cgi-bin/template.cgi` is available locally.
7. Check `meteobridge-aqi-state/status.txt` and `meteobridge-aqi.log`.

### 11.2 Meteobridge reports `unexpected 0 bytes`

Version 1.0.1 and later emit a status heartbeat immediately. If a current
version still produces zero bytes, check that:

- The selected plugin is the current `meteobridge-aqi.plugin` file.
- The file is executable and uses Unix line endings.
- Meteobridge is not running an older cached copy.
- The station process was restarted after replacement.

### 11.3 Status is 2

EPA PurpleAir correction is enabled, but humidity is missing, invalid, or
stale. Verify `RH_SENSOR`, or choose one of these configurations:

```sh
PURPLEAIR_CORRECTION="none"
```

or:

```sh
CORRECTION_MISSING_RH="uncorrected"
```

The second option permits output without applying the correction when humidity
is unavailable.

### 11.4 Status is 3

Verify that the configuration is named exactly `meteobridge-aqi.conf`. The
plugin searches:

1. Beside the running plugin
2. `/data/scripts/meteobridge-aqi.conf`
3. `/scripts/meteobridge-aqi.conf`

Also check for invalid configuration values, duplicate output assignments, and
an unwritable `STATE_DIR`.

### 11.5 Instant results appear but NowCast does not

This is normal immediately after installation. With default settings, NowCast
needs at least two sufficiently complete recent hourly averages. Wait up to
approximately two hours before treating it as a fault.

If it still does not appear, inspect the source for gaps and consider whether
`MIN_HOURLY_COVERAGE=75` is appropriate for the update interval and source
reliability.

### 11.6 Values look too low after enabling correction

The most likely cause is double correction. Disable the plugin correction and
compare values:

```sh
PURPLEAIR_CORRECTION="none"
```

Only raw PurpleAir CF=1 data should receive the plugin's `epa_us` correction.

## 12. Updating the plugin

1. Save a backup copy of `meteobridge-aqi.conf`.
2. Replace `meteobridge-aqi.plugin` with the new version.
3. Compare the included configuration with the existing file for new options.
4. Preserve site-specific source names and credentials.
5. Restart or resave the User-Defined Plugin station.
6. Verify that Data #5 changes to 0 and Data #3 contains current PM2.5.

When upgrading from a package that used `PM25_SENSOR="air0pm"`, change it to
`PM25_SENSOR="air1pm"` or the fully qualified `air1!1pm` for PM2.5.

Existing NowCast history can normally be retained. Clear it only when changing
to a different physical PM2.5 source or when the stored history is known to be
invalid.

## 13. Removal

1. Remove or disable the User-Defined Plugin station in Meteobridge.
2. Delete `meteobridge-aqi.plugin` and `meteobridge-aqi.conf` from the scripts
   directory.
3. If historical data and logs are no longer needed, delete the
   `meteobridge-aqi-state` directory.

Removing the plugin does not modify the original PM2.5 station.

## 14. Validation and limitations

- This plugin is not a regulatory monitor.
- Instant AQI is not the official EPA 24-hour AQI.
- Agreement with AirNow is not guaranteed because sensor hardware, siting,
  correction, quality control, and averaging inputs differ.
- A PurpleAir sensor mounted indoors or near a local particle source may not
  represent neighborhood outdoor air.
- Do not replace emergency instructions or medical advice with plugin output.

The included Linux test suite can be run with:

```sh
./tests/run-tests.sh
```

## 15. References

- [EPA AQS AQI breakpoints](https://aqs.epa.gov/aqsweb/documents/codetables/aqi_breakpoints.html)
- [EPA AQI Technical Assistance Document](https://www.airnow.gov/publications/air-quality-index/technical-assistance-document-for-reporting-the-daily-aqi/)
- [EPA extended U.S.-wide PurpleAir correction](https://www.epa.gov/sites/default/files/2021-05/documents/toolsresourceswebinar_purpleairsmoke_210519b.pdf)
- [Meteobridge template variables](https://www.meteobridge.com/wiki/index.php/Templates)

## 16. License

MIT. See `LICENSE`.
