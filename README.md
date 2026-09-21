# Government GIS Map

A Flutter-based GIS field data collection application built using the ArcGIS Maps SDK for Flutter and ArcGIS Online.

The application enables users to view and interact with GIS maps, collect and edit spatial features, capture locations using GNSS/GPS, work with maps and data offline, attach files to features, and synchronize collected data with ArcGIS Online.

---

## Overview

The application is designed for field-based GIS data collection and editing.

Users can:

- View GIS maps and operational layers
- Switch between different basemaps
- Identify and inspect existing GIS features
- Create new GIS features
- Select a location manually from the map
- Capture the current device/GNSS location
- Edit existing features
- Copy existing features
- Collect a new feature at an existing feature's location
- Enter and edit feature attributes
- Add attachments to features
- Download maps for offline use
- Create and edit features while offline
- Synchronize offline changes with ArcGIS Online
- Connect to external GNSS receivers using NMEA data

---

## Key Features

### Map

- ArcGIS map visualization
- Current location display
- Map navigation and zoom
- Operational layer management
- Basemap selection
- Feature identification
- Feature popups

### Feature Collection

- Create new features
- Manual map-center location selection
- Current location based feature creation
- Dynamic attribute forms
- Date and time fields
- Verification status
- Feature attachments
- Feature submission

### Feature Editing

- Edit existing features
- Update feature attributes
- Update feature geometry/location
- Copy existing features
- Collect a new feature at an existing feature's location

### Offline GIS

- Download offline map areas
- Use downloaded maps without internet connectivity
- Create features offline
- Edit features offline
- Add attachments while offline
- Synchronize offline changes when connectivity is restored

### GNSS / DGPS

The application supports NMEA-based GNSS positioning.

The GNSS architecture supports:

- Device location
- Mock NMEA data for development/testing
- Bluetooth-based external GNSS receivers
- USB serial GNSS receiver integration
- NMEA 0183 data processing
- Position information
- Satellite information
- Fix information
- Accuracy information

The application is designed to work with external GNSS receivers that provide compatible NMEA data through the supported communication transport.

---

## Technology Stack

| Technology | Purpose |
|---|---|
| Flutter | Cross-platform application development |
| Dart | Application programming language |
| ArcGIS Maps SDK for Flutter | GIS map and feature functionality |
| ArcGIS Online | GIS services, web maps and feature services |
| Flutter BLoC | State management |
| NMEA 0183 | GNSS positioning data |
| Bluetooth SPP | External GNSS receiver communication |
| USB Serial | External GNSS receiver communication |
| Offline Geodatabase | Offline GIS data |
| ArcGIS Offline Maps | Offline map workflow |

---

## Project Architecture

The application follows a layered architecture with separation between presentation, business logic, data sources and repositories.

```text
Presentation
    |
    ├── Pages
    ├── Widgets
    └── BLoC
         |
         ▼
Domain
    |
    ├── Entities
    ├── Repository Interfaces
    └── Use Cases
         |
         ▼
Data
    |
    ├── Repositories
    ├── Remote Data Sources
    ├── Local Data Sources
    └── GNSS / NMEA Data Sources
         |
         ▼
External Services
    |
    ├── ArcGIS Online
    ├── ArcGIS Feature Services
    ├── Offline Geodatabases
    └── GNSS Receivers
```
