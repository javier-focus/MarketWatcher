# MarketWatcher

MarketWatcher is a lightweight macOS desktop widget that displays live market data for the indices you care about — S&P 500, Nasdaq, Dow Jones, Russell 2000, VIX, and Bitcoin — in a floating panel that sits above your desktop icons and stays visible at all times. It auto-refreshes every 5 minutes, remembers your last selected index and interval across launches, and renders a sparkline chart with color-coded gain/loss indicators, all without requiring an API key.

---

## Features

- **Six market indices** — S&P 500, Nasdaq 100, Dow Jones, Russell 2000, VIX, and Bitcoin (BTC-USD)
- **Four time intervals** — 1 Day, Week-to-Date, Month-to-Date, and Year-to-Date
- **Live sparkline chart** — area chart with dynamic bar resolution (5 min / 1 hr / 1 day) matched to the selected interval
- **Floating always-on-top panel** — sits above desktop icons, below normal app windows; never hides when focus moves away
- **Multiple widgets** — double-click the app to open additional independent panels, each with its own index and interval
- **Right-click to quit** — right-click anywhere on a widget to reveal a Quit menu item
- **Auto-refresh** — silent background refresh every 5 minutes with a subtle spinner overlay (no full reload flicker)
- **Persistent selection** — last-used index and interval survive app restarts via `UserDefaults`
- **Sticky price display** — the large price number stays visible and stable during interval switches while the chart re-fetches
- **Human-readable errors** — connection errors, rate limiting (with exponential back-off), and market-closed states all surface as plain-language messages
- **No API key required** — data sourced from Yahoo Finance's public chart endpoint

---

## Requirements

- **macOS 13 (Ventura)** or later
- **Xcode 15** or later
- No API key, no account, no dependencies to install

---

## How to Run

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourname/marketwatcher.git
   cd marketwatcher
   ```

2. **Open the package in Xcode**
   ```bash
   open MarketWatcher/Package.swift
   ```
   Xcode will resolve the package and generate schemes automatically.

3. **Select the correct scheme**
   In the Xcode toolbar, open the scheme picker and select **MarketWatcher**.
   Make sure the destination is **My Mac**.

4. **Set your signing team** *(first run only)*
   - In the Project navigator, select the `MarketWatcher` package.
   - Go to **Signing & Capabilities** for the `MarketWatcherApp` target.
   - Under **Signing**, choose your personal team from the dropdown.
   - Set the Bundle Identifier to `com.yourname.marketwatcher` (replace `yourname`).

5. **Run**
   Press **⌘R**. The widget panel appears in the top-left corner of your screen.
   Drag it anywhere — its position is saved automatically.

---

## How to Run Tests

### In Xcode
Press **⌘U**. All tests run and results appear in the Test Navigator.
Expected output: **32 tests passing, 0 failures**.

### From the command line
```bash
cd MarketWatcher
swift test
```

Expected output:
```
Test Suite 'All tests' passed.
  Executed 32 tests, with 0 failures (0 unexpected) in X.XXX seconds
```

The test suite covers:
- `MarketViewModelTests` — state transitions, interval/index switching, error handling, retain-cycle safety (10 tests)
- `YahooFinanceServiceTests` — JSON decoding, baseline price rules, network/decoding errors, market-closed handling (8 tests)
- `TimeIntervalTests` — `startDate()` calculations for all four intervals across boundary conditions (14 tests)

---

## Architecture

MarketWatcher is structured in four layers, each with a single responsibility:

```
Models → Networking → ViewModel → Views
```

| Layer | Files | Responsibility |
|---|---|---|
| **Models** | `ChartInterval`, `MarketIndex`, `QuoteData` | Define the domain types — intervals, index symbols, price points, and quotes |
| **Networking** | `YahooFinanceService` | Fetch and decode Yahoo Finance chart responses; translate raw JSON into `Quote` values |
| **ViewModel** | `MarketViewModel` | Own app state (`ViewState`), drive Combine-based reactive reloads, manage auto-refresh scheduling |
| **Views** | `ContentView`, `PriceHeaderView`, `SparklineChartView`, `IntervalSelectorView` | Render state as SwiftUI views; delegate all decisions upward to the ViewModel |

The app shell (`AppDelegate`, `MarketWatcherApp`) lives in a separate executable target that imports the library, keeping the panel/window code isolated from the UI logic.

This project was built using a **Plan → Code → Verify** methodology: each feature was designed as a written plan before any code was written, implemented in a single focused change, and verified with a full test run before moving to the next feature.

---

## How to Add a New Index

Adding a new market index requires exactly **one file change**:

1. **Open `Sources/SP500Widget/Models/MarketIndex.swift`**

2. **Add a new case** with the Yahoo Finance symbol as the raw value:
   ```swift
   case nikkei = "^N225"
   ```
   Then add its `displayName` to the `switch` in the `displayName` property:
   ```swift
   case .nikkei: return "Nikkei 225"
   ```
   If the index trades around the clock (like crypto), also return `true` from `tradesAroundTheClock`.

3. **Build and run** — the new index appears automatically in the dropdown picker.
   No changes needed in `YahooFinanceService`, `MarketViewModel`, or any view.

---

## Building a Release DMG

A `build_release.sh` script is provided to produce a distributable `.dmg` from the command line.

### Prerequisites

- Xcode command-line tools installed (`xcode-select --install`)
- A valid signing identity in your Keychain (automatic signing configured in Xcode)

### Steps

```bash
# From the repository root:
chmod +x scripts/build_release.sh
./scripts/build_release.sh
```

The script will:
1. Clean the previous build
2. Compile in Release configuration via `swift build`
3. Assemble the `.app` bundle and apply an ad-hoc code signature
4. Wrap it in a compressed DMG

On success the output path and file size are printed:
```
✅  Build complete!
📂  ./build/MarketWatcher.dmg  (360K)
```

To distribute, share `./build/MarketWatcher.dmg`. Recipients open the DMG and drag **MarketWatcher.app** to their Applications folder.

> **Note:** For distribution outside the Mac App Store without notarization, recipients may need to right-click → Open the first time they launch the app to bypass Gatekeeper.

---

## License

MIT — see [LICENSE](LICENSE).
