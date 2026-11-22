# Tatweer (Advisor v1) — Project Documentation

> **⚠️ Build Note:** The `mssql_connection` package does not work in **Release mode**. Always build using **Profile mode** for users: `flutter build apk --profile`

---

## What This App Does

This is a mobile app for salesmen in the field. They use it to:
- Record **sales bills** when they sell items to clients
- Record **purchase bills** when they buy items from sellers
- Record **cash collections** when they collect money from clients
- Transfer items between branches using **exchange bills**
- Add new **clients, items, and sellers** to the system

Everything works **offline**. Data saves to the phone first, then automatically uploads to the company's SQL Server when internet is available.

---

## How It Works (The Big Picture)

```
User does something (e.g. creates a bill)
    → Saved to phone (SQLite) with Synced = 0
    → When internet is detected:
        → Uploaded to SQL Server
        → Local record updated to Synced = 1
```

The app also **pulls** fresh data from the server (clients list, items, prices, etc.) to keep the phone up to date.

---

## Session Rule

In `main.dart`, the app checks every minute if the user has been inactive. If the last action was more than **2 hours** ago, it:
1. Syncs any pending data to the server
2. Clears the session
3. Sends the user back to the login screen
4. Shows a "session expired" dialog

---

## Screens — What Each One Does

### Entry & Navigation

| Screen | What it does |
|--------|-------------|
| `main.dart` | Starts the app. Sets up the database, Arabic language, and internet monitoring. Controls the 2-hour session timeout. Decides whether to show login or home screen. |
| `login_screen.dart` | User enters their ID or username to log in. Connects to the server to verify credentials. After login, downloads all master data (clients, items, categories, etc.) to the phone. |
| `home_screen.dart` | The main menu. Shows a welcome card with the user's name and whether they're online or offline. Has buttons to go to Sales, Purchases, Collections, Exchange, Coding, and Inventory. |

### Sales (`features/sells/`)

| Screen | What it does |
|--------|-------------|
| `sells_screen.dart` | Shows all of today's sales bills in two tabs: **Synced** (uploaded to server) and **Unsynced** (still on phone only). Has buttons to manually sync and to create a new bill. |
| `new_sells_bill_screen.dart` | Form to create a new sale. User picks a client, adds items, enters discount and paid amount. The app calculates totals automatically. Saves to the phone and tries to upload. |
| `sells_bill_details_screen.dart` | Opens an existing bill to view or edit it. User can change the discount, paid amount, or items. Can also lock the bill (to prevent further edits) and export it as a PDF. |
| `add_item_for_sells_screen.dart` | Opened from the bill screen. User picks a category, then an item, chooses the unit size and pricing type, enters quantity. Items are added to a cart and sent back to the bill screen. |
| `inventory_screen.dart` | Shows current stock levels for items in the user's branch. Can filter by category and search by name. |

### Purchases (`features/buys/`)

| Screen | What it does |
|--------|-------------|
| `buys_screen.dart` | Same layout as sells screen. Lists today's purchase bills in Synced/Unsynced tabs. |
| `new_buys_bill_screen.dart` | Form to create a new purchase from a seller. Same flow as sales but tracks supplier purchases. |
| `buys_bill_details_screen.dart` | View or edit an existing purchase bill. Same features as sells details (edit, lock, PDF). |
| `add_item_for_buys_screen.dart` | Item picker for purchase bills. Same cart concept as sells. |

### Collections (`features/collections/`)

| Screen | What it does |
|--------|-------------|
| `collections_screen.dart` | Lists today's cash collections. Synced/Unsynced tabs. |
| `new_collection_screen.dart` | Form to record a cash collection. User picks a client, enters the amount and optional notes. |
| `collection_details_screen.dart` | View or edit a collection. Can change amount, notes, lock it, or export as PDF. |

### Exchange (`features/exchange/`)

| Screen | What it does |
|--------|-------------|
| `exchange_screen.dart` | Lists today's exchange (transfer) bills. Synced/Unsynced tabs. |
| `new_exchange_bill_screen.dart` | Form to create an item transfer. User selects source and destination branches, then adds items. |
| `exchange_bill_details_screen.dart` | View or edit an exchange bill. |
| `add_item_for_exchange_screen.dart` | Item picker for exchange bills. |

### Coding / Master Data (`features/coding/`)

| Screen | What it does |
|--------|-------------|
| `coding_screen.dart` | Menu to choose what to add: new client, new item, or new seller. |
| `add_new_client_screen.dart` | Form to register a new client (name, phone, address, region). Pushes directly to the server. |
| `add_new_item_screen.dart` | Form to add a new item to the catalog (name, category, prices). Pushes directly to the server. |
| `add_new_seller_screen.dart` | Form to add a new seller/supplier. Pushes directly to the server. |

---

## Widgets — Reusable UI Parts

| Path | Files | What they do |
|------|-------|-------------|
| `widgets/shared/` | `autocomplete_field`, `action_button`, `loading_overlay`, `tab_content_builder`, `info_row`, `connection_status`, `custom_app_bar`, `custom_text_field`, `responsive_button`, `responsive_container` | Common components used across the whole app: text inputs, buttons, loading spinners, tab layouts, etc. |
| `widgets/bill/` | `bill_header`, `items_table` | Bill-specific widgets: the top section showing totals/calculations, and the items list/table below it. |
| `widgets/collection/` | `collection_header` | Collection-specific widget: shows amount and notes with edit fields. |

---

## Utils — Shared Helpers

| File | What it does |
|------|-------------|
| `app_colors.dart` | All color constants in one place (primary, success, error, warning, etc.) |
| `app_styles.dart` | Text styles, spacing values, field decorations — all responsive to screen size |
| `constants.dart` | Database connection config (server host, port, database name) |
| `helpers.dart` | `getSafeString()` and `getSafeDouble()` — safely convert database values that might be null or wrong type |
| `snackbars.dart` | Pop-up messages: error (red), success (green), info (blue), offline warning |

---

## Services — Data Layer (Handover)

### `local_db_service.dart` — The Phone Database

This is a **singleton** (`LocalDbService.instance`). It manages the SQLite database on the device.

**Tables that only get READ locally** (filled from server during sync):

`Region`, `Clients`, `Sellers`, `STRCategory`, `STRItems`, `Settings`, `Branchs`, `vw_Inventory_AllBranches_Current`, `ClientBranchs`

**Tables that get WRITTEN locally** (created by the user, uploaded to server):

| Table | What it stores | Important columns |
|-------|---------------|-------------------|
| `SellsBills` | Sales bill headers | ClientId, Total, PaiedForien, Discount, NetTotal, GrandTotal, Rest, Lock, Settlement |
| `Sells` | Items inside a sales bill | BillId, ItemId, Qty, Price, Total, QtyUnit, Pricing, Type |
| `BuysBills` | Purchase bill headers | SellerId, Total, Paied, Discount, Type |
| `Buys` | Items inside a purchase bill | BillId, ItemId, Qty, Price, Serial, SerialType |
| `ExchangeBills` | Exchange/transfer bill headers | BranchId, DestBranchId, Total |
| `Exchange` | Items inside an exchange bill | BillId, ItemId, Qty, BranchId, DestBranchId |
| `ClientsPaying` | Cash collections | ClientId, Amount, Notes |

**Every write table has these tracking columns:**
- `Synced` → `0` means not yet uploaded, `1` means uploaded to server
- `LocalUuid` → a temporary ID used until the server assigns a real ID
- `Lock` → `'Lock'` means the record can't be edited anymore, `NULL` means editable

**The main operations follow this pattern:**
- **Create**: `createLocalBill()` → saves with `Synced=0`, `Bill=NULL`, generates a `LocalUuid`
- **Update**: `updateBillTotalPaiedAndLock()` → changes fields, resets `Synced=0` so it gets re-uploaded
- **Read**: `getUserSellsBills()`, `getPendingSellsBills()` → queries filtered by user ID and/or sync status
- **Post-sync ID fix**: `updateBillIdAndNumberByLocalUuid()` → after the server assigns a real ID, this replaces the temporary local ID in both the bill table AND all linked item rows

### `sync_service.dart` — The Upload/Download Engine

This is a **singleton** (`SyncService.instance`). It sits between `local_db_service` and `remote_db_service`.

**Downloading (Server → Phone):**
- `syncUserData()` — downloads all master data tables (clients, items, categories, regions, prices, branches, sellers) and replaces the local copies
- `fetchUserSellsBills()` — gets today's bills from the server, stores them locally, merges with any unsynced local bills, and returns the combined list. Same pattern exists for buys, exchange, and collections.
- `getClientBalance()` / `getSellerBalance()` — gets account balance from server views

**Uploading (Phone → Server):**
- `syncPendingToServer()` — this is the main upload function. It runs these steps in order:

**For a NEW bill (Bill number is NULL):**
1. Asks the server: what's the highest bill number? (`SELECT MAX(Bill)`)
2. Adds 1 to get the next bill number
3. Inserts the bill on the server, gets back the server-assigned ID
4. Updates the local record: replaces the temporary LocalUuid-based ID with the real server ID, sets `Synced=1`
5. Inserts all the bill's items on the server
6. Marks the items as `Synced=1` locally

**For an EDITED bill (Bill number exists):**
1. Updates the bill fields on the server (`UPDATE ... WHERE Id=X`)
2. Deletes old items from the server, inserts the new ones
3. Marks everything as `Synced=1` locally

This same pattern (new insert vs. edit update) applies to all bill types and collections.

### `remote_db_service.dart` — SQL Server Connection

Singleton. Wraps the `mssql_connection` package. Two main methods:
- `getData(query)` — runs a SELECT, returns rows
- `writeData(query)` — runs INSERT/UPDATE/DELETE

Stores connection parameters (host, port, database, user, password) in SharedPreferences.

### `pdf_service.dart` — PDF Export

Generates Arabic RTL PDF documents using the Amiri font. Creates formatted invoices for bills (with company header, items table, and totals) and receipts for collections.

---

## Key Concepts at a Glance

| Concept | Meaning |
|---------|---------|
| `Synced = 0` | Data exists only on the phone, waiting to be uploaded |
| `Synced = 1` | Data has been successfully uploaded to the server |
| `Lock = 'Lock'` | Record is frozen — user printed or exported it, no more edits allowed |
| `LocalUuid` | Temporary ID for records created offline. Gets replaced with a real server ID after sync. |
| **2-hour session** | If no user activity for 2 hours, app logs out automatically |
| **4 AM day boundary** | Server queries treat 4 AM as the start of a new day (bills after midnight belong to the previous day) |

---

## Packages

| Package | What it's for |
|---------|--------------|
| `sqflite` | Local SQLite database on the phone |
| `mssql_connection` | Connecting to the company's SQL Server |
| `connectivity_plus` | Detecting when internet is available |
| `shared_preferences` | Storing login session and connection settings |
| `easy_localization` | Arabic language and RTL layout |
| `pdf` + `printing` | Creating and printing PDF documents |
| `uuid` | Generating unique IDs for offline records |
| `google_fonts` | App typography |
| `share_plus` | Sharing PDF files |
| `path_provider` | Finding file paths on the device |
