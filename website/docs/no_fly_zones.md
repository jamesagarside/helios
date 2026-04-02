# No-Fly Zones

Helios supports three sources of no-fly zone (NFZ) and restricted airspace data:

1. **OpenAIP live fetch** — real-time regulatory airspace from the OpenAIP API
2. **GeoJSON file import** — import any GeoJSON airspace file manually
3. **User-drawn NFZs** — draw custom planning overlays that stay local and are never sent to the flight controller

All three sources are combined on the Plan View map and used for waypoint conflict detection.

---

## OpenAIP Live Fetch

**Platform**: macOS, Linux, Windows, iOS, Android (requires internet connection)

OpenAIP provides free global airspace data via their REST API. You need a free API key from [openaip.net](https://www.openaip.net).

### Setup

1. Register for a free account at openaip.net and copy your API key.
2. In the Plan View, tap the **cloud download** (Fetch Airspace) button in the map controls.
3. If no API key is stored, a dialog will prompt you to enter it. The key is saved to local preferences.
4. Helios fetches all airspace zones for the current map viewport.

### Caching

Fetched data is cached locally for **7 days** in the app support directory (`airspace_cache/`). Subsequent fetches for the same area within 7 days return the cached copy without a network request.

### Airspace colours

| Colour | Airspace types |
|---|---|
| Red | Prohibited (P), Restricted (R) |
| Amber | Danger (D), TFR, Alert, Warning |
| Blue | CTR, TMA, Class A–E |
| Grey | Class F–G, Other |

### Altitude filtering

Zones are fetched for the current map bounds regardless of altitude. Future versions will add altitude-based filtering.

---

## GeoJSON File Import

**Platform**: macOS, Linux, Windows (file picker; limited on iOS/Android)

Tap the **layers** button in the Plan View map controls to import one or more `.geojson` / `.json` files. Both OpenAIP v1 export format and standard GeoJSON FeatureCollections are supported.

Tap **layers_clear** to remove all imported zones.

---

## User-Drawn NFZs

**Platform**: All

Draw custom no-fly zones as local planning overlays. These are **never sent to the flight controller** — they are planning aids only.

### How to draw

1. Tap the **pentagon** (Draw NFZ) button in the map controls.
2. Tap the map to place polygon vertices. A live preview shows the in-progress polygon.
3. Once you have 3+ points, tap **Close** to complete the polygon.
4. Enter a name for the NFZ in the dialog.

The NFZ is displayed as a dashed orange border on the map.

### Management

- Tap **Clear custom NFZ** to remove all user-drawn zones.
- Custom NFZs are saved to `{appSupportDir}/custom_nfz.json` and loaded on startup.

### Colour options

When creating a zone, you can choose: `red`, `orange`, or `yellow`.

---

## Waypoint Conflict Detection

Helios automatically checks all mission waypoints against loaded restricted airspace (Prohibited and Restricted zones from any source).

- **Conflicting waypoints** are highlighted on the map with a red danger badge.
- The info bar at the bottom of the Plan View shows a warning count: _"N wps in restricted airspace"_.
- Conflict detection runs live as you move waypoints or load new airspace.

---

## Platform Notes

| Feature | macOS | Linux | Windows | iOS | Android |
|---|:---:|:---:|:---:|:---:|:---:|
| OpenAIP live fetch | ✅ | ✅ | ✅ | ✅ | ✅ |
| GeoJSON file import | ✅ | ✅ | ✅ | ⚠️ | ⚠️ |
| User-drawn NFZs | ✅ | ✅ | ✅ | ✅ | ✅ |
| Conflict detection | ✅ | ✅ | ✅ | ✅ | ✅ |

⚠️ File picker on iOS/Android has platform restrictions — GeoJSON import may require files to be in the app's Documents directory.
